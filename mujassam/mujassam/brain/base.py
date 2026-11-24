"""The 'brain': a vision-language model that plans, writes specs, sees renders and criticises.

Backends implement one method, ``chat(messages) -> str``. Messages are OpenAI-like:
    {"role": "system"|"user"|"assistant",
     "content": "text" | [{"type": "text", "text": ...}, {"type": "image", "image": PIL.Image | path}]}
"""
from __future__ import annotations

import json
import re
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

Message = dict[str, Any]


class Brain(ABC):
    name = "brain"

    @abstractmethod
    def chat(self, messages: list[Message], *, max_new_tokens: int = 2048, temperature: float = 0.2,
             seed: int | None = None) -> str:
        ...

    def num_parameters(self) -> int:
        return 0

    # convenience ---------------------------------------------------------------
    def chat_json(self, messages: list[Message], *, retries: int = 2, **kw: Any) -> Any:
        """Ask for JSON; on parse failure show the model its error and retry."""
        last_err = ""
        msgs = list(messages)
        for attempt in range(retries + 1):
            text = self.chat(msgs, **kw)
            try:
                return extract_json(text)
            except ValueError as e:
                last_err = str(e)
                msgs = msgs + [
                    {"role": "assistant", "content": text[-4000:]},
                    {"role": "user", "content": "Your reply was not valid JSON (" + last_err[:200] +
                     "). Reply again with ONLY the corrected JSON, no prose, no code fences."},
                ]
                kw["temperature"] = max(0.0, kw.get("temperature", 0.2) * 0.5)
        raise ValueError(f"brain did not return valid JSON after {retries + 1} attempts: {last_err}")


# ---------------------------------------------------------------------------- JSON utils
_FENCE = re.compile(r"```(?:json|JSON)?\s*(.*?)```", re.S)


def _balanced(text: str, start: int) -> str | None:
    open_ch = text[start]
    close_ch = "}" if open_ch == "{" else "]"
    depth, i, in_str, esc = 0, start, False, False
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == open_ch:
                depth += 1
            elif c == close_ch:
                depth -= 1
                if depth == 0:
                    return text[start:i + 1]
        i += 1
    return None


def _repair(s: str) -> str:
    s = re.sub(r"//[^\n\"]*$", "", s, flags=re.M)          # // comments at line end
    s = re.sub(r",\s*([}\]])", r"\1", s)                    # trailing commas
    s = s.replace("True", "true").replace("False", "false").replace("None", "null")
    return s


def extract_json(text: str) -> Any:
    """Pull the first JSON object/array out of a model reply (fences, prose, trailing commas)."""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    candidates = [m.group(1) for m in _FENCE.finditer(text)] + [text]
    for cand in candidates:
        for i, ch in enumerate(cand):
            if ch in "{[":
                block = _balanced(cand, i)
                if block is None:
                    continue
                for attempt in (block, _repair(block)):
                    try:
                        return json.loads(attempt)
                    except json.JSONDecodeError:
                        pass
                break
    raise ValueError("no JSON object found in reply")


def load_image(img: Any):
    from PIL import Image
    if isinstance(img, (str, Path)):
        return Image.open(img).convert("RGB")
    if hasattr(img, "convert"):
        return img.convert("RGB")
    raise TypeError(f"unsupported image type {type(img)}")


def split_content(content: Any) -> tuple[str, list[Any]]:
    """Return (text with <image> markers, images) for backends that need it."""
    if isinstance(content, str):
        return content, []
    texts, images = [], []
    for c in content:
        if c.get("type") == "text":
            texts.append(c["text"])
        elif c.get("type") == "image":
            images.append(c["image"])
            texts.append("<image>")
    return "\n".join(texts), images
