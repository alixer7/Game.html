"""Specialise the brain (Qwen3-VL) on Mujassam tasks with QLoRA.

Input: one or more JSONL files from synth_data.py / self_improve.py:
    {"task": "...", "messages": [{"role": ..., "content": str | [{"type": "text"|"image", ...}]}, ...]}
Only the final assistant message is trained (prompt tokens are masked with -100).

A T4 (16 GB, free Colab) fits Qwen3-VL-4B in 4-bit with LoRA r=32, batch 1, grad-accum 8.

usage:
  python training/sft_lora.py --data data/synth/train.jsonl --out runs/mujassam-lora \
      --model Qwen/Qwen3-VL-4B-Instruct --epochs 2
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Any

LM_TARGETS = r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$"


def load_rows(paths: list[str], max_rows: int | None, seed: int) -> list[dict[str, Any]]:
    rows = []
    for p in paths:
        with open(p, encoding="utf-8") as f:
            rows += [json.loads(line) for line in f if line.strip()]
    random.Random(seed).shuffle(rows)
    return rows[:max_rows] if max_rows else rows


class Collator:
    def __init__(self, processor, max_len: int, max_image_side: int):
        self.p = processor
        self.max_len = max_len
        self.max_side = max_image_side
        self.pad_id = processor.tokenizer.pad_token_id or processor.tokenizer.eos_token_id

    def _conv(self, messages):
        from PIL import Image
        images, conv = [], []
        for m in messages:
            c = m["content"]
            if isinstance(c, str):
                conv.append({"role": m["role"], "content": [{"type": "text", "text": c}]})
                continue
            items = []
            for it in c:
                if it["type"] == "image":
                    im = Image.open(it["image"]).convert("RGB")
                    s = self.max_side / max(im.size)
                    if s < 1:
                        im = im.resize((int(im.width * s), int(im.height * s)))
                    images.append(im)
                    items.append({"type": "image"})
                else:
                    items.append({"type": "text", "text": it["text"]})
            conv.append({"role": m["role"], "content": items})
        return conv, images

    def __call__(self, batch):
        import torch
        ids, labels, extras, seq_extras = [], [], {}, {}
        for row in batch:
            conv, images = self._conv(row["messages"])
            full = self.p.apply_chat_template(conv, tokenize=False, add_generation_prompt=False)
            prompt = self.p.apply_chat_template(conv[:-1], tokenize=False, add_generation_prompt=True)
            enc = self.p(text=[full], images=images or None, return_tensors="pt")
            n_prompt = self.p(text=[prompt], images=images or None, return_tensors="pt")["input_ids"].shape[1]
            x = enc["input_ids"][0][: self.max_len]
            y = x.clone()
            y[:n_prompt] = -100
            if n_prompt >= len(x) and not getattr(self, "_warned", False):
                print(f"warning: a row has {n_prompt} prompt tokens >= max_len {self.max_len}; "
                      "its answer is truncated away (raise --max-len)")
                self._warned = True
            ids.append(x)
            labels.append(y)
            n_tok = enc["input_ids"].shape[1]
            for k, v in enc.items():
                if k in ("input_ids", "attention_mask"):
                    continue
                if hasattr(v, "dim") and v.dim() == 2 and v.shape[0] == 1 and v.shape[1] == n_tok:
                    seq_extras.setdefault(k, []).append(v[0][: self.max_len])   # per-token (e.g. mm_token_type_ids)
                else:
                    extras.setdefault(k, []).append(v)                          # per-image (pixel_values, grid_thw)
        L = max(len(x) for x in ids)
        input_ids = torch.full((len(ids), L), self.pad_id, dtype=torch.long)
        lab = torch.full((len(ids), L), -100, dtype=torch.long)
        att = torch.zeros((len(ids), L), dtype=torch.long)
        for i, (x, y) in enumerate(zip(ids, labels)):
            input_ids[i, : len(x)] = x
            lab[i, : len(y)] = y
            att[i, : len(x)] = 1
        out = {"input_ids": input_ids, "attention_mask": att, "labels": lab}
        for k, vs in extras.items():
            out[k] = torch.cat(vs, dim=0)   # pixel_values / image_grid_thw are concatenated across the batch
        for k, vs in seq_extras.items():
            t = torch.zeros((len(vs), L), dtype=vs[0].dtype)
            for i, v in enumerate(vs):
                t[i, : len(v)] = v
            out[k] = t
        return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", nargs="+", required=True)
    ap.add_argument("--out", default="runs/mujassam-lora")
    ap.add_argument("--model", default="Qwen/Qwen3-VL-4B-Instruct")
    ap.add_argument("--epochs", type=float, default=2.0)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--rank", type=int, default=32)
    ap.add_argument("--alpha", type=int, default=64)
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--max-len", type=int, default=6144)
    ap.add_argument("--max-image-side", type=int, default=768)
    ap.add_argument("--max-rows", type=int, default=None)
    ap.add_argument("--no-4bit", action="store_true")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--workers", type=int, default=2)
    a = ap.parse_args()

    import torch
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from torch.utils.data import Dataset
    from transformers import AutoModelForImageTextToText, AutoProcessor, Trainer, TrainingArguments

    rows = load_rows(a.data, a.max_rows, a.seed)
    print(f"{len(rows)} training rows")
    bf16 = torch.cuda.is_available() and torch.cuda.is_bf16_supported()
    dtype = torch.bfloat16 if bf16 else torch.float16
    kw: dict[str, Any] = {"device_map": "auto", "dtype": dtype}
    if not a.no_4bit:
        from transformers import BitsAndBytesConfig
        kw["quantization_config"] = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                                                       bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=dtype,
                                                       llm_int8_skip_modules=["visual", "lm_head"])
    processor = AutoProcessor.from_pretrained(a.model)
    try:
        model = AutoModelForImageTextToText.from_pretrained(a.model, **kw)
    except TypeError:
        kw["torch_dtype"] = kw.pop("dtype")
        model = AutoModelForImageTextToText.from_pretrained(a.model, **kw)
    if not a.no_4bit:
        model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    else:
        model.gradient_checkpointing_enable()
    model = get_peft_model(model, LoraConfig(r=a.rank, lora_alpha=a.alpha, lora_dropout=0.05,
                                             target_modules=LM_TARGETS, task_type="CAUSAL_LM"))
    model.print_trainable_parameters()

    class DS(Dataset):
        def __len__(self):
            return len(rows)

        def __getitem__(self, i):
            return rows[i]

    import inspect
    import math
    total_steps = math.ceil(len(rows) * a.epochs / (a.batch * a.grad_accum))
    targs = dict(
        output_dir=a.out, num_train_epochs=a.epochs, learning_rate=a.lr, per_device_train_batch_size=a.batch,
        gradient_accumulation_steps=a.grad_accum, warmup_steps=max(1, int(0.03 * total_steps)),
        lr_scheduler_type="cosine", logging_steps=10, save_steps=200, save_total_limit=2, bf16=bf16,
        fp16=not bf16 and torch.cuda.is_available(), gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False}, remove_unused_columns=False,
        dataloader_num_workers=a.workers, report_to=[], seed=a.seed)
    accepted = inspect.signature(TrainingArguments.__init__).parameters
    dropped = sorted(k for k in targs if k not in accepted)
    if dropped:
        print("note: this transformers version ignores", dropped)
    args = TrainingArguments(**{k: v for k, v in targs.items() if k in accepted})
    Trainer(model=model, args=args, train_dataset=DS(), data_collator=Collator(processor, a.max_len, a.max_image_side)).train()
    model.save_pretrained(a.out)
    processor.save_pretrained(a.out)
    Path(a.out, "mujassam_lora.json").write_text(json.dumps({"base_model": a.model, "rows": len(rows), "rank": a.rank}))
    print("saved LoRA adapter to", a.out)


if __name__ == "__main__":
    main()
