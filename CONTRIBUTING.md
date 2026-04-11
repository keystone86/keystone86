# Contributing to Keystone86

Thank you for contributing.

## First rule

Do not drift the architecture.

This project welcomes:
- bug fixes
- tests
- tooling
- documentation improvements
- implementation cleanup
- performance improvements below existing service boundaries
- new service implementations that preserve the ownership model

This project does **not** accept casual changes that:
- move semantics into the decoder
- move instruction policy into hardware services
- bypass pending commit / ENDI
- create hidden pipeline control meshes
- allow services to become instruction engines

## Contribution lanes

### Lane 1 — Normal contributions
- RTL fixes
- microcode fixes
- tests and regressions
- tooling
- docs clarification
- build improvements

### Lane 2 — Architecture proposals
Anything affecting:
- Appendix A field dictionary
- Appendix B ownership matrix
- Appendix C assembler spec
- Appendix D bring-up ladder
- microcode authority rules
- decoder contract
- commit semantics
- fault ordering

must begin as a proposal in `proposals/` before implementation changes are accepted.

## Pull request checklist

Every PR should answer:

- Does this move semantics into the decoder?
- Does this move policy into hardware?
- Does this bypass commit/ENDI?
- Does this make a service an instruction engine?
- Does this change frozen spec behavior?
- Does this require new regressions?

If any answer is yes, escalate for architecture review.

## DCO

All commits must carry a Signed-off-by line as described in `DCO.md`.
