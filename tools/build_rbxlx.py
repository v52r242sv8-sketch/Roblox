#!/usr/bin/env python3
"""Builds a Roblox place file (.rbxlx) from default.project.json without Rojo.

It follows the same rules as Rojo for the parts this project uses:
  *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript,
  folders -> Folder, "$properties" with bool/number/string values.

Usage: python3 tools/build_rbxlx.py [output.rbxlx]
Then open the file in Roblox Studio (File > Open from File).
If you have Rojo installed, `rojo build -o build/StealAMeteor.rbxlx` does the same.
"""
import json
import os
import sys
import uuid
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def referent():
    return "RBX" + uuid.uuid4().hex.upper()


def cdata(text):
    # "]]>" cannot appear inside CDATA: split it across two sections
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def prop_xml(name, value):
    if isinstance(value, dict) and "Enum" in value:
        # Rojo-style explicit enum: {"Enum": 4}
        return f'<token name="{escape(name)}">{int(value["Enum"])}</token>'
    if isinstance(value, bool):
        return f'<bool name="{escape(name)}">{"true" if value else "false"}</bool>'
    if isinstance(value, int):
        return f'<int name="{escape(name)}">{value}</int>'
    if isinstance(value, float):
        return f'<float name="{escape(name)}">{value}</float>'
    if isinstance(value, str):
        return f'<string name="{escape(name)}">{escape(value)}</string>'
    raise ValueError(f"Unsupported property {name}={value!r}")


def item(class_name, name, children_xml="", extra_props=None, indent=1):
    pad = "\t" * indent
    props = [prop_xml("Name", name)]
    for key, value in (extra_props or {}).items():
        if key == "Source":
            props.append(f'<ProtectedString name="Source">{cdata(value)}</ProtectedString>')
        else:
            props.append(prop_xml(key, value))
    props_xml = "".join(f"\n{pad}\t\t{p}" for p in props)
    return (
        f'\n{pad}<Item class="{class_name}" referent="{referent()}">'
        f"\n{pad}\t<Properties>{props_xml}\n{pad}\t</Properties>"
        f"{children_xml}"
        f"\n{pad}</Item>"
    )


def script_class(filename):
    if filename.endswith(".server.luau") or filename.endswith(".server.lua"):
        return "Script", filename.rsplit(".server.", 1)[0]
    if filename.endswith(".client.luau") or filename.endswith(".client.lua"):
        return "LocalScript", filename.rsplit(".client.", 1)[0]
    if filename.endswith(".luau") or filename.endswith(".lua"):
        return "ModuleScript", filename.rsplit(".", 1)[0]
    return None, None


def build_path(path, name, indent):
    full = os.path.join(ROOT, path)
    if os.path.isfile(full):
        cls, _ = script_class(os.path.basename(full))
        with open(full, encoding="utf-8") as f:
            return item(cls, name, extra_props={"Source": f.read()}, indent=indent)
    children = ""
    for entry in sorted(os.listdir(full)):
        child_path = os.path.join(path, entry)
        if os.path.isdir(os.path.join(ROOT, child_path)):
            children += build_path(child_path, entry, indent + 1)
        else:
            cls, child_name = script_class(entry)
            if cls:
                children += build_path(child_path, child_name, indent + 1)
    return item("Folder", name, children, indent=indent)


def build_node(name, node, indent):
    if "$path" in node:
        return build_path(node["$path"], name, indent)
    class_name = node.get("$className", name)
    children = ""
    for key, child in node.items():
        if not key.startswith("$"):
            children += build_node(key, child, indent + 1)
    return item(class_name, name, children, node.get("$properties"), indent)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "StealAMeteor.rbxlx")
    with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
        project = json.load(f)
    tree = project["tree"]
    body = ""
    for key, child in tree.items():
        if not key.startswith("$"):
            body += build_node(key, child, 1)
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        f"{body}\n</roblox>\n"
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"Wrote {out} ({len(xml) // 1024} KB)")


if __name__ == "__main__":
    main()
