"""Qwen3-VL brain (Apache-2.0) via Hugging Face transformers.

Default: Qwen/Qwen3-VL-4B-Instruct, language model in 4-bit NF4 (bitsandbytes), vision
encoder kept in 16-bit so the critic keeps its eyesight. ~3 GB of VRAM at runtime.
"""
from __future__ import annotations

import base64
import io
import json
import urllib.request
from typing import Any

from .base import Brain, Message, load_image


def _resize(img, max_side: int):
    w, h = img.size
    s = max_side / max(w, h)
    if s < 1:
        img = img.resize((max(28, int(w * s)), max(28, int(h * s))))
    return img


def count_params(module) -> int:
    """Parameter count that also understands bitsandbytes 4-bit packed weights."""
    total = 0
    for p in module.parameters():
        qs = getattr(p, "quant_state", None)
        if qs is not None and getattr(qs, "shape", None) is not None:
            n = 1
            for d in qs.shape:
                n *= int(d)
            total += n
        else:
            total += p.numel()
    return total


class QwenVLBrain(Brain):
    name = "qwen3-vl"

    def __init__(self, model_id: str = "Qwen/Qwen3-VL-4B-Instruct", quantization: str = "nf4",
                 device_map: str | dict = "auto", lora: str | None = None, max_image_side: int = 896,
                 attn_implementation: str | None = None, torch_dtype: str | None = None):
        import torch
        from transformers import AutoModelForImageTextToText, AutoProcessor

        self.torch = torch
        self.model_id = model_id
        self.max_image_side = max_image_side
        if torch_dtype:
            dtype = getattr(torch, torch_dtype)
        elif torch.cuda.is_available():
            dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
        else:
            dtype = torch.float32
        kw: dict[str, Any] = {"device_map": device_map, "dtype": dtype}
        if attn_implementation:
            kw["attn_implementation"] = attn_implementation
        if quantization in ("nf4", "int4", "4bit") and torch.cuda.is_available():
            from transformers import BitsAndBytesConfig
            kw["quantization_config"] = BitsAndBytesConfig(
                load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_use_double_quant=True,
                bnb_4bit_compute_dtype=dtype, llm_int8_skip_modules=["visual", "lm_head"])
        elif quantization in ("int8", "8bit") and torch.cuda.is_available():
            from transformers import BitsAndBytesConfig
            kw["quantization_config"] = BitsAndBytesConfig(load_in_8bit=True,
                                                           llm_int8_skip_modules=["visual", "lm_head"])
        self.quantization = quantization if "quantization_config" in kw else "none"
        self.processor = AutoProcessor.from_pretrained(model_id)
        try:
            self.model = AutoModelForImageTextToText.from_pretrained(model_id, **kw)
        except TypeError:  # older transformers use torch_dtype=
            kw["torch_dtype"] = kw.pop("dtype")
            self.model = AutoModelForImageTextToText.from_pretrained(model_id, **kw)
        if lora:
            from peft import PeftModel
            self.model = PeftModel.from_pretrained(self.model, lora)
        self.model.eval()

    def num_parameters(self) -> int:
        return count_params(self.model)

    def _prepare(self, messages: list[Message]):
        images, conv = [], []
        for m in messages:
            c = m["content"]
            if isinstance(c, str):
                conv.append({"role": m["role"], "content": [{"type": "text", "text": c}]})
                continue
            items = []
            for it in c:
                if it.get("type") == "image":
                    images.append(_resize(load_image(it["image"]), self.max_image_side))
                    items.append({"type": "image"})
                else:
                    items.append({"type": "text", "text": it["text"]})
            conv.append({"role": m["role"], "content": items})
        text = self.processor.apply_chat_template(conv, tokenize=False, add_generation_prompt=True)
        inputs = self.processor(text=[text], images=images or None, return_tensors="pt", padding=True)
        return inputs.to(self.model.device)

    def chat(self, messages: list[Message], *, max_new_tokens: int = 2048, temperature: float = 0.2,
             seed: int | None = None) -> str:
        torch = self.torch
        if seed is not None:
            torch.manual_seed(seed)
        inputs = self._prepare(messages)
        gen = dict(max_new_tokens=max_new_tokens, repetition_penalty=1.0)
        if temperature and temperature > 0:
            gen.update(do_sample=True, temperature=float(temperature), top_p=0.8, top_k=20)
        else:
            gen.update(do_sample=False)
        with torch.inference_mode():
            out = self.model.generate(**inputs, **gen)
        new = out[:, inputs["input_ids"].shape[1]:]
        return self.processor.batch_decode(new, skip_special_tokens=True)[0].strip()


class OpenAICompatBrain(Brain):
    """Any OpenAI-compatible server: llama.cpp (GGUF, phones/CPUs), vLLM, Ollama, LM Studio.

    This is how the compressed GGUF build of the brain is used.
    """
    name = "openai-compat"

    def __init__(self, base_url: str = "http://127.0.0.1:8080/v1", model: str = "mujassam-brain",
                 api_key: str = "none", timeout: float = 600, max_image_side: int = 896,
                 param_count: int = 0):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key = api_key
        self.timeout = timeout
        self.max_image_side = max_image_side
        self._params = param_count

    def num_parameters(self) -> int:
        return self._params

    def _img_url(self, img) -> str:
        im = _resize(load_image(img), self.max_image_side)
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

    def chat(self, messages: list[Message], *, max_new_tokens: int = 2048, temperature: float = 0.2,
             seed: int | None = None) -> str:
        conv = []
        for m in messages:
            c = m["content"]
            if isinstance(c, str):
                conv.append({"role": m["role"], "content": c})
                continue
            items = []
            for it in c:
                if it.get("type") == "image":
                    items.append({"type": "image_url", "image_url": {"url": self._img_url(it["image"])}})
                else:
                    items.append({"type": "text", "text": it["text"]})
            conv.append({"role": m["role"], "content": items})
        body = {"model": self.model, "messages": conv, "max_tokens": max_new_tokens,
                "temperature": float(temperature)}
        if seed is not None:
            body["seed"] = seed
        req = urllib.request.Request(self.base_url + "/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json",
                                              "Authorization": f"Bearer {self.api_key}"})
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            data = json.loads(r.read().decode())
        return data["choices"][0]["message"]["content"] or ""
