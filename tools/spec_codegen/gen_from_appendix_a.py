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
        expr = rewrap(x["expr"])
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
    """Generate the complete authoritative RTL package from appendix_a_codegen.json.

    Sections generated:
      - ENTRY_* identifiers (all entries)
      - SVC_* / service identifiers (all services, grouped)
      - SR_* service result codes
      - FC_* fault class codes
      - CM_* commit mask bits and combined masks
      - STAGE_* field selectors
      - REG_* register namespace
      - C_* condition codes
      - MSEQ_* microsequencer states (hardcoded — not in JSON)
    """
    lines = [
        "// Keystone86 / Aegis",
        "// keystone86_pkg.sv — Complete shared parameter package",
        "// Auto-generated from Appendix A Field Dictionary (frozen spec)",
        "// DO NOT EDIT MANUALLY — regenerate via: make codegen",
        "//",
        "// This file is the AUTHORITATIVE RTL source for all shared constants.",
        "// All RTL modules must use: import keystone86_pkg::*;",
        "//",
        "// The legacy *.svh files in this directory (entry_ids.svh, fault_defs.svh,",
        "// commit_defs.svh, field_defs.svh, service_ids.svh) contain the same",
        "// constants as backtick macros. They are retained for compatibility with",
        "// external tooling only. RTL source files must NOT use `include for these —",
        "// use this package import instead.",
        "//",
        "// See docs/implementation/coding_rules/source_of_truth.md for the full",
        "// authoritative-source map.",
        "",
        "package keystone86_pkg;",
        "",
        "    // ----------------------------------------------------------------",
        "    // ENTRY IDENTIFIERS (Appendix A Section 4)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["entries"]:
        comment = ""
        name = x["name"]
        val = x["value"]
        # Add phase comments matching the hand-authored version
        if name in ("ENTRY_JMP_FAR", "ENTRY_CALL_FAR", "ENTRY_RET_FAR",
                    "ENTRY_SEG_LOAD", "ENTRY_MISC_SYSTEM"):
            comment = "  // phase 2"
        elif name == "ENTRY_STRING_BASIC":
            comment = "  // phase 3"
        elif name == "ENTRY_RESET":
            comment = "  // startup only"
        lines.append(f"    localparam logic [7:0] {name:<22} = 8'h{hexw(val,2)};{comment}")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // SERVICE IDENTIFIERS (Appendix A Section 5)",
        "    // ----------------------------------------------------------------",
        "    localparam logic [7:0] SVC_NULL                 = 8'h00;",
        "    // Fetch",
    ]
    # Services — emit with grouping comments matching hand-authored version
    svc_groups = {
        "FETCH_IMM8":       "    // Fetch",
        "EA_CALC_16":       "    // Address",
        "LOAD_RM8":         "    // Operand",
        "ALU_ADD8":         "    // ALU",
        "PUSH16":           "    // Stack/flow",
        "LOAD_DESCRIPTOR":  "    // Descriptor (phase 2)",
        "PREPARE_CALL_GATE":"    // Interrupt/flow",
        "PAGE_XLATE_FETCH": "    // Memory (phase 2/3)",
        "COMMIT_GPR":       "    // Commit",
    }
    svc_phase2 = {"SEG_DEFAULT_SELECT", "LINEARIZE_OFFSET", "SHIFT_ROT", "MUL_IMUL",
                  "DIV_IDIV", "VALIDATE_FAR_TRANSFER", "LOAD_DESCRIPTOR", "CHECK_SEG_ACCESS",
                  "CHECK_DESCRIPTOR_PRESENT", "CHECK_CODE_SEG_TRANSFER",
                  "CHECK_STACK_SEG_TRANSFER", "LOAD_SEG_VISIBLE", "LOAD_SEG_HIDDEN",
                  "COMMIT_SEG_CACHE", "FAR_RETURN_VALIDATE", "PAGE_XLATE_FETCH",
                  "PAGE_XLATE_READ", "PAGE_XLATE_WRITE", "MEM_READ8", "MEM_READ16",
                  "MEM_READ32", "MEM_WRITE8", "MEM_WRITE16", "MEM_WRITE32", "COMMIT_SEG"}
    svc_phase3 = {"PREPARE_CALL_GATE", "PREPARE_TASK_SWITCH", "FAR_RETURN_OUTER_VALIDATE"}
    emitted_header = {"FETCH_IMM8"}  # already emitted Fetch header above
    for x in d["services"]:
        name = x["name"]
        val = x["value"]
        if name in svc_groups and name not in emitted_header:
            lines.append(svc_groups[name])
        comment = ""
        if name in svc_phase3:
            comment = "  // phase 3"
        elif name in svc_phase2:
            comment = "  // phase 2"
        lines.append(f"    localparam logic [7:0] {name:<26} = 8'h{hexw(val,2)};{comment}")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // SERVICE RESULT CODES (Appendix A Section 6.2)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["faults"]["service_results"]:
        lines.append(f"    localparam logic [1:0] {x['name']:<8} = 2'h{x['value']:X};")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // FAULT CLASS CODES (Appendix A Section 6.1)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["faults"]["fault_classes"]:
        lines.append(f"    localparam logic [3:0] {x['name']:<8} = 4'h{x['value']:X};")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // COMMIT MASK BITS (Appendix A Section 3.8)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["commit_masks"]["bits"]:
        mask = 1 << x["bit"]
        lines.append(f"    localparam logic [9:0] {x['name']:<12} = 10'b{mask:010b};")
    lines.append("    // Standard combined masks (Appendix A Section 3.9)")
    for x in d["commit_masks"]["combined"]:
        expr = " | ".join(x["expr"].split(" | "))
        lines.append(f"    localparam logic [9:0] {x['name']:<12} = {expr};")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // STAGE FIELD SELECTORS (Appendix A Section 3.7)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["stage_fields"]:
        lines.append(f"    localparam logic [5:0] {x['name']:<18} = 6'h{hexw(x['value'],2)};")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // MICROINSTRUCTION REGISTER NAMESPACE (Appendix A Section 7.4)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["registers"]:
        lines.append(f"    localparam logic [3:0] {x['name']:<12} = 4'h{x['value']:X};")

    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // CONDITION CODES (Appendix A Section 7.3)",
        "    // ----------------------------------------------------------------",
    ]
    for x in d["conditions"]:
        lines.append(f"    localparam logic [3:0] {x['name']:<10} = 4'h{x['value']:X};")

    # MSEQ states are not in the JSON — hardcoded architectural constants
    lines += [
        "",
        "    // ----------------------------------------------------------------",
        "    // MICROSEQUENCER STATES",
        "    // ----------------------------------------------------------------",
        "    localparam logic [1:0] MSEQ_FETCH_DECODE  = 2'h0;",
        "    localparam logic [1:0] MSEQ_EXECUTE       = 2'h1;",
        "    localparam logic [1:0] MSEQ_WAIT_SERVICE  = 2'h2;",
        "    localparam logic [1:0] MSEQ_FAULT_HOLD    = 2'h3;",
        "",
        "endpackage",
        "",
    ]
    return "\n".join(lines)

def gen_microcode_exports(d):
    out = {}
    out["entry_ids.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] +
        [f"{x['name']} = 0x{hexw(x['value'],2)}" for x in d["entries"]] + [""])
    out["service_ids.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] +
        [f"{x['name']} = 0x{hexw(x['value'],2)}" for x in d["services"]] + [""])
    out["conditions.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] +
        [f"{x['name']} = 0x{x['value']:X}" for x in d["conditions"]] + [""])
    bit_map = [f"{x['name']} = 0b{(1<<x['bit']):010b}" for x in d["commit_masks"]["bits"]]
    combined = [f"{x['name']} = {x['expr']}" for x in d["commit_masks"]["combined"]]
    out["commit_masks.inc"] = "\n".join(["; Auto-generated from appendix_a_codegen.json", ""] +
        bit_map + [""] + combined + [""])
    return out

def main():
    d = load()
    write(ROOT / "rtl/include/entry_ids.svh",   gen_entry_ids(d))
    write(ROOT / "rtl/include/service_ids.svh", gen_service_ids(d))
    write(ROOT / "rtl/include/fault_defs.svh",  gen_fault_defs(d))
    write(ROOT / "rtl/include/commit_defs.svh", gen_commit_defs(d))
    write(ROOT / "rtl/include/field_defs.svh",  gen_field_defs(d))
    write(ROOT / "rtl/include/keystone86_pkg.sv", gen_pkg(d))
    exports = gen_microcode_exports(d)
    for name, text in exports.items():
        write(ROOT / "microcode/tools/generators/exports" / name, text)
    print("Generated RTL includes and microcode export includes from appendix_a_codegen.json")

if __name__ == "__main__":
    main()
