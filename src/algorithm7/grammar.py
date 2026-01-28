"""Grammar representation for head-driven parsing."""

from dataclasses import dataclass


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
            raise ValueError("Production RHS cannot be empty")
        if not 1 <= self.head_pos <= len(self.rhs):
            raise ValueError(
                f"Head position {self.head_pos} out of range for RHS of length {len(self.rhs)}"
            )

    @property
    def head(self) -> str:
        """Return the head symbol of this production."""
        return self.rhs[self.head_pos - 1]

    def __repr__(self) -> str:
        rhs_str = " ".join(
            f"[{s}]" if i == self.head_pos - 1 else s
            for i, s in enumerate(self.rhs)
        )
        return f"{self.lhs} → {rhs_str}"


class Grammar:
    """A context-free grammar with head annotations.

    Nonterminals are uppercase, terminals are lowercase.
    The start symbol is 'S' by default.
    """

    def __init__(self, start: str = "S"):
        self.start = start
        self.productions: list[Production] = []
        self.nonterminals: set[str] = set()
        self.terminals: set[str] = set()

    def add_production(self, lhs: str, rhs: tuple[str, ...], head_pos: int) -> int:
        """Add a production and return its index."""
        prod = Production(lhs, rhs, head_pos)
        idx = len(self.productions)
        self.productions.append(prod)
        self.nonterminals.add(lhs)
        for symbol in rhs:
            if symbol.isupper():
                self.nonterminals.add(symbol)
            else:
                self.terminals.add(symbol)
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
            rhs = []
            head_pos = None

            for i, part in enumerate(rhs_parts):
                if part.startswith("[") and part.endswith("]"):
                    symbol = part[1:-1]
                    head_pos = i + 1  # 1-indexed
                else:
                    symbol = part
                rhs.append(symbol)

            if head_pos is None:
                head_pos = 1  # Default: first symbol is head

            grammar.add_production(lhs, tuple(rhs), head_pos)

        return grammar

    def __repr__(self) -> str:
        lines = [f"Grammar(start={self.start!r})"]
        for i, p in enumerate(self.productions):
            lines.append(f"  [{i}] {p}")
        return "\n".join(lines)
