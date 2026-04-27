# Namespace Sync Rule

The following namespaces must remain aligned:

- Appendix A frozen encodings
- `rtl/include/*.svh`
- `rtl/include/keystone86_pkg.sv`
- microcode generator exports in `microcode/tools/generators/exports/`

Preferred workflow:
Appendix A is frozen/protected; editing it requires explicit protected-file authorization/proposal before namespace synchronization proceeds.
1. Update Appendix A
2. Regenerate shared include/export artifacts
3. Rebuild microcode
4. Run spec and symbol consistency checks
