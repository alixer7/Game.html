"""Exercise the real transformers code paths (brain + LoRA training collator) with a TINY, randomly
initialised Qwen3-VL built locally — no downloads. Verifies wiring, not quality."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "training"))

torch = pytest.importorskip("torch")
transformers = pytest.importorskip("transformers")
pytest.importorskip("tokenizers")

CHAT_TEMPLATE = (
    "{% for message in messages %}<|im_start|>{{ message['role'] }}\n"
    "{% if message['content'] is string %}{{ message['content'] }}{% else %}"
    "{% for c in message['content'] %}{% if c['type'] == 'image' %}<|vision_start|><|image_pad|><|vision_end|>"
    "{% elif c['type'] == 'text' %}{{ c['text'] }}{% endif %}{% endfor %}{% endif %}<|im_end|>\n"
    "{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}"
)
SPECIAL = ["<|endoftext|>", "<|im_start|>", "<|im_end|>", "<|vision_start|>", "<|vision_end|>",
           "<|image_pad|>", "<|video_pad|>"]


@pytest.fixture(scope="module")
def tiny_dir(tmp_path_factory):
    try:
        from transformers import Qwen3VLConfig, Qwen3VLForConditionalGeneration, Qwen3VLProcessor
    except ImportError:
        pytest.skip("transformers without Qwen3-VL")
    from tokenizers import Tokenizer, decoders, models, pre_tokenizers, trainers
    from transformers import AutoImageProcessor, PreTrainedTokenizerFast

    d = tmp_path_factory.mktemp("tiny_qwen3vl")
    tok = Tokenizer(models.BPE(unk_token=None))
    tok.pre_tokenizer = pre_tokenizers.ByteLevel(add_prefix_space=False)
    tok.decoder = decoders.ByteLevel()
    corpus = ['{"name":"chair","parts":[{"id":"seat","type":"box","size":[0.4,0.4,0.05]}]}',
              "REQUEST: كرسي خشبي مع وسادة زرقاء", "scores adherence proportions overall issues patch"] * 20
    tok.train_from_iterator(corpus, trainers.BpeTrainer(vocab_size=600, special_tokens=SPECIAL,
                                                        initial_alphabet=pre_tokenizers.ByteLevel.alphabet()))
    fast = PreTrainedTokenizerFast(tokenizer_object=tok, eos_token="<|im_end|>", pad_token="<|endoftext|>",
                                   additional_special_tokens=SPECIAL[1:])
    try:
        image_proc = AutoImageProcessor.from_pretrained  # noqa: F841  (just to keep import used)
        from transformers import Qwen2VLImageProcessorFast as IP
    except ImportError:
        from transformers import Qwen2VLImageProcessor as IP
    ip = IP(patch_size=16, merge_size=2, temporal_patch_size=2, min_pixels=32 * 32, max_pixels=128 * 128,
            image_mean=[0.5, 0.5, 0.5], image_std=[0.5, 0.5, 0.5])
    try:
        from transformers import Qwen3VLVideoProcessor
        vp = Qwen3VLVideoProcessor(patch_size=16, merge_size=2, temporal_patch_size=2)
    except ImportError:
        vp = None
    proc = Qwen3VLProcessor(image_processor=ip, tokenizer=fast, video_processor=vp, chat_template=CHAT_TEMPLATE)
    proc.save_pretrained(d)
    vocab = len(fast)
    cfg = Qwen3VLConfig(
        text_config=dict(vocab_size=vocab, hidden_size=64, intermediate_size=128, num_hidden_layers=2,
                         num_attention_heads=4, num_key_value_heads=2, head_dim=16, max_position_embeddings=4096,
                         rope_scaling={"rope_type": "default", "mrope_section": [2, 3, 3], "mrope_interleaved": True}),
        vision_config=dict(depth=2, hidden_size=32, intermediate_size=64, num_heads=2, patch_size=16,
                           spatial_merge_size=2, temporal_patch_size=2, out_hidden_size=64,
                           deepstack_visual_indexes=[0], num_position_embeddings=64),
        image_token_id=fast.convert_tokens_to_ids("<|image_pad|>"),
        video_token_id=fast.convert_tokens_to_ids("<|video_pad|>"),
        vision_start_token_id=fast.convert_tokens_to_ids("<|vision_start|>"),
        vision_end_token_id=fast.convert_tokens_to_ids("<|vision_end|>"),
        tie_word_embeddings=True)
    torch.manual_seed(0)
    Qwen3VLForConditionalGeneration(cfg).save_pretrained(d)
    return d


def _img(path: Path, color=(200, 80, 40)):
    from PIL import Image
    Image.new("RGB", (96, 64), color).save(path)
    return path


def test_qwen_brain_chat_with_image(tiny_dir, tmp_path):
    from mujassam.brain.qwen_vl import QwenVLBrain
    from mujassam.brain.prompts import critic_messages

    brain = QwenVLBrain(str(tiny_dir), quantization="none", device_map="cpu", torch_dtype="float32")
    assert 50_000 < brain.num_parameters() < 5_000_000
    msgs = critic_messages("كرسي", _img(tmp_path / "grid.png"), '{"parts":[]}', "faces=10",
                           checklist=["blue cushion"], reference=_img(tmp_path / "ref.png", (10, 10, 200)))
    out = brain.chat(msgs, max_new_tokens=8, temperature=0)
    assert isinstance(out, str)
    out2 = brain.chat(msgs, max_new_tokens=8, temperature=0.7, seed=1)
    assert isinstance(out2, str)


def test_sft_collator_masks_prompt_and_trains(tiny_dir, tmp_path):
    from sft_lora import Collator
    from transformers import AutoModelForImageTextToText, AutoProcessor

    from mujassam.brain import prompts as P

    proc = AutoProcessor.from_pretrained(tiny_dir)
    img = _img(tmp_path / "photo.png")
    answer = {"name": "chair", "parts": [{"id": "seat", "type": "box"}]}

    def row(msgs, ans):
        ser = []
        for m in msgs:
            c = m["content"]
            ser.append({"role": m["role"], "content": c if isinstance(c, str) else
                        [x if x["type"] == "text" else {"type": "image", "image": str(x["image"])} for x in c]})
        return {"messages": ser + [{"role": "assistant", "content": json.dumps(ans)}]}

    batch = [row(P.planner_messages("", None, img, few_shot=False), answer),
             row(P.router_messages("a chair"), {"subject": "chair"})]
    out = Collator(proc, max_len=60_000, max_image_side=96)(batch)   # tiny vocab -> long sequences
    lab = out["labels"]
    assert lab.shape == out["input_ids"].shape
    # only the answer is supervised
    n_sup = int((lab[0] != -100).sum())
    ans_len = len(proc.tokenizer(json.dumps(answer))["input_ids"])
    assert ans_len <= n_sup <= ans_len + 4
    assert "pixel_values" in out and "image_grid_thw" in out and out["image_grid_thw"].shape[0] == 1
    model = AutoModelForImageTextToText.from_pretrained(tiny_dir)
    loss = model(**out).loss
    assert torch.isfinite(loss)
    loss.backward()


def test_package_roundtrip_with_lora(tiny_dir, tmp_path):
    peft = pytest.importorskip("peft")
    from transformers import AutoModelForImageTextToText

    from mujassam.brain.qwen_vl import QwenVLBrain
    from mujassam.model import CONFIG_NAME, MujassamConfig, MujassamModel

    # make a (random) LoRA adapter for the tiny model
    base = AutoModelForImageTextToText.from_pretrained(tiny_dir)
    from sft_lora import LM_TARGETS
    lora = peft.get_peft_model(base, peft.LoraConfig(r=4, lora_alpha=8, target_modules=LM_TARGETS))
    lora.save_pretrained(tmp_path / "adapter")

    cfg = MujassamConfig(brain_model=str(tiny_dir), brain_quantization="none", recon_backend="none",
                         brain_lora=str(tmp_path / "adapter"))
    brain = QwenVLBrain(str(tiny_dir), quantization="none", device_map="cpu", torch_dtype="float32",
                        lora=str(tmp_path / "adapter"))
    m = MujassamModel(cfg, brain)
    n_before = m.num_parameters()["brain"]
    pkg = m.save_pretrained(tmp_path / "pkg")
    assert (pkg / CONFIG_NAME).exists() and (pkg / "brain_lora").is_dir() and (pkg / "MODEL_CARD.md").exists()
    sd_keys = json.loads((pkg / "brain" / "model.safetensors.index.json").read_text())["weight_map"] \
        if (pkg / "brain" / "model.safetensors.index.json").exists() else None
    from safetensors import safe_open
    with safe_open(str(pkg / "brain" / "model.safetensors"), "pt") as f:
        keys = list(f.keys()) if sd_keys is None else list(sd_keys)
    assert not any("lora_" in k or "base_layer" in k for k in keys)   # clean base weights

    # the in-memory model still has its adapter, and re-saving in place works
    assert hasattr(m.brain.model, "peft_config")
    m.save_pretrained(pkg)

    m2 = MujassamModel.from_pretrained(str(pkg), load_recon=False)
    assert m2.config.brain_lora == str(pkg / "brain_lora")
    assert m2.num_parameters()["brain"] == n_before
    assert isinstance(m2.brain.chat([{"role": "user", "content": "hi"}], max_new_tokens=3, temperature=0), str)

    # merged export (what GGUF conversion starts from)
    merged = m2.save_pretrained(tmp_path / "merged", merge_lora=True)
    assert not (merged / "brain_lora").exists()
    m3 = MujassamModel.from_pretrained(str(merged), load_recon=False)
    assert m3.config.brain_lora is None


def test_sft_script_end_to_end(tiny_dir, tmp_path, monkeypatch):
    pytest.importorskip("peft")
    import sft_lora

    from mujassam.brain import prompts as P
    rows = []
    for i in range(3):
        img = _img(tmp_path / f"p{i}.png", (40 * i, 100, 200))
        msgs = P.planner_messages("", None, img, few_shot=False)
        ser = [{"role": m["role"], "content": m["content"] if isinstance(m["content"], str) else
                [x if x["type"] == "text" else {"type": "image", "image": str(x["image"])} for x in m["content"]]}
               for m in msgs]
        rows.append({"task": "planner_image", "messages": ser + [{"role": "assistant", "content": '{"parts":[]}'}]})
    data = tmp_path / "train.jsonl"
    data.write_text("\n".join(json.dumps(r) for r in rows))
    out = tmp_path / "lora"
    monkeypatch.setattr(sys, "argv", ["sft_lora.py", "--data", str(data), "--out", str(out), "--model", str(tiny_dir),
                                      "--no-4bit", "--epochs", "1", "--grad-accum", "1", "--max-len", "60000",
                                      "--rank", "4", "--alpha", "8", "--workers", "0"])
    monkeypatch.setenv("CUDA_VISIBLE_DEVICES", "")
    sft_lora.main()
    assert (out / "adapter_config.json").exists() and (out / "mujassam_lora.json").exists()
