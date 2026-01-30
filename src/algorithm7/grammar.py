"""Grammar representation for head-driven parsing."""

from dataclasses import dataclass

EPSILON_TOKENS = {"ε", "eps", "epsilon"}


@dataclass
class Production:
    """A CFG production with head annotation.

    Attributes:
        lhs: Left-hand side nonterminal
        rhs: Right-hand side symbols (tuple of strings)
        head_pos: 1-indexed position of the head in rhs (τ_r in the paper)
    """
    lhs: str
    rhs: tuple[str, ...]
    head_pos: int

    def __post_init__(self):
        if not self.rhs:
            if self.head_pos != 0:
                raise ValueError("Empty RHS must use head_pos=0")
        else:
            if not 1 <= self.head_pos <= len(self.rhs):
                raise ValueError(
                    f"Head position {self.head_pos} out of range for RHS of length {len(self.rhs)}"
                )

    @property
    def head(self) -> str:
        """Return the head symbol of this production."""
        if not self.rhs:
            raise ValueError("Empty RHS has no head")
        return self.rhs[self.head_pos - 1]

    def __repr__(self) -> str:
        if not self.rhs:
            rhs_str = "ε"
        else:
            rhs_str = " ".join(
                f"[{s}]" if i == self.head_pos - 1 else s
                for i, s in enumerate(self.rhs)
            )
        return f"{self.lhs} → {rhs_str}"


class Grammar:
    """A context-free grammar with head annotations.

    Nonterminals are all symbols that appear on the left-hand side.
    The start symbol is 'S' by default.
    """

    def __init__(self, start: str = "S"):
        self.start = start
        self.productions: list[Production] = []
        self.nonterminals: set[str] = set()
        self.terminals: set[str] = set()

    def _recompute_symbols(self) -> None:
        """Recompute terminal and nonterminal sets from productions."""
        self.nonterminals = {p.lhs for p in self.productions}
        rhs_symbols = {sym for p in self.productions for sym in p.rhs}
        self.terminals = rhs_symbols - self.nonterminals

    def _unique_start_symbol(self) -> str:
        """Generate a start symbol not used elsewhere in the grammar."""
        existing = self.nonterminals | self.terminals | {self.start}
        base = f"{self.start}_START"
        candidate = base
        counter = 1
        while candidate in existing:
            candidate = f"{base}{counter}"
            counter += 1
        return candidate

    def add_production(self, lhs: str, rhs: tuple[str, ...], head_pos: int) -> int:
        """Add a production and return its index."""
        prod = Production(lhs, rhs, head_pos)
        idx = len(self.productions)
        self.productions.append(prod)
        self._recompute_symbols()
        return idx

    def is_terminal(self, symbol: str) -> bool:
        """Check if a symbol is a terminal."""
        return symbol in self.terminals

    def is_nonterminal(self, symbol: str) -> bool:
        """Check if a symbol is a nonterminal."""
        return symbol in self.nonterminals

    def productions_with_head(self, head: str) -> list[tuple[int, Production]]:
        """Return all (index, production) pairs where the head is the given symbol."""
        return [
            (i, p) for i, p in enumerate(self.productions)
            if p.head == head
        ]

    @classmethod
    def from_string(cls, text: str, start: str = "S") -> "Grammar":
        """Parse a grammar from a string representation.

        Format per line:
            LHS -> sym1 sym2 [head] sym3

        The head symbol is marked with square brackets.
        If no head is marked, the first symbol is the head.

        Example:
            S -> NP [VP]
            VP -> cl [v] NP
            NP -> [det] n

        Epsilon productions can be written as:
            A -> ε
            A -> eps
            A -> epsilon
            A ->
        """
        grammar = cls(start)
        for line in text.strip().split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            if "->" not in line:
                raise ValueError(f"Invalid production format: {line}")

            lhs, rhs_str = line.split("->", 1)
            lhs = lhs.strip()

            rhs_parts = rhs_str.split()
            if not rhs_parts or (len(rhs_parts) == 1 and rhs_parts[0] in EPSILON_TOKENS):
                grammar.add_production(lhs, tuple(), 0)
                continue
            rhs = []
            head_pos = None

            for i, part in enumerate(rhs_parts):
                if part.startswith("[") and part.endswith("]"):
                    symbol = part[1:-1]
                    if symbol in EPSILON_TOKENS:
                        raise ValueError("Cannot mark epsilon as head")
                    head_pos = i + 1  # 1-indexed
                else:
                    symbol = part
                if symbol in EPSILON_TOKENS:
                    raise ValueError("Epsilon production must be empty (no symbols)")
                rhs.append(symbol)

            if head_pos is None:
                head_pos = 1  # Default: first symbol is head

            grammar.add_production(lhs, tuple(rhs), head_pos)

        return grammar

    def nullable_nonterminals(self) -> set[str]:
        """Compute the set of nullable nonterminals (A =>* ε)."""
        nullable = {p.lhs for p in self.productions if not p.rhs}
        changed = True
        while changed:
            changed = False
            for p in self.productions:
                if p.lhs in nullable:
                    continue
                if not p.rhs:
                    nullable.add(p.lhs)
                    changed = True
                    continue
                all_nullable = True
                for sym in p.rhs:
                    if sym not in self.nonterminals:
                        all_nullable = False
                        break
                    if sym not in nullable:
                        all_nullable = False
                        break
                if all_nullable:
                    nullable.add(p.lhs)
                    changed = True
        return nullable

    def with_single_start(self) -> "Grammar":
        """Return a grammar with a single start production.

        If multiple productions rewrite the start symbol, a fresh start
        symbol S' is introduced with a single production S' -> S.
        """
        start_prods = [p for p in self.productions if p.lhs == self.start]
        if len(start_prods) <= 1:
            return self

        new_start = self._unique_start_symbol()
        normalized = Grammar(start=new_start)
        for prod in self.productions:
            normalized.add_production(prod.lhs, prod.rhs, prod.head_pos)
        normalized.add_production(new_start, (self.start,), head_pos=1)
        return normalized

    def __repr__(self) -> str:
        lines = [f"Grammar(start={self.start!r})"]
        for i, p in enumerate(self.productions):
            lines.append(f"  [{i}] {p}")
        return "\n".join(lines)
