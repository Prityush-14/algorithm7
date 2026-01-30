"""H-cover construction for head-driven parsing.

Implements Definitions 4 and 5 from Satta & Stock (1994).

An h-cover transforms a CFG G into G_H with:
- H-items as nonterminals
- Projection productions P_H^(1): I_D or I_r^(τ-1,τ) → X_H
- Expansion productions P_H^(2): partial item extensions
"""

from dataclasses import dataclass
from typing import Union

from .grammar import Grammar


@dataclass(frozen=True)
class PartialItem:
    """A partial h-item I_r^(s,t).

    Represents partial recognition of production r,
    having processed symbols from boundary s to t (0-indexed, inclusive),
    where 0 ≤ s < τ_r ≤ t ≤ n_r and (s, t) ≠ (0, n_r).
    """
    prod_idx: int  # Production index r
    s: int         # Left boundary (0-indexed)
    t: int         # Right boundary (0-indexed)

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
    lhs: HItem         # I_D (n_r=1) or I_r^(τ-1,τ) (n_r>1)
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
    result: HItem        # I_r^(s-1,t) or I_D (completion)
    symbol: str | None   # X_{s-1} (None means ε-skip)
    source: PartialItem  # I_r^(s,t)
    direction: str = "left"

    def __repr__(self) -> str:
        sym = self.symbol if self.symbol is not None else "ε"
        return f"{self.result} → {sym} {self.source}"


@dataclass(frozen=True)
class RightExpandProd:
    """A right-expansion production from P_H^(2).

    Form: I_r^(s,t+1) → I_r^(s,t) X_{t+1}
    Extends a partial item rightward.
    """
    result: HItem        # I_r^(s,t+1) or I_D (completion)
    source: PartialItem  # I_r^(s,t)
    symbol: str | None   # X_{t+1} (None means ε-skip)
    direction: str = "right"

    def __repr__(self) -> str:
        sym = self.symbol if self.symbol is not None else "ε"
        return f"{self.result} → {self.source} {sym}"


class HCover:
    """The h-cover G_H of a grammar G.

    Provides methods to:
    - Look up projection productions by head symbol
    - Look up expansion productions for extending partial items
    - Look up completion productions for full spans
    """

    def __init__(self, grammar: Grammar):
        self.grammar = grammar
        self.nullables = grammar.nullable_nonterminals()

        # P_H^(1): Projection productions indexed by head symbol
        self.projections: dict[str, list[ProjectionProd]] = {}

        # P_H^(2): Expansion productions indexed by source item
        self.left_expansions: dict[PartialItem, list[LeftExpandProd]] = {}
        self.right_expansions: dict[PartialItem, list[RightExpandProd]] = {}

        self._build()

    def _build(self):
        """Build the h-cover from the grammar."""
        for r, prod in enumerate(self.grammar.productions):
            if len(prod.rhs) == 0:
                continue
            tau = prod.head_pos  # Head position (1-indexed)
            n = len(prod.rhs)    # RHS length

            # P_H^(1): Projection production
            # I_{prod.lhs} → prod.head_H
            head = prod.head
            if n == 1:
                proj_lhs: HItem = CompleteItem(prod.lhs)
            else:
                proj_lhs = PartialItem(r, tau - 1, tau)
            proj = ProjectionProd(lhs=proj_lhs, head=head, prod_idx=r)
            if head not in self.projections:
                self.projections[head] = []
            self.projections[head].append(proj)

            # P_H^(2): Expansions (only for length > 1)
            if n == 1:
                continue

            # Left expansions: I_r^(s,t) -> X_H I_r^(s+1,t)
            for s in range(0, tau - 1):
                for t in range(tau, n + 1):
                    result = PartialItem(r, s, t)
                    if result.s == 0 and result.t == n:
                        continue
                    source = PartialItem(r, s + 1, t)
                    symbol = prod.rhs[s]  # Z_{r,s+1}
                    exp = LeftExpandProd(result, symbol, source)
                    self.left_expansions.setdefault(source, []).append(exp)
                    if symbol in self.nullables:
                        self.left_expansions[source].append(
                            LeftExpandProd(result, None, source)
                        )

            # Right expansions: I_r^(s,t) -> I_r^(s,t-1) Y_H
            for s in range(0, tau):
                for t in range(tau + 1, n + 1):
                    result = PartialItem(r, s, t)
                    if result.s == 0 and result.t == n:
                        continue
                    source = PartialItem(r, s, t - 1)
                    symbol = prod.rhs[t - 1]  # Z_{r,t}
                    exp = RightExpandProd(result, source, symbol)
                    self.right_expansions.setdefault(source, []).append(exp)
                    if symbol in self.nullables:
                        self.right_expansions[source].append(
                            RightExpandProd(result, source, None)
                        )

            # Completions (P_H^(2)(b)) as expansions to complete I_D
            # Left completion: I_D -> X_H I_r^(1,n)
            if tau > 1:
                source = PartialItem(r, 1, n)
                symbol = prod.rhs[0]
                comp = LeftExpandProd(CompleteItem(prod.lhs), symbol, source)
                self.left_expansions.setdefault(source, []).append(comp)
                if symbol in self.nullables:
                    self.left_expansions[source].append(
                        LeftExpandProd(CompleteItem(prod.lhs), None, source)
                    )

            # Right completion: I_D -> I_r^(0,n-1) Y_H
            if tau < n:
                source = PartialItem(r, 0, n - 1)
                symbol = prod.rhs[n - 1]
                comp = RightExpandProd(CompleteItem(prod.lhs), source, symbol)
                self.right_expansions.setdefault(source, []).append(comp)
                if symbol in self.nullables:
                    self.right_expansions[source].append(
                        RightExpandProd(CompleteItem(prod.lhs), source, None)
                    )

    def get_projections(self, head: str) -> list[ProjectionProd]:
        """Get projection productions for a head symbol."""
        return self.projections.get(head, [])

    def get_left_expansions(self, item: PartialItem) -> list[LeftExpandProd]:
        """Get left-expansion productions for a partial item."""
        return self.left_expansions.get(item, [])

    def get_right_expansions(self, item: PartialItem) -> list[RightExpandProd]:
        """Get right-expansion productions for a partial item."""
        return self.right_expansions.get(item, [])

    def initial_item(self, prod_idx: int) -> PartialItem:
        """Get the initial partial item for a production (just the head)."""
        prod = self.grammar.productions[prod_idx]
        tau = prod.head_pos
        if len(prod.rhs) == 1:
            raise ValueError("No partial items for length-1 productions")
        return PartialItem(prod_idx, tau - 1, tau)

    def __repr__(self) -> str:
        return self.format(explain=False)

    def format(self, explain: bool = False) -> str:
        """Format the H-cover for display.

        Args:
            explain: If True, include detailed explanations and source productions
        """
        lines = []

        if explain:
            lines.append("H-Cover G_H (covering grammar for G)")
            lines.append("=" * 50)
            lines.append("")
            lines.append("Note: Boundary indices (s,t) follow Satta & Stock 1994")
            lines.append("  I_r^(s,t) with 0 ≤ s < τ ≤ t ≤ n and (s,t) ≠ (0,n)")
            lines.append("  I_A = complete recognition of nonterminal A")
            lines.append("")
        else:
            lines.append("HCover:")

        # Projections
        if explain:
            lines.append("Projections P_H^(1): I_D -> X_H")
            lines.append("  (To recognize D, first find its head X)")
            lines.append("-" * 40)
        else:
            lines.append("  Projections:")

        for head, projs in self.projections.items():
            for p in projs:
                if explain:
                    prod = self.grammar.productions[p.prod_idx]
                    lines.append(f"  {p.lhs} -> {p.head}_H")
                    lines.append(f"    Source: [{p.prod_idx}] {prod}")
                    lines.append(f"    Meaning: To recognize {p.lhs}, first find head '{p.head}'")
                    lines.append("")
                else:
                    lines.append(f"    {p}")

        # Left Expansions
        if explain:
            lines.append("Left Expansions P_H^(2): I_r^(s-1,t) -> X_{s-1} I_r^(s,t)")
            lines.append("  (Extend partial item leftward by consuming X)")
            lines.append("-" * 40)
        else:
            lines.append("  Left Expansions:")

        for source, exps in self.left_expansions.items():
            for e in exps:
                if explain:
                    prod = self.grammar.productions[e.source.prod_idx]
                    sym = e.symbol if e.symbol is not None else "ε"
                    lines.append(f"  {e.result} -> {sym} {e.source}")
                    lines.append(f"    Source: [{e.source.prod_idx}] {prod}")
                    if isinstance(e.result, PartialItem):
                        lines.append(f"    Meaning: Extend left by consuming '{sym}' at boundary {e.result.s}")
                    else:
                        lines.append(f"    Meaning: Complete {e.result.symbol} by consuming '{sym}' on the left")
                    lines.append("")
                else:
                    lines.append(f"    {e}")

        # Right Expansions
        if explain:
            lines.append("Right Expansions P_H^(2): I_r^(s,t+1) -> I_r^(s,t) X_{t+1}")
            lines.append("  (Extend partial item rightward by consuming X)")
            lines.append("-" * 40)
        else:
            lines.append("  Right Expansions:")

        for source, exps in self.right_expansions.items():
            for e in exps:
                if explain:
                    prod = self.grammar.productions[e.source.prod_idx]
                    sym = e.symbol if e.symbol is not None else "ε"
                    lines.append(f"  {e.result} -> {e.source} {sym}")
                    lines.append(f"    Source: [{e.source.prod_idx}] {prod}")
                    if isinstance(e.result, PartialItem):
                        lines.append(f"    Meaning: Extend right by consuming '{sym}' at boundary {e.result.t}")
                    else:
                        lines.append(f"    Meaning: Complete {e.result.symbol} by consuming '{sym}' on the right")
                    lines.append("")
                else:
                    lines.append(f"    {e}")

        return "\n".join(lines)
