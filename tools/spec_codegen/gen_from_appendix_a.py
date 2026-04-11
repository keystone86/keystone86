#!/usr/bin/env python3
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tools/spec_codegen/appendix_a_codegen.json"

def hexw(v, width=2):
    return f"{v:0{width}X}"

def load():
    return json.loads(SRC.read_text(encoding="utf-8"))

def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")

def gen_entry_ids(d):
    lines = ["`ifndef KEYSTONE86_ENTRY_IDS_SVH", "`define KEYSTONE86_ENTRY_IDS_SVH", ""]
    for x in d["entries"]:
        lines.append(f"`define {x['name']:<18} 8'h{hexw(x['value'],2)}")
    lines += ["", "`endif", ""]
    return "\n".join(lines)

def gen_service_ids(d):
    lines = ["`ifndef KEYSTONE86_SERVICE_IDS_SVH", "`define KEYSTONE86_SERVICE_IDS_SVH", ""]
    for x in d["services"]:
        lines.append(f"`define {x['name']:<26} 8'h{hexw(x['value'],2)}")
    lines += ["", "`endif", ""]
    return "\n".join(lines)

def gen_fault_defs(d):
    lines = ["`ifndef KEYSTONE86_FAULT_DEFS_SVH", "`define KEYSTONE86_FAULT_DEFS_SVH", ""]
    for x in d["faults"]["service_results"]:
        lines.append(f"`define {x['name']:<10} 2'h{x['value']:X}")
    lines.append("")
    for x in d["faults"]["fault_classes"]:
        lines.append(f"`define {x['name']:<10} 4'h{x['value']:X}")
    lines += ["", "`endif", ""]
    return "\n".join(lines)

def gen_commit_defs(d):
    lines = ["`ifndef KEYSTONE86_COMMIT_DEFS_SVH", "`define KEYSTONE86_COMMIT_DEFS_SVH", ""]
    for x in d["stage_fields"]:
        lines.append(f"`define {x['name']:<18} 6'h{hexw(x['value'],2)}")
    lines.append("")
    for x in d["commit_masks"]["bits"]:
        mask = 1 << x["bit"]
        lines.append(f"`define {x['name']:<10} 10'b{mask:010b}")
    lines.append("")
    for x in d["commit_masks"]["combined"]:
        expr = x["expr"]
        expr = rewrap(expr)
        lines.append(f"`define {x['name']:<12} ({expr})")
    lines += ["", "`endif", ""]
    return "\n".join(lines)

def rewrap(expr: str) -> str:
    parts = [p.strip() for p in expr.split("|")]
    return " | ".join(f"`{p}" for p in parts)

def gen_field_defs(d):
    lines = ["`ifndef KEYSTONE86_FIELD_DEFS_SVH", "`define KEYSTONE86_FIELD_DEFS_SVH", "", "// Registers"]
    for x in d["registers"]:
        lines.append(f"`define {x['name']:<12} 4'h{x['value']:X}")
    lines += ["", "// Metadata extract fields"]
    for x in d["extract_fields"]:
        lines.append(f"`define {x['name']:<14} 10'h{hexw(x['value'],3)}")
    lines += ["", "// Conditions"]
    for x in d["conditions"]:
        lines.append(f"`define {x['name']:<10} 4'h{x['value']:X}")
    lines += ["", "`endif", ""]
    return "\n".join(lines)

def gen_pkg(d):
    lines = ["package keystone86_pkg;"]
    for grp_name, grp, width in [
        ("entries", d["entries"][:4], 8),
        ("services", d["services"][:3], 8),
        ("service_results", d["faults"]["service_results"], 2),
        ("fault_classes", d["faults"]["fault_classes"][:3], 4),
    ]:
        lines.append(f"    // {grp_name}")
        for x in grp:
            lines.append(f"    localparam logic [{width-1}:0] {x['name']:<18} = {width}'h{hexw(x['value'], max(1, width//4))};")
        lines.append("")
    lines.append("endpackage")
    lines.append("")
    return "\n".join(lines)

def gen_microcode_exports(d):
    out = {}
    out["entry_ids.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] + [f"{x['name']} = 0x{hexw(x['value'],2)}" for x in d["entries"]] + [""])
    out["service_ids.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] + [f"{x['name']} = 0x{hexw(x['value'],2)}" for x in d["services"]] + [""])
    out["conditions.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] + [f"{x['name']} = 0x{x['value']:X}" for x in d["conditions"]] + [""])
    bit_map = [f"{x['name']} = 0b{(1<<x['bit']):010b}" for x in d["commit_masks"]["bits"]]
    combined = [f"{x['name']} = {x['expr']}" for x in d["commit_masks"]["combined"]]
    out["commit_masks.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] + bit_map + [""] + combined + [""])
    return out

def main():
    d = load()
    write(ROOT / "rtl/include/entry_ids.svh", gen_entry_ids(d))
    write(ROOT / "rtl/include/service_ids.svh", gen_service_ids(d))
    write(ROOT / "rtl/include/fault_defs.svh", gen_fault_defs(d))
    write(ROOT / "rtl/include/commit_defs.svh", gen_commit_defs(d))
    write(ROOT / "rtl/include/field_defs.svh", gen_field_defs(d))
    write(ROOT / "rtl/include/keystone86_pkg.sv", gen_pkg(d))
    exports = gen_microcode_exports(d)
    for name, text in exports.items():
        write(ROOT / "microcode/tools/generators/exports" / name, text)
    print("Generated RTL includes and microcode export includes from appendix_a_codegen.json")

if __name__ == "__main__":
    main()
