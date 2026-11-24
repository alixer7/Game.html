"""Static safety check for model-written Blender code (freeform mode).

Generated code runs inside Blender, which can touch the file system and network. Before
running it we parse the AST and reject anything outside a small modelling vocabulary.
This is a guard-rail against accidents and prompt-injection, not a full security
boundary: still run Blender jobs in a throwaway container / subprocess (we do).
"""
from __future__ import annotations

import ast

ALLOWED_IMPORTS = {"bpy", "bmesh", "math", "mathutils", "random", "itertools", "functools", "colorsys"}

FORBIDDEN_NAMES = {
    "eval", "exec", "compile", "open", "__import__", "globals", "locals", "vars", "getattr",
    "setattr", "delattr", "input", "breakpoint", "exit", "quit", "memoryview", "help",
    "os", "sys", "subprocess", "shutil", "socket", "importlib", "pathlib", "builtins",
}

FORBIDDEN_ATTRS = {
    # file / process / network side effects through bpy
    "save_as_mainfile", "save_mainfile", "open_mainfile", "read_homefile", "quit_blender",
    "addon_install", "addon_enable", "script_reload", "load_post", "handlers", "app",
    "filepath", "unlink", "remove_file", "system", "popen", "__subclasses__", "__globals__",
    "__builtins__", "__code__", "__class__", "__bases__", "__mro__", "func_globals",
    "export_scene", "import_scene", "wm", "preferences", "driver_namespace", "texts", "libraries",
}


class UnsafeCodeError(ValueError):
    pass


def check_code(code: str, max_len: int = 60_000) -> None:
    if len(code) > max_len:
        raise UnsafeCodeError(f"code too long ({len(code)} chars)")
    try:
        tree = ast.parse(code)
    except SyntaxError as e:
        raise UnsafeCodeError(f"syntax error: {e}") from e
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                if a.name.split(".")[0] not in ALLOWED_IMPORTS:
                    raise UnsafeCodeError(f"import of {a.name!r} not allowed")
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".")[0] not in ALLOWED_IMPORTS or node.level:
                raise UnsafeCodeError(f"import from {node.module!r} not allowed")
        elif isinstance(node, ast.Name) and node.id in FORBIDDEN_NAMES:
            raise UnsafeCodeError(f"use of {node.id!r} not allowed")
        elif isinstance(node, ast.Attribute):
            if node.attr in FORBIDDEN_ATTRS or node.attr.startswith("__"):
                raise UnsafeCodeError(f"attribute {node.attr!r} not allowed")
        elif isinstance(node, (ast.Global, ast.Nonlocal)):
            raise UnsafeCodeError("global/nonlocal not allowed")
        elif isinstance(node, ast.While):
            # unbounded loops are a common failure of small models; require for-loops
            raise UnsafeCodeError("while loops not allowed (use bounded for-loops)")
