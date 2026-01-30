# Algorithm7 Update Log

Date: 2026-01-30

## Summary
- Aligned h-cover construction with Satta & Stock (1994) Definitions 4/5 using boundary indices (0 ≤ s < τ ≤ t ≤ n, excluding (0,n)).
- Implemented Algorithm 7 subsumption blocking (Q sets) in both Python and OCaml recognizers.
- Updated projection handling (length-1 productions now project directly to complete items).
- Grammar symbol classification now derives nonterminals from LHS symbols instead of case.
- Updated formatting and tests to reflect the paper-accurate h-cover and boundaries.

## Tests
- Python: `PYTHONPATH=src pytest -q` -> 21 passed
- OCaml: `dune test` (in `ocaml/`) -> 70/70 passed

## Included Repo Cleanup
- Added CLI options in both Python and OCaml for showing used rules, derivations, and explain mode.
- Exposed used-hcover and derivation APIs in the OCaml interface.
- Tracked the paper PDF in-repo.
