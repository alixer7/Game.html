"""Offline brains for tests and CPU-only demos (no neural weights)."""
from __future__ import annotations

import json
from typing import Any, Callable

from .base import Brain, Message


def last_text(messages: list[Message]) -> str:
    for m in reversed(messages):
        if m["role"] == "user":
            c = m["content"]
            if isinstance(c, str):
                return c
            return "\n".join(x.get("text", "") for x in c if x.get("type") == "text")
    return ""


def task_of(messages: list[Message]) -> str:
    """Which prompt template produced this conversation (planner/critic/router/analyst/...)."""
    sys_txt = messages[0]["content"] if messages and messages[0]["role"] == "system" else ""
    if isinstance(sys_txt, list):
        sys_txt = " ".join(x.get("text", "") for x in sys_txt)
    for tag in ("[MJ:ROUTER]", "[MJ:PLANNER]", "[MJ:CRITIC]", "[MJ:ANALYST]", "[MJ:CODER]"):
        if tag in sys_txt:
            return tag[4:-1].lower()
    return "unknown"


class ScriptedBrain(Brain):
    """Returns answers from per-task queues or a callback — deterministic pipeline tests."""
    name = "scripted"

    def __init__(self, responses: dict[str, list[Any]] | None = None,
                 fn: Callable[[str, list[Message]], Any] | None = None):
        self.responses = {k: list(v) for k, v in (responses or {}).items()}
        self.fn = fn
        self.calls: list[tuple[str, list[Message]]] = []

    def chat(self, messages: list[Message], **kw: Any) -> str:
        task = task_of(messages)
        self.calls.append((task, messages))
        if self.fn is not None:
            out = self.fn(task, messages)
        else:
            q = self.responses.get(task) or self.responses.get("*")
            if not q:
                raise RuntimeError(f"ScriptedBrain has no response left for task {task!r}")
            out = q.pop(0) if len(q) > 1 else q[0]
        return out if isinstance(out, str) else json.dumps(out)
