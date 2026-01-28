"""H-cover construction for head-driven parsing.

Implements Definitions 4 and 5 from Satta & Stock (1994).

An h-cover transforms a CFG G into G_H with:
- H-items as nonterminals
- Projection productions P_H^(1): I_D → X_H (complete item from head)
- Expansion productions P_H^(2): partial item extensions
"""

from dataclasses import dataclass
from typing import Union

from .grammar import Grammar


@dataclass(frozen=True)
class PartialItem:
    """A partial h-item I_r^(s,t).

    Represents partial recognition of production r,
    having processed symbols from position s to t (1-indexed, inclusive).
    """
    prod_idx: int  # Production index r
    s: int         # Left boundary (1-indexed)
    t: int         # Right boundary (1-indexed)

    def __repr__(self) -> str:
        return f"I_{self.prod_idx}^({self.s},{self.t})"


@dataclass(frozen=True)
class CompleteItem:
    """A complete h-item I_A.

    Represents complete recognition of nonterminal A.
    """
    symbol: str  # Nonterminal A

    def __repr__(self) -> str:
        return f"I_{self.symbol}"


# Type alias for any h-item
HItem = Union[PartialItem, CompleteItem]


@dataclass(frozen=True)
class ProjectionProd:
    """A projection production from P_H^(1).

    Form: I_D → X_H
    where D is a nonterminal and X is its head.
    """
    lhs: CompleteItem  # I_D
    head: str          # X_H (the head symbol)
    prod_idx: int      # Which production this projects from

    def __repr__(self) -> str:
        return f"{self.lhs} → {self.head}_H (prod {self.prod_idx})"


@dataclass(frozen=True)
class LeftExpandProd:
    """A left-expansion production from P_H^(2).

    Form: I_r^(s-1,t) → X_{s-1} I_r^(s,t)
    Extends a partial item leftward.
    """
    result: PartialItem  # I_r^(s-1,t)
    symbol: str          # X_{s-1}
    source: PartialItem  # I_r^(s,t)
    direction: str = "left"

    def __repr__(self) -> str:
        return f"{self.result} → {self.symbol} {self.source}"


@dataclass(frozen=True)
class RightExpandProd:
    """A right-expansion production from P_H^(2).

    Form: I_r^(s,t+1) → I_r^(s,t) X_{t+1}
    Extends a partial item rightward.
    """
    result: PartialItem  # I_r^(s,t+1)
    source: PartialItem  # I_r^(s,t)
    symbol: str          # X_{t+1}
    direction: str = "right"

    def __repr__(self) -> str:
        return f"{self.result} → {self.source} {self.symbol}"


@dataclass(frozen=True)
class CompleteProd:
    """A completion production from P_H^(2).

    Form: I_A → I_r^(1,|α|)
    Completes a nonterminal when a partial item spans the full RHS.
    """
    result: CompleteItem  # I_A
    source: PartialItem   # I_r^(1,|α|)
    prod_idx: int         # Production index

    def __repr__(self) -> str:
        return f"{self.result} → {self.source}"


class HCover:
    """The h-cover G_H of a grammar G.

    Provides methods to:
    - Look up projection productions by head symbol
    - Look up expansion productions for extending partial items
    - Look up completion productions for full spans
    """

    def __init__(self, grammar: Grammar):
        self.grammar = grammar

        # P_H^(1): Projection productions indexed by head symbol
        self.projections: dict[str, list[ProjectionProd]] = {}

        # P_H^(2): Expansion productions indexed by source item
        self.left_expansions: dict[PartialItem, list[LeftExpandProd]] = {}
        self.right_expansions: dict[PartialItem, list[RightExpandProd]] = {}

        # Completion productions indexed by source partial item
        self.completions: dict[PartialItem, CompleteProd] = {}

        self._build()

    def _build(self):
        """Build the h-cover from the grammar."""
        for r, prod in enumerate(self.grammar.productions):
            tau = prod.head_pos  # Head position (1-indexed)
            n = len(prod.rhs)    # RHS length

            # P_H^(1): Projection production
            # I_{prod.lhs} → prod.head_H
            head = prod.head
            proj = ProjectionProd(
                lhs=CompleteItem(prod.lhs),
                head=head,
                prod_idx=r
            )
            if head not in self.projections:
                self.projections[head] = []
            self.projections[head].append(proj)

            # P_H^(2): Expansion and completion productions
            # Starting item: I_r^(tau, tau) - just the head
            # We need to generate all possible partial items and their expansions

            # Generate all possible partial items for this production
            for s in range(1, tau + 1):
                for t in range(tau, n + 1):
                    source = PartialItem(r, s, t)

                    # Left expansion: if s > 1, we can extend left
                    if s > 1:
                        result = PartialItem(r, s - 1, t)
                        symbol = prod.rhs[s - 2]  # X_{s-1} (0-indexed)
                        exp = LeftExpandProd(result, symbol, source)
                        if source not in self.left_expansions:
                            self.left_expansions[source] = []
                        self.left_expansions[source].append(exp)

                    # Right expansion: if t < n, we can extend right
                    if t < n:
                        result = PartialItem(r, s, t + 1)
                        symbol = prod.rhs[t]  # X_{t+1} (0-indexed)
                        exp = RightExpandProd(result, source, symbol)
                        if source not in self.right_expansions:
                            self.right_expansions[source] = []
                        self.right_expansions[source].append(exp)

                    # Completion: if spans full RHS (1 to n)
                    if s == 1 and t == n:
                        comp = CompleteProd(
                            result=CompleteItem(prod.lhs),
                            source=source,
                            prod_idx=r
                        )
                        self.completions[source] = comp

    def get_projections(self, head: str) -> list[ProjectionProd]:
        """Get projection productions for a head symbol."""
        return self.projections.get(head, [])

    def get_left_expansions(self, item: PartialItem) -> list[LeftExpandProd]:
        """Get left-expansion productions for a partial item."""
        return self.left_expansions.get(item, [])

    def get_right_expansions(self, item: PartialItem) -> list[RightExpandProd]:
        """Get right-expansion productions for a partial item."""
        return self.right_expansions.get(item, [])

    def get_completion(self, item: PartialItem) -> CompleteProd | None:
        """Get completion production for a partial item (if it spans full RHS)."""
        return self.completions.get(item)

    def initial_item(self, prod_idx: int) -> PartialItem:
        """Get the initial partial item for a production (just the head)."""
        prod = self.grammar.productions[prod_idx]
        tau = prod.head_pos
        return PartialItem(prod_idx, tau, tau)

    def __repr__(self) -> str:
        lines = ["HCover:"]
        lines.append("  Projections:")
        for head, projs in self.projections.items():
            for p in projs:
                lines.append(f"    {p}")
        lines.append("  Left Expansions:")
        for source, exps in self.left_expansions.items():
            for e in exps:
                lines.append(f"    {e}")
        lines.append("  Right Expansions:")
        for source, exps in self.right_expansions.items():
            for e in exps:
                lines.append(f"    {e}")
        lines.append("  Completions:")
        for source, comp in self.completions.items():
            lines.append(f"    {comp}")
        return "\n".join(lines)
