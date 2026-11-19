"""A small, conservative static type checker for GDScript expressions (used by check_gd.py).

It parses statements into trees, infers types where they are certain (literals, declared variables, project
functions, a table of value-type methods) and reports only what is certainly wrong:

  * binary/unary operators on incompatible operand types   (Vector3 + float, float % float, String + int ...)
  * argument / initializer / assignment / return values whose type cannot convert to the declared type
  * constructor calls of value types with a wrong argument count or non-numeric components

Unknown types (None / Variant) never produce a report.
"""

NUM = ("int", "float")
VEC = ("Vector2", "Vector3", "Vector4", "Vector2i", "Vector3i", "Vector4i")
PACKED = {"PackedVector3Array": "Vector3", "PackedVector2Array": "Vector2", "PackedFloat32Array": "float",
          "PackedFloat64Array": "float", "PackedInt32Array": "int", "PackedInt64Array": "int",
          "PackedStringArray": "String", "PackedColorArray": "Color", "PackedByteArray": "int"}
VALUE_KNOWN = set(VEC) | {"int", "float", "bool", "String", "StringName", "NodePath", "Color", "Basis", "Transform3D",
                          "Transform2D", "Quaternion", "AABB", "Rect2", "Rect2i", "Plane", "Array", "Dictionary",
                          "Callable", "Signal", "Projection"} | set(PACKED)
CTOR_ARITY = {
    "Vector2": (0, 1, 2), "Vector3": (0, 1, 3), "Vector4": (0, 1, 4), "Vector2i": (0, 1, 2), "Vector3i": (0, 1, 3),
    "Color": (0, 1, 2, 3, 4), "Basis": (0, 1, 2, 3, 4), "Quaternion": (0, 1, 2, 3, 4), "Transform3D": (0, 1, 2, 4),
    "Transform2D": (0, 1, 2, 3), "AABB": (0, 1, 2), "Rect2": (0, 1, 2, 4), "Plane": (0, 1, 2, 3, 4)}
CTOR_NUMERIC_ARGS = {("Vector2", 2), ("Vector3", 3), ("Vector4", 4), ("Color", 3), ("Color", 4)}

UTIL_FLOAT = set("""sin cos tan asin acos atan atan2 sinh cosh tanh sqrt pow exp log deg_to_rad rad_to_deg lerpf clampf
minf maxf absf signf floorf ceilf roundf fmod fposmod randf randf_range randfn smoothstep inverse_lerp remap
move_toward snappedf pingpong wrapf lerp_angle ease bezier_interpolate cubic_interpolate""".split())
UTIL_INT = set("""int clampi mini maxi absi randi randi_range floori ceili roundi posmod len wrapi signi snappedi
hash typeof ord nearest_po2 step_decimals""".split())
UTIL_GENERIC = set("abs sign min max clamp snapped round floor ceil wrap lerp".split())  # result follows the arguments

VEC_FLOAT_METHODS = set("""length length_squared dot distance_to distance_squared_to angle_to angle aspect
angle_to_point""".split())
VEC_SAME_METHODS = set("""normalized abs floor ceil round sign lerp slerp limit_length clamp rotated reflect bounce slide
project move_toward direction_to snapped orthogonal posmod cubic_interpolate min max lerp""".split())
VEC_BOOL_METHODS = set("is_zero_approx is_equal_approx is_normalized is_finite".split())
COLOR_SAME = set("lerp darkened lightened blend inverted srgb_to_linear linear_to_srgb".split())
STR_METHODS = {
    "length": "int", "begins_with": "bool", "ends_with": "bool", "contains": "bool", "is_empty": "bool",
    "to_upper": "String", "to_lower": "String", "substr": "String", "replace": "String", "strip_edges": "String",
    "format": "String", "capitalize": "String", "pad_zeros": "String", "pad_decimals": "String", "lstrip": "String",
    "rstrip": "String", "to_int": "int", "to_float": "float", "find": "int", "hash": "int", "split": "PackedStringArray",
    "is_valid_int": "bool", "is_valid_float": "bool", "left": "String", "right": "String", "trim_prefix": "String",
    "trim_suffix": "String", "repeat": "String", "get_extension": "String", "get_file": "String"}
ARR_METHODS = {"size": "int", "is_empty": "bool", "has": "bool", "find": "int", "duplicate": "Array", "count": "int",
               "slice": "Array"}
DICT_METHODS = {"size": "int", "has": "bool", "is_empty": "bool", "keys": "Array", "values": "Array",
                "duplicate": "Dictionary", "erase": "bool", "has_all": "bool"}
PACKED_METHODS = {"size": "int", "is_empty": "bool"}
ENGINE_STATIC_RET = {
    ("Time", "get_ticks_msec"): "int", ("Time", "get_ticks_usec"): "int", ("Engine", "get_frames_per_second"): "float",
    ("Input", "is_action_pressed"): "bool", ("Input", "is_action_just_pressed"): "bool",
    ("Input", "is_action_just_released"): "bool", ("Input", "get_axis"): "float", ("Input", "get_vector"): "Vector2",
    ("OS", "has_feature"): "bool", ("JSON", "stringify"): "String", ("FileAccess", "file_exists"): "bool",
    ("ResourceLoader", "exists"): "bool", ("Color", "from_hsv"): "Color", ("Color", "html"): "Color",
    ("Basis", "looking_at"): "Basis", ("Basis", "from_euler"): "Basis", ("Quaternion", "from_euler"): "Quaternion",
    ("DisplayServer", "screen_get_size"): "Vector2i", ("Vector3", "from_angle"): "Vector3",
    ("Transform3D", "looking_at"): "Transform3D", ("AudioServer", "get_bus_index"): "int",
    ("AudioServer", "get_bus_count"): "int", ("DisplayServer", "get_display_safe_area"): "Rect2i"}


class ParseError(Exception):
    pass


BIN_PREC = {"or": 1, "||": 1, "and": 2, "&&": 2, "in": 4, "==": 5, "!=": 5, "<": 5, ">": 5, "<=": 5, ">=": 5,
            "|": 6, "^": 7, "&": 8, "<<": 9, ">>": 9, "+": 10, "-": 10, "*": 11, "/": 11, "%": 11, "**": 13}
ASSIGN_OPS = ("=", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "<<=", ">>=", "**=")


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, o=0):
        j = self.i + o
        return self.t[j] if j < len(self.t) else (None, None)

    def eat(self, text=None):
        k, t = self.peek()
        if k is None or (text is not None and t != text):
            raise ParseError("expected %r got %r" % (text, t))
        self.i += 1
        return k, t

    def done(self):
        return self.i >= len(self.t)

    # ternary
    def expr(self):
        left = self.binary(1)
        k, t = self.peek()
        if k == "id" and t == "if":
            self.i += 1
            cond = self.binary(1)
            self.eat("else")
            other = self.expr()
            return ("ternary", cond, left, other)
        return left

    def binary(self, minp):
        left = self.unary()
        while True:
            k, t = self.peek()
            if k is None:
                break
            op = t
            if k == "id" and t == "not" and self.peek(1)[1] == "in":
                op = "in"
                nlen = 2
            elif (k == "op" or (k == "id" and t in ("and", "or", "in"))) and t in BIN_PREC:
                nlen = 1
            else:
                break
            p = BIN_PREC[op]
            if p < minp:
                break
            self.i += nlen
            right = self.binary(p if op == "**" else p + 1)
            left = ("bin", op, left, right)
        return left

    def unary(self):
        k, t = self.peek()
        if k == "op" and t in ("-", "+", "~"):
            self.i += 1
            return ("un", t, self.binary(13))
        if (k == "id" and t == "not") or (k == "op" and t == "!"):
            self.i += 1
            return ("un", "not", self.binary(4))
        if k == "id" and t == "await":
            self.i += 1
            return ("await", self.unary())
        return self.postfix()

    def typename(self):
        parts = []
        while True:
            k, t = self.eat()
            if k != "id":
                raise ParseError("type name")
            parts.append(t)
            if self.peek()[1] == ".":
                self.i += 1
                continue
            break
        name = ".".join(parts)
        if self.peek()[1] == "[":  # Array[T]
            depth = 0
            j = self.i
            inner = []
            while j < len(self.t):
                if self.t[j][1] == "[":
                    depth += 1
                elif self.t[j][1] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                    inner.append(self.t[j][1])
                else:
                    inner.append(self.t[j][1])
                j += 1
            name += "[" + "".join(inner[0:]) + "]"
            self.i = j + 1
        return name

    def postfix(self):
        node = self.primary()
        while True:
            k, t = self.peek()
            if k == "op" and t == ".":
                self.i += 1
                nk, nt = self.eat()
                if nk != "id":
                    raise ParseError("member name")
                node = ("member", node, nt)
            elif k == "op" and t == "(":
                self.i += 1
                args = self.args(")")
                node = ("call", node, args)
            elif k == "op" and t == "[":
                self.i += 1
                idx = self.expr()
                self.eat("]")
                node = ("index", node, idx)
            elif k == "id" and t == "as":
                self.i += 1
                node = ("as", node, self.typename())
            elif k == "id" and t == "is":
                self.i += 1
                if self.peek()[1] == "not":
                    self.i += 1
                self.typename()
                node = ("is", node)
            else:
                break
        return node

    def args(self, close):
        out = []
        if self.peek()[1] == close:
            self.i += 1
            return out
        while True:
            out.append(self.expr())
            k, t = self.peek()
            if t == ",":
                self.i += 1
                if self.peek()[1] == close:
                    self.i += 1
                    return out
                continue
            self.eat(close)
            return out

    def primary(self):
        k, t = self.peek()
        if k is None:
            raise ParseError("eof")
        if k == "num":
            self.i += 1
            low = t.lower()
            if low.startswith("0x") or low.startswith("0b"):
                return ("num", "int")
            return ("num", "float" if ("." in t or "e" in low) else "int")
        if k == "str":
            self.i += 1
            if t.startswith("&"):
                return ("lit", "StringName")
            if t.startswith("^"):
                return ("lit", "NodePath")
            return ("lit", "String")
        if k == "id":
            if t == "func":
                raise ParseError("lambda")
            self.i += 1
            return ("id", t)
        if k == "op" and t == "(":
            self.i += 1
            e = self.expr()
            self.eat(")")
            return ("paren", e)
        if k == "op" and t == "[":
            self.i += 1
            items = self.args("]")
            return ("array", items)
        if k == "op" and t == "{":
            self.i += 1
            depth = 1
            j = self.i
            while j < len(self.t) and depth:
                if self.t[j][1] in "([{" and self.t[j][0] == "op":
                    depth += 1
                elif self.t[j][1] in ")]}" and self.t[j][0] == "op":
                    depth -= 1
                j += 1
            self.i = j
            return ("dict",)
        raise ParseError("unexpected %r" % t)


def parse_expr(toks):
    p = Parser(toks)
    e = p.expr()
    if not p.done():
        raise ParseError("trailing tokens")
    return e


def split_assign(toks):
    depth = 0
    for i, (k, t) in enumerate(toks):
        if k == "op" and t in "([{":
            depth += 1
        elif k == "op" and t in ")]}":
            depth -= 1
        elif depth == 0 and k == "op" and t in ASSIGN_OPS:
            return i
    return None


def numeric_result(a, b):
    return "float" if "float" in (a, b) else "int"


def binop(op, a, b):
    """result type, 'ERR' or None (unknown)"""
    if op in ("and", "or", "&&", "||"):
        return "bool"
    if op == "in":
        return "bool"
    if a in (None, "Variant", "void") or b in (None, "Variant", "void"):
        return "bool" if op in ("==", "!=", "<", ">", "<=", ">=") else None
    if op in ("==", "!="):
        return "bool"
    if a not in VALUE_KNOWN or b not in VALUE_KNOWN:
        return None
    na, nb = a in NUM, b in NUM
    strs = ("String", "StringName")
    if op in ("<", ">", "<=", ">="):
        if (na and nb) or (a in strs and b in strs) or (a == b and a in VEC):
            return "bool"
        return "ERR"
    if op in ("+", "-"):
        if na and nb:
            return numeric_result(a, b)
        if a == b and (a in VEC or a in ("Color", "Quaternion", "Plane")):
            return a
        if op == "+" and a in strs and b in strs:
            return "String"
        if op == "+" and a == "Array" and b == "Array":
            return "Array"
        if a == b and a in PACKED and op == "+":
            return a
        if op == "+" and a in PACKED and b == "Array":
            return None
        if {a, b} <= {"Vector2", "Vector2i"} or {a, b} <= {"Vector3", "Vector3i"}:
            return a if a in ("Vector2", "Vector3") else b
        if a == "Transform3D" and b == "Transform3D":
            return None
        return "ERR"
    if op == "*":
        if na and nb:
            return numeric_result(a, b)
        if a in VEC and (b in NUM or b == a):
            return a
        if a in NUM and b in VEC:
            return b
        if a == "Color" and (b in NUM or b == "Color"):
            return "Color"
        if a in NUM and b == "Color":
            return "Color"
        if a == "Basis" and b in ("Basis", "Vector3"):
            return b
        if a == "Transform3D" and b in ("Transform3D", "Vector3", "AABB", "Plane"):
            return b
        if a == "Quaternion" and b in ("Quaternion", "Vector3", "float", "int"):
            return b if b in ("Quaternion", "Vector3") else "Quaternion"
        if a in NUM and b == "Quaternion":
            return "Quaternion"
        if a == "Basis" and b in NUM or a in NUM and b == "Basis":
            return "Basis"
        if a in strs and b == "int":
            return "String"
        if a == "Transform2D" or b == "Transform2D" or a == "Projection" or b == "Projection":
            return None
        if a in VEC and b in VEC:
            return None
        return "ERR"
    if op == "/":
        if na and nb:
            return numeric_result(a, b)
        if a in VEC and (b in NUM or b == a):
            return a
        if a == "Color" and (b in NUM or b == "Color"):
            return "Color"
        if a == "Quaternion" and b in NUM:
            return "Quaternion"
        if a == "Basis" and b in NUM:
            return "Basis"
        return "ERR"
    if op == "%":
        if a in strs:
            return "String"
        if a == "int" and b == "int":
            return "int"
        if na and nb:
            return "ERR"  # float % is not supported in GDScript 4 (use fmod / fposmod)
        if a in VEC and (b in NUM or b == a):
            return a
        return "ERR"
    if op in ("&", "|", "^", "<<", ">>"):
        if a == "int" and b == "int":
            return "int"
        if a in ("bool", "int") and b in ("bool", "int"):
            return "int"
        return "ERR"
    if op == "**":
        if na and nb:
            return "float" if "float" in (a, b) else "int"
        return "ERR"
    return None


def norm(t):
    if t is None:
        return None
    if isinstance(t, tuple):
        return None
    return t


class Ctx:
    """what the inference needs from the checker"""
    def __init__(self, ck, ln, cls, scope, static, func_ret):
        self.ck, self.ln, self.cls, self.scope, self.static, self.func_ret = ck, ln, cls, scope, static, func_ret


class Infer:
    def __init__(self, env):
        self.env = env  # object with resolve_class, find_member, base_class, type_of_name, GLOBAL, AUTOLOADS, ENGINE_CLASSES ...

    def err(self, ctx, msg):
        ctx.ck.E(ctx.ln, msg)

    # --------------------------------------------------------------- type relations
    def is_subclass(self, sub, sup, ctx):
        a = self.env.resolve_class(sub, ctx.cls)
        b = self.env.resolve_class(sup, ctx.cls)
        if a is None or b is None:
            return None
        seen = 0
        while a is not None and seen < 30:
            if a is b:
                return True
            a = self.env.base_class(a)
            seen += 1
        return False

    def assignable(self, decl, act, ctx):
        """True / False / None(unknown)"""
        decl, act = norm(decl), norm(act)
        if decl in (None, "Variant", "void") or act in (None, "Variant", "void"):
            return True
        if decl == act:
            return True
        if decl.startswith("Array") and act.startswith("Array"):
            return True
        if decl in NUM and act in NUM:
            return True
        if decl == "bool" and act in NUM:
            return True
        if decl in ("String", "StringName", "NodePath") and act in ("String", "StringName", "NodePath"):
            return True
        if {decl, act} <= {"Vector2", "Vector2i"} or {decl, act} <= {"Vector3", "Vector3i"} or {decl, act} <= {"Vector4", "Vector4i"}:
            return True
        if {decl, act} <= {"Rect2", "Rect2i"}:
            return True
        if act == "null":
            return decl not in VALUE_KNOWN or decl in ("Array", "Dictionary", "Callable", "Signal") and False
        if decl in ("Array", "Dictionary") and act in PACKED:
            return False
        if decl in VALUE_KNOWN and act in VALUE_KNOWN:
            return False
        a_known = act in VALUE_KNOWN
        d_known = decl in VALUE_KNOWN
        if a_known != d_known:
            # value type vs object type: only flag when the object side is one of ours
            obj = decl if a_known else act
            if self.env.resolve_class(obj.split("[")[0], ctx.cls) is not None:
                return False
            return None
        r1 = self.is_subclass(act, decl, ctx)
        if r1 is None:
            return None
        if r1:
            return True
        r2 = self.is_subclass(decl, act, ctx)
        return True if r2 else False

    # --------------------------------------------------------------- inference
    def resolve_vtype(self, v, ctx):
        if isinstance(v, tuple) and v and v[0] == "call":
            return None
        return v

    def infer(self, n, ctx):
        r = self._infer(n, ctx)
        return r

    def _infer(self, n, ctx):
        k = n[0]
        if k == "num":
            return n[1]
        if k == "lit":
            return n[1]
        if k == "paren":
            return self.infer(n[1], ctx)
        if k == "array":
            for e in n[1]:
                self.infer(e, ctx)
            return "Array"
        if k == "dict":
            return "Dictionary"
        if k == "await":
            self.infer(n[1], ctx)
            return None
        if k == "is":
            self.infer(n[1], ctx)
            return "bool"
        if k == "as":
            self.infer(n[1], ctx)
            return n[2]
        if k == "ternary":
            self.infer(n[1], ctx)
            a = self.infer(n[2], ctx)
            b = self.infer(n[3], ctx)
            return a if a == b else None
        if k == "un":
            t = self.infer(n[2], ctx)
            if n[1] == "not":
                return "bool"
            if t in (None, "Variant"):
                return None
            if n[1] in ("-", "+"):
                if t in NUM or t in VEC or t in ("Color", "Quaternion", "Plane", "Basis"):
                    return t
                self.err(ctx, "invalid operand type '%s' for unary '%s'" % (t, n[1]))
                return None
            if n[1] == "~":
                return "int"
            return None
        if k == "bin":
            a = self.infer(n[2], ctx)
            b = self.infer(n[3], ctx)
            r = binop(n[1], norm(a), norm(b))
            if r == "ERR":
                self.err(ctx, "invalid operands '%s' and '%s' in operator '%s'" % (a, b, n[1]))
                return None
            return r
        if k == "index":
            t = norm(self.infer(n[1], ctx))
            self.infer(n[2], ctx)
            if t is None:
                return None
            if t.startswith("Array[") and t.endswith("]"):
                return t[6:-1]
            if t in PACKED:
                return PACKED[t]
            if t in VEC:
                return "int" if t.endswith("i") else "float"
            if t == "Color":
                return "float"
            if t == "String":
                return "String"
            if t == "Basis":
                return "Vector3"
            return None
        if k == "id":
            return self.infer_name(n[1], ctx)
        if k == "member":
            return self.infer_member(n, ctx)
        if k == "call":
            return self.infer_call(n, ctx)
        return None

    def infer_name(self, name, ctx):
        if name in ("true", "false"):
            return "bool"
        if name == "null":
            return "null"
        if name in ("PI", "TAU", "INF", "NAN"):
            return "float"
        if name == "self":
            return ctx.cls.qual
        found, info = self.env.type_of_name(name, ctx.cls, ctx.scope)
        if found:
            if hasattr(info, "kind"):
                if info.kind == "func":
                    return "Callable"
                if info.kind == "signal":
                    return "Signal"
                if info.kind == "class":
                    return ("classref", self.env.find_inner(ctx.cls, name) or self.env.resolve_class(name, ctx.cls))
                return self.env.member_type(info, ctx)
            return self.env.local_type(info, ctx)
        ci = self.env.resolve_class(name, ctx.cls)
        if ci is not None:
            return ("classref", ci)
        if name in self.env.autoload_types:
            ci = self.env.autoload_types[name]
            if ci is not None:
                return ci.qual
        if name in VALUE_KNOWN or name in CTOR_ARITY:
            return ("typeref", name)
        if name in self.env.engine_classes:
            return ("engineref", name)
        return None

    def infer_member(self, n, ctx):
        obj = self.infer(n[1], ctx)
        name = n[2]
        if isinstance(obj, tuple):
            kind, what = obj
            if kind == "classref":
                mem = self.env.find_member(what, name)
                if mem is None:
                    if name in what.inner:
                        return ("classref", what.inner[name])
                    return None
                if mem.kind == "class":
                    return ("classref", self.env.find_inner(what, name))
                if mem.kind == "func":
                    return "Callable"
                return self.env.member_type(mem, ctx)
            if kind == "typeref":
                if name.isupper() or name[:1].isupper():
                    if what in VEC or what in ("Color", "Basis", "Transform3D", "Quaternion", "Plane", "AABB", "Rect2"):
                        if name.startswith("AXIS"):
                            return "int"
                        return what
                return None
            return None
        t = norm(obj)
        if t is None:
            return None
        if t in VEC:
            if name in ("x", "y", "z", "w"):
                return "int" if t.endswith("i") else "float"
            return None
        if t == "Color":
            if name in ("r", "g", "b", "a", "h", "s", "v"):
                return "float"
            if name in ("r8", "g8", "b8", "a8"):
                return "int"
            return None
        if t == "Transform3D":
            return {"basis": "Basis", "origin": "Vector3"}.get(name)
        if t == "Basis":
            return "Vector3" if name in ("x", "y", "z") else None
        if t == "Quaternion":
            return "float" if name in ("x", "y", "z", "w") else None
        ci = self.env.resolve_class(t.split("[")[0], ctx.cls)
        if ci is not None:
            mem = self.env.find_member(ci, name)
            if mem is None:
                return None
            if mem.kind == "func":
                return "Callable"
            if mem.kind == "signal":
                return "Signal"
            if mem.kind == "class":
                return None
            return self.env.member_type(mem, ctx)
        return None

    def check_args(self, ctx, label, params, args, arg_types):
        for idx, (a, at) in enumerate(zip(args, arg_types)):
            if idx >= len(params):
                break
            pname, ptype, _ = params[idx]
            if ptype and self.assignable(ptype, at, ctx) is False:
                self.err(ctx, "%s: argument %d (%s) has type '%s', expected '%s'" % (label, idx + 1, pname, at, ptype))

    def infer_call(self, n, ctx):
        callee, args = n[1], n[2]
        arg_types = [self.infer(a, ctx) for a in args]
        arg_types = [norm(t) if not isinstance(t, tuple) else None for t in arg_types]
        if callee[0] == "id":
            name = callee[1]
            found, info = self.env.type_of_name(name, ctx.cls, ctx.scope)
            if found and hasattr(info, "kind") and info.kind == "func":
                self.check_args(ctx, name + "()", info.params, args, arg_types)
                return self.env.func_ret(info, ctx)
            if found:
                return None
            if name in CTOR_ARITY:
                return self.check_ctor(ctx, name, args, arg_types)
            if name in ("int", "float", "bool", "str"):
                return {"int": "int", "float": "float", "bool": "bool", "str": "String"}[name]
            if name in ("String", "StringName", "NodePath"):
                return name
            if name in UTIL_FLOAT:
                return "float"
            if name in UTIL_INT:
                return "int"
            if name in UTIL_GENERIC:
                ts = [t for t in arg_types if t]
                if ts and len(ts) == len(arg_types):
                    if all(t in NUM for t in ts):
                        return "float" if "float" in ts else "int"
                    if ts[0] in VEC or ts[0] == "Color":
                        return ts[0]
                return None
            if name in ("preload", "load", "range", "print", "push_error", "push_warning", "printerr"):
                return None
            return None
        if callee[0] == "member":
            obj = self.infer(callee[1], ctx)
            name = callee[2]
            if isinstance(obj, tuple):
                kind, what = obj
                if kind == "classref":
                    if name == "new":
                        init = what.members.get("_init")
                        if init is not None:
                            self.check_args(ctx, what.short + ".new()", init.params, args, arg_types)
                        return what.qual
                    mem = self.env.find_member(what, name)
                    if mem is not None and mem.kind == "func":
                        self.check_args(ctx, "%s.%s()" % (what.short, name), mem.params, args, arg_types)
                        return self.env.func_ret(mem, ctx)
                    return None
                if kind == "typeref":
                    if name == "new":
                        return what
                    return ENGINE_STATIC_RET.get((what, name))
                if kind == "engineref":
                    if name == "new":
                        return what
                    return ENGINE_STATIC_RET.get((what, name))
                return None
            t = norm(obj)
            if t is None:
                return None
            base = t.split("[")[0]
            if base in VEC:
                if name in VEC_FLOAT_METHODS:
                    if name == "cross" and base == "Vector2":
                        return "float"
                    return "float"
                if name == "cross":
                    return "float" if base == "Vector2" else base
                if name in VEC_SAME_METHODS:
                    return base
                if name in VEC_BOOL_METHODS:
                    return "bool"
                return None
            if base == "Color":
                if name in COLOR_SAME:
                    return "Color"
                if name == "get_luminance":
                    return "float"
                if name == "to_html":
                    return "String"
                return None
            if base == "Transform3D":
                if name in ("inverse", "rotated", "translated", "scaled", "looking_at", "orthonormalized", "affine_inverse"):
                    return "Transform3D"
                return None
            if base == "Basis":
                if name in ("inverse", "orthonormalized", "rotated", "scaled", "transposed"):
                    return "Basis"
                if name in ("get_euler", "get_scale"):
                    return "Vector3"
                if name == "get_rotation_quaternion":
                    return "Quaternion"
                return None
            if base == "Quaternion":
                if name in ("normalized", "slerp", "inverse", "slerpni"):
                    return "Quaternion"
                if name == "get_euler":
                    return "Vector3"
                return None
            if base in ("String", "StringName"):
                return STR_METHODS.get(name)
            if base == "Array":
                return ARR_METHODS.get(name)
            if base == "Dictionary":
                return DICT_METHODS.get(name)
            if base in PACKED:
                return PACKED_METHODS.get(name)
            ci = self.env.resolve_class(base, ctx.cls)
            if ci is not None:
                mem = self.env.find_member(ci, name)
                if mem is not None and mem.kind == "func":
                    self.check_args(ctx, "%s.%s()" % (ci.short, name), mem.params, args, arg_types)
                    return self.env.func_ret(mem, ctx)
            return None
        # call of a call result etc.
        self.infer(callee, ctx)
        return None

    def check_ctor(self, ctx, name, args, arg_types):
        ar = CTOR_ARITY[name]
        if len(args) not in ar:
            self.err(ctx, "%s() cannot take %d arguments" % (name, len(args)))
            return name
        if (name, len(args)) in CTOR_NUMERIC_ARGS:
            for i, t in enumerate(arg_types):
                if t is not None and t not in NUM and t != "Variant":
                    self.err(ctx, "%s(): argument %d has type '%s', expected a number" % (name, i + 1, t))
        if name == "Vector3" and len(args) == 2 or name == "Vector2" and len(args) == 3:
            self.err(ctx, "%s() cannot take %d arguments" % (name, len(args)))
        return name
