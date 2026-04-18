# Review Checklist

- Decoder remains classification-only.
- Microcode retains policy ownership.
- Services remain leaf mechanisms.
- No architectural visibility outside commit_engine + ENDI.
- Instruction behavior remains microcode / microsequencer driven.
- Decoder changes are limited to classification, byte consumption, and required metadata generation.
- Commit logic does not become a hidden per-instruction execution engine.
- Helper RTL does not embed opcode-specific semantics that should belong to dispatch/microcode control.
- Any temporary bootstrap behavior is explicitly identified, narrowly scoped, and justified.
- New fields/enums update Appendix A first.
- New ownership changes update Appendix B first.
- New assembler syntax updates Appendix C first.
- Bring-up sequence remains aligned with Appendix D.
- Shared RTL constants use `import keystone86_pkg::*` — no new `` `include `` of legacy `.svh` headers.
- New authoritative-source relationships are reflected in `docs/implementation/coding_rules/source_of_truth.md`.