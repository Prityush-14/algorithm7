# Algorithm7

Head-driven bidirectional tabular recognizer (Algorithm 7) based on Satta & Stock (1994).
This repo provides **both** a Python and an OCaml implementation, plus a CLI for each.

The implementation now follows the paper's h-cover definitions and subsumption blocking rules.
The paper PDF is included in `satta1994.pdf`.

## Paper Concepts (Brief)

Let a CFG be G = (N, Σ, P, S). Each production `D_r -> Z_{r,1} ... Z_{r,n_r}` has a designated
head position `τ_r` (1-indexed within the RHS).

### h-items
- Partial h-items: `I_r^(s,t)` where `0 ≤ s < τ_r ≤ t ≤ n_r` and `(s,t) ≠ (0,n_r)`.
- Complete h-items: `I_A` for each nonterminal `A ∈ N`.

### h-cover `G_H`
`G_H = (I^(H), Σ, P_H, I_S)` with productions partitioned as:

**P_H^(1) (projections)**
- If `n_r = 1`: `I_{D_r} -> X_H` where `X` is the head symbol.
- If `n_r > 1`: `I_r^(τ_r-1, τ_r) -> X_H`.

**P_H^(2) (expansions)**
- Left expand: `I_r^(s,t) -> X_H I_r^(s+1,t)` (when defined)
- Right expand: `I_r^(s,t) -> I_r^(s,t-1) Y_H` (when defined)
- Completion (as expansions in the paper):
  - `I_{D_r} -> X_H I_r^(1, n_r)` (left completion, if `τ_r > 1`)
  - `I_{D_r} -> I_r^(0, n_r-1) Y_H` (right completion, if `τ_r < n_r`)

### Algorithm 7 (Recognizer)
The recognizer builds a chart `T[i,j]` of h-items spanning input substring `[i,j)` and uses
an agenda. It performs:

1) **Init**: scan terminals; add projection items driven by head matches.
2) **Project**: from complete items (heads), add their projection items.
3) **Left/Right Expand**: extend partial items by matching terminals or complete items.
4) **Subsumption blocking**: Q-sets (`Q(i,j,left/right)`) prevent redundant expansions on
   both sides of the same partial item.
5) **Accept** if `I_S ∈ T[0,n]`.

Both implementations follow this structure, including the Q-set blocking.

**Nullable (ε) support**: Following Appendix A, nullable nonterminals are seeded into
`T[i,i]` for all spans, and nullable symbols on either side of a head are handled with
ε-skip expansions in the h-cover.

## Grammar Format
One production per line:

```
S -> NP [VP]
VP -> cl [v] NP
NP -> [det] n
```

- The head symbol is marked with `[ ... ]`.
- If no head is marked, the **first** symbol is the head.
- Lines can be commented with `#`.
- **Nonterminals are all symbols that appear on the LHS**. Everything else is a terminal.
- ε-productions are supported:
  - Use `A -> ε`, `A -> eps`, `A -> epsilon`, or an empty RHS (`A ->`).
  - Epsilon productions must be empty (do not mix ε with other symbols).
- Start symbol defaults to `S` (override with `--start` or `Grammar.from_string(..., start=...)`).
- If multiple productions rewrite the start symbol, the recognizer introduces a fresh start
  symbol (e.g., `S_START`) with a single production `S_START -> S`.

## CLI (Python)

Run directly from source:

```
PYTHONPATH=src python -m algorithm7.main --example "det n cl v det n"
```

Or, if installed as a package:

```
algorithm7 --example "det n cl v det n"
```

## CLI (OCaml)

```
cd ocaml

dune exec algorithm7 -- --example "det n cl v det n"
```

## CLI Options (Shared)

```
-g, --grammar FILE    Load grammar from file
-e, --example         Use the example grammar from the paper
--start SYMBOL        Start symbol (default: S)
--show-grammar        Print the grammar and exit
--show-hcover         Print the h-cover and exit
--show-used-rules     Show only the H-cover rules used during recognition
--show-derivation     Print a derivation tree
-x, --explain         Verbose explanations (with --show-hcover or --show-used-rules)
-d, --debug           Debug output
-h, --help            Show help
```

Notes:
- If `--show-grammar` or `--show-hcover` is used, input is not required.
- Exit code is `0` for ACCEPT, `1` for REJECT.

## Library Usage (Python)

```
from algorithm7.grammar import Grammar
from algorithm7.recognizer import Recognizer

g = Grammar.from_string("""
S -> NP [VP]
VP -> cl [v] NP
NP -> [det] n
""")

rec = Recognizer(grammar=g)
print(rec.recognize(["det", "n", "cl", "v", "det", "n"]))  # True
```

## Tests

Python:
```
PYTHONPATH=src pytest -q
```

OCaml:
```
cd ocaml

dune test
```

## Repo Layout

- `src/algorithm7/` — Python implementation
- `ocaml/lib/` — OCaml implementation
- `tests/` and `ocaml/test/` — test suites
- `satta1994.pdf` — reference paper
- `LOG.md` — change log

## Known Limitations

- Nullable heads are allowed but may be inefficient (the paper recommends avoiding
  nullable heads for Algorithm 7).
- Epsilon productions follow the Appendix A adaptation (nullable seeding + ε-skip
  expansions). Grammars with ε on the head symbol may be slower.
