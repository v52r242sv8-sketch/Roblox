#!/usr/bin/env python3
"""Lightweight Luau sanity checker (no external tools needed).

Checks every .luau file under the given folders for:
  * unbalanced blocks (function/if/do/repeat vs end/until)
  * unbalanced brackets ( ) { } [ ]
  * `!=` (not valid Luau, use `~=`)
  * identifiers that are never declared in the file and are not Roblox/Luau globals
    (catches typos like `Servcies.Plot`)

It is not a full parser: use `selene` / `luau-analyze` for real linting.
Usage: python3 tools/luau_check.py src
"""
import os
import re
import sys

KEYWORDS = {
    "and", "break", "continue", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

GLOBALS = {
    "game", "workspace", "script", "plugin", "shared", "_G", "self",
    "Instance", "Vector3", "Vector2", "Vector3int16", "Vector2int16", "CFrame", "Color3", "BrickColor",
    "ColorSequence", "ColorSequenceKeypoint", "NumberSequence", "NumberSequenceKeypoint", "NumberRange",
    "UDim", "UDim2", "Rect", "Enum", "Random", "RaycastParams", "OverlapParams", "TweenInfo", "Ray",
    "Region3", "PhysicalProperties", "Font", "Axes", "Faces", "DateTime", "buffer",
    "math", "string", "table", "os", "task", "coroutine", "utf8", "bit32", "debug",
    "typeof", "type", "tostring", "tonumber", "pairs", "ipairs", "next", "print", "warn", "error",
    "pcall", "xpcall", "require", "select", "setmetatable", "getmetatable", "rawget", "rawset",
    "rawequal", "rawlen", "unpack", "assert", "tick", "time", "wait", "spawn", "delay", "newproxy",
    "gcinfo", "elapsedTime",
}

TOKEN_RE = re.compile(
    r"""
    (?P<ws>[ \t\r]+)
  | (?P<nl>\n)
  | (?P<longcomment>--\[(?P<eq1>=*)\[.*?\](?P=eq1)\])
  | (?P<comment>--[^\n]*)
  | (?P<longstring>\[(?P<eq2>=*)\[.*?\](?P=eq2)\])
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<interp>`(?:\\.|[^`\\])*`)
  | (?P<number>0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|//=|//|%=|\^=|::|->|!=|[-+*/%^#<>=(){}\[\];:,.&|~!?])
    """,
    re.S | re.X,
)


def tokenize(source, path, errors):
    tokens = []
    pos = 0
    line = 1
    while pos < len(source):
        m = TOKEN_RE.match(source, pos)
        if not m:
            errors.append(f"{path}:{line}: cannot tokenize near {source[pos:pos + 20]!r}")
            pos += 1
            continue
        kind = m.lastgroup
        text = m.group(0)
        if kind in ("eq1", "eq2"):
            kind = "longcomment" if text.startswith("--") else "longstring"
        if kind == "nl":
            line += 1
        elif kind not in ("ws", "comment", "longcomment"):
            if kind in ("longstring", "interp"):
                kind = "string"
            tokens.append((kind, text, line))
        line += text.count("\n") if kind not in ("nl",) and "\n" in text else 0
        pos = m.end()
    return tokens


def check_file(path):
    errors = []
    warnings = []
    with open(path, encoding="utf-8") as f:
        source = f.read()
    tokens = tokenize(source, path, errors)

    # Blocks and brackets
    block_stack = []
    bracket_stack = []
    pairs_ = {")": "(", "}": "{", "]": "["}
    loop_header = False  # inside `while ... do` / `for ... do` header
    for i, (kind, text, line) in enumerate(tokens):
        prev = tokens[i - 1][1] if i > 0 else None
        if kind == "op" and text == "!=":
            errors.append(f"{path}:{line}: '!=' is not valid Luau, use '~='")
        if kind == "op" and text in "({[":
            bracket_stack.append((text, line))
        elif kind == "op" and text in ")}]":
            if not bracket_stack or bracket_stack[-1][0] != pairs_[text]:
                errors.append(f"{path}:{line}: unexpected '{text}'")
            else:
                bracket_stack.pop()
        if kind != "name" or prev in (".", ":"):
            continue
        if text in ("while", "for"):
            loop_header = True
            block_stack.append((text, line))
        elif text == "do":
            if loop_header:
                loop_header = False
            else:
                block_stack.append(("do", line))
        elif text in ("function", "if", "repeat"):
            block_stack.append((text, line))
        elif text == "end":
            if not block_stack:
                errors.append(f"{path}:{line}: 'end' without an open block")
            else:
                opener, _ = block_stack.pop()
                if opener == "repeat":
                    errors.append(f"{path}:{line}: 'end' closes a 'repeat' (needs 'until')")
        elif text == "until":
            if not block_stack or block_stack[-1][0] != "repeat":
                errors.append(f"{path}:{line}: 'until' without 'repeat'")
            else:
                block_stack.pop()
    for opener, line in block_stack:
        errors.append(f"{path}:{line}: '{opener}' is never closed")
    for opener, line in bracket_stack:
        errors.append(f"{path}:{line}: '{opener}' is never closed")

    # Declared names (file-wide, scope-insensitive)
    declared = set()
    n = len(tokens)
    for i, (kind, text, line) in enumerate(tokens):
        if kind != "name":
            continue
        if text == "local":
            j = i + 1
            if j < n and tokens[j][1] == "function":
                if j + 1 < n:
                    declared.add(tokens[j + 1][1])
                continue
            while j < n and tokens[j][0] == "name":
                declared.add(tokens[j][1])
                if j + 1 < n and tokens[j + 1][1] == ",":
                    j += 2
                else:
                    break
        elif text == "function":
            j = i + 1
            # skip function name (A.B:C)
            while j < n and tokens[j][1] != "(":
                j += 1
            j += 1
            while j < n and tokens[j][1] != ")":
                if tokens[j][0] == "name":
                    declared.add(tokens[j][1])
                j += 1
        elif text == "for":
            j = i + 1
            while j < n and tokens[j][1] not in ("=", "in"):
                if tokens[j][0] == "name":
                    declared.add(tokens[j][1])
                j += 1

    # Undeclared identifier usage
    reported = set()
    for i, (kind, text, line) in enumerate(tokens):
        if kind != "name" or text in KEYWORDS:
            continue
        prev = tokens[i - 1][1] if i > 0 else None
        nxt = tokens[i + 1][1] if i + 1 < n else None
        if prev in (".", ":", "::"):
            continue
        if nxt == "=" and prev in ("{", ",", ";"):
            # table constructor key { Name = 1 } (or multiple assignment a, b = ...)
            continue
        if text in declared or text in GLOBALS:
            continue
        if text not in reported:
            reported.add(text)
            warnings.append(f"{path}:{line}: '{text}' is never declared in this file (global or typo?)")
    return errors, warnings


def main():
    roots = sys.argv[1:] or ["src"]
    files = []
    for root in roots:
        for dirpath, _, filenames in os.walk(root):
            for name in sorted(filenames):
                if name.endswith((".luau", ".lua")):
                    files.append(os.path.join(dirpath, name))
    total_errors = 0
    total_warnings = 0
    for path in sorted(files):
        errors, warnings = check_file(path)
        for e in errors:
            print("ERROR  ", e)
        for w in warnings:
            print("WARNING", w)
        total_errors += len(errors)
        total_warnings += len(warnings)
    print(f"Checked {len(files)} files: {total_errors} errors, {total_warnings} warnings")
    sys.exit(1 if total_errors else 0)


if __name__ == "__main__":
    main()
