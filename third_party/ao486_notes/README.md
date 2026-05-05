# ao486 Notes

Imported from `https://github.com/MiSTer-devel/ao486_MiSTer` at commit `79db96be8a37cdfcc2738836bf343d1dbdf214cc` on 2026-05-05.

This directory contains ao486 semantic donor material only. The imported command-description corpus under `commands/` provides instruction-behavior context for translation into Keystone86's own microcoded architecture.

The imported `CMD_*.txt` and `common_*.txt` files do not authorize Rung 6 scope expansion. Rung 6 may use only MOV-relevant behavior allowed by `docs/implementation/bringup/rung6.md` and Appendix D unless later explicit authorization says otherwise.

ao486 RTL, pipeline structure, token-passing, generated Verilog, hazard logic, and MiSTer platform integration must not be imported into Keystone86 architecture.

License/provenance status at import time: upstream `LICENSE` was present and imported as `upstream/LICENSE`; upstream `README.md` was present and imported as `upstream/README.md`.
