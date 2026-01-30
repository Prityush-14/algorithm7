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

## Documentation
- Wrote README with algorithm overview, grammar format, CLI options, and test instructions.

## Summary (Follow-up)
- Added ε-production support (nullable seeding + ε-skip expansions) in both Python and OCaml.
- Added `--start` option to both CLIs and propagated custom start symbols.
- Normalized grammars with multiple start productions by introducing a fresh start symbol.
- Updated H-cover/used-rule formatting to show ε skips, and expanded tests for ε and start normalization.

## Tests (Follow-up)
- Python: `PYTHONPATH=src pytest -q` -> 25 passed
- OCaml: `dune test` (in `ocaml/`) -> 81/81 passed

## Manual Checks (Follow-up)
- Python CLI ε-grammar: `PYTHONPATH=src python -m algorithm7.main --grammar /tmp/epsilon_grammar.txt "b"` -> ACCEPTED
- Python CLI --start: `PYTHONPATH=src python -m algorithm7.main --grammar /tmp/start_grammar.txt --start E "id"` -> ACCEPTED
- Python CLI multi-start: `PYTHONPATH=src python -m algorithm7.main --grammar /tmp/multi_start.txt "a"` -> ACCEPTED
- OCaml CLI ε-grammar: `dune exec algorithm7 -- --grammar /tmp/epsilon_grammar.txt "b"` -> ACCEPTED
- OCaml CLI --start: `dune exec algorithm7 -- --grammar /tmp/start_grammar.txt --start E "id"` -> ACCEPTED
- OCaml CLI multi-start: `dune exec algorithm7 -- --grammar /tmp/multi_start.txt "a"` -> ACCEPTED
