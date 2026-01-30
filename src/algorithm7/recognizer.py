"""Algorithm 7: Head-driven tabular recognizer.

Implementation of the head-driven bidirectional parser from Satta & Stock (1994).
"""

from collections import deque
from dataclasses import dataclass, field
from typing import Union

from .grammar import Grammar
from .hcover import (
    HCover, HItem, PartialItem, CompleteItem,
    ProjectionProd, LeftExpandProd, RightExpandProd
)


# Type alias for H-cover rules
HCoverRule = Union[ProjectionProd, LeftExpandProd, RightExpandProd]


@dataclass
class DerivationStep:
    """A step in the derivation, showing how an item was derived.

    Attributes:
        item: The h-item that was derived
        span: The input span (i, j) this item covers
        rule: The H-cover rule used (or None for initial terminal scan)
        children: Child derivation steps that contributed to this step
        terminal: If this is a terminal scan, the terminal symbol
    """
    item: HItem
    span: tuple[int, int]
    rule: HCoverRule | None = None
    children: list["DerivationStep"] = field(default_factory=list)
    terminal: str | None = None

    def format(self, tokens: list[str], indent: int = 0) -> str:
        """Format the derivation step as a string."""
        prefix = "  " * indent
        i, j = self.span
        span_text = " ".join(tokens[i:j]) if tokens else ""

        lines = []
        if self.terminal:
            lines.append(f"{prefix}{self.item} @ [{i},{j}] '{span_text}' (terminal scan: {self.terminal})")
        elif self.rule:
            rule_type = type(self.rule).__name__.replace("Prod", "")
            lines.append(f"{prefix}{self.item} @ [{i},{j}] '{span_text}' ({rule_type})")
        else:
            lines.append(f"{prefix}{self.item} @ [{i},{j}] '{span_text}'")

        for child in self.children:
            lines.append(child.format(tokens, indent + 1))

        return "\n".join(lines)


@dataclass
class UsedHCover:
    """Subset of H-cover rules that were actually used during recognition."""

    grammar: Grammar
    projections: set[ProjectionProd] = field(default_factory=set)
    left_expansions: set[LeftExpandProd] = field(default_factory=set)
    right_expansions: set[RightExpandProd] = field(default_factory=set)

    def format(self, explain: bool = False) -> str:
        """Format the used H-cover for display."""
        lines = []
        symbol_text = lambda s: s if s is not None else "ε"

        if explain:
            lines.append("Used H-Cover Rules (only rules applied during recognition)")
            lines.append("=" * 60)
            lines.append("")
            lines.append("Note: Boundary indices (s,t) follow Satta & Stock 1994")
            lines.append("")
        else:
            lines.append("Used HCover Rules:")

        # Projections
        if explain:
            lines.append("Projections P_H^(1): I_D -> X_H")
            lines.append("-" * 40)
        else:
            lines.append("  Projections:")

        for p in sorted(self.projections, key=lambda x: x.prod_idx):
            if explain:
                prod = self.grammar.productions[p.prod_idx]
                lines.append(f"  {p.lhs} -> {p.head}_H")
                lines.append(f"    Source: [{p.prod_idx}] {prod}")
                lines.append("")
            else:
                lines.append(f"    {p}")

        # Left Expansions
        if explain:
            lines.append("Left Expansions P_H^(2):")
            lines.append("-" * 40)
        else:
            lines.append("  Left Expansions:")

        for e in sorted(self.left_expansions, key=lambda x: (x.source.prod_idx, x.source.s, x.source.t)):
            if explain:
                prod = self.grammar.productions[e.source.prod_idx]
                lines.append(f"  {e.result} -> {symbol_text(e.symbol)} {e.source}")
                lines.append(f"    Source: [{e.source.prod_idx}] {prod}")
                lines.append("")
            else:
                lines.append(f"    {e}")

        # Right Expansions
        if explain:
            lines.append("Right Expansions P_H^(2):")
            lines.append("-" * 40)
        else:
            lines.append("  Right Expansions:")

        for e in sorted(self.right_expansions, key=lambda x: (x.source.prod_idx, x.source.s, x.source.t)):
            if explain:
                prod = self.grammar.productions[e.source.prod_idx]
                lines.append(f"  {e.result} -> {e.source} {symbol_text(e.symbol)}")
                lines.append(f"    Source: [{e.source.prod_idx}] {prod}")
                lines.append("")
            else:
                lines.append(f"    {e}")

        return "\n".join(lines)

    def __repr__(self) -> str:
        return self.format(explain=False)


@dataclass
class Recognizer:
    """Head-driven tabular recognizer (Algorithm 7).

    Uses an (n+1)×(n+1) recognition matrix T where T[i,j] contains
    h-items spanning positions i to j in the input.

    Employs subsumption blocking via Q(i,j,X,d) sets to avoid
    redundant bidirectional expansions.
    """

    grammar: Grammar
    hcover: HCover = field(init=False)
    debug: bool = False

    # Internal state (reset on each recognize call)
    _T: dict[tuple[int, int], set[HItem]] = field(default_factory=dict, repr=False)
    _agenda: deque[tuple[int, int, HItem]] = field(default_factory=deque, repr=False)
    _n: int = field(default=0, repr=False)
    _tokens: list[str] = field(default_factory=list, repr=False)
    _Q_left: dict[tuple[int, int], set[PartialItem]] = field(default_factory=dict, repr=False)
    _Q_right: dict[tuple[int, int], set[PartialItem]] = field(default_factory=dict, repr=False)

    # Tracking for used H-cover rules
    _used_projections: set[ProjectionProd] = field(default_factory=set, repr=False)
    _used_left_expansions: set[LeftExpandProd] = field(default_factory=set, repr=False)
    _used_right_expansions: set[RightExpandProd] = field(default_factory=set, repr=False)

    # Derivation tracking: maps (i, j, item) to derivation info
    _derivations: dict[tuple[int, int, HItem], DerivationStep] = field(default_factory=dict, repr=False)

    def __post_init__(self):
        self.grammar = self.grammar.with_single_start()
        self.hcover = HCover(self.grammar)

    def _reset(self):
        """Reset the recognizer state."""
        self._T = {}
        self._agenda = deque()
        self._Q_left = {}
        self._Q_right = {}
        self._used_projections = set()
        self._used_left_expansions = set()
        self._used_right_expansions = set()
        self._derivations = {}

    def _add_to_T(self, i: int, j: int, item: HItem) -> bool:
        """Add an item to T[i,j]. Returns True if it was new."""
        key = (i, j)
        if key not in self._T:
            self._T[key] = set()
        if item not in self._T[key]:
            self._T[key].add(item)
            return True
        return False

    def _record_derivation(
        self,
        i: int,
        j: int,
        item: HItem,
        rule: HCoverRule | None = None,
        children: list[tuple[int, int, HItem]] | None = None,
        terminal: str | None = None
    ):
        """Record how an item was derived (first derivation only)."""
        key = (i, j, item)
        if key not in self._derivations:
            child_steps = []
            if children:
                for ci, cj, citem in children:
                    child_key = (ci, cj, citem)
                    if child_key in self._derivations:
                        child_steps.append(self._derivations[child_key])
            self._derivations[key] = DerivationStep(
                item=item,
                span=(i, j),
                rule=rule,
                children=child_steps,
                terminal=terminal
            )

    def _add_to_agenda(self, i: int, j: int, item: HItem):
        """Add an item to the agenda if it's new in T."""
        if self._add_to_T(i, j, item):
            self._agenda.append((i, j, item))
            if self.debug:
                print(f"  Added: T[{i},{j}] += {item}")

    def _q_left(self, i: int, j: int) -> set[PartialItem]:
        return self._Q_left.setdefault((i, j), set())

    def _q_right(self, i: int, j: int) -> set[PartialItem]:
        return self._Q_right.setdefault((i, j), set())

    def recognize(self, tokens: list[str]) -> bool:
        """Recognize whether the token sequence is in the language.

        Args:
            tokens: List of terminal symbols

        Returns:
            True if the string is accepted, False otherwise
        """
        self._reset()
        self._n = len(tokens)
        self._tokens = tokens
        n = self._n

        if self.debug:
            print(f"Recognizing: {' '.join(tokens)}")
            print(f"Length n = {n}")

        # Step 1: Initialize - scan terminals and start projections
        if self.debug:
            print("\n=== INIT STEP ===")

        nullables = self.grammar.nullable_nonterminals()
        if nullables:
            for i in range(n + 1):
                for sym in nullables:
                    item = CompleteItem(sym)
                    if self._add_to_T(i, i, item):
                        self._agenda.append((i, i, item))
                        self._record_derivation(i, i, item, terminal="ε")
                        if self.debug:
                            print(f"  Added: T[{i},{i}] += {item} (ε)")

        for i, token in enumerate(tokens):
            if self.debug:
                print(f"Position {i}: terminal '{token}'")

            # Get projections where this terminal is the head
            for proj in self.hcover.get_projections(token):
                item = proj.lhs
                if self._add_to_T(i, i + 1, item):
                    self._agenda.append((i, i + 1, item))
                    self._used_projections.add(proj)
                    self._record_derivation(i, i + 1, item, rule=proj, terminal=token)
                    if self.debug:
                        print(f"  Added: T[{i},{i + 1}] += {item}")

        # Step 2: Process agenda
        if self.debug:
            print("\n=== MAIN LOOP ===")

        while self._agenda:
            i, j, item = self._agenda.popleft()

            if self.debug:
                print(f"\nProcessing: T[{i},{j}], {item}")

            if isinstance(item, PartialItem):
                self._process_partial(i, j, item)
            elif isinstance(item, CompleteItem):
                self._process_complete(i, j, item)

        # Step 3: Accept check
        start_item = CompleteItem(self.grammar.start)
        accepted = start_item in self._T.get((0, n), set())

        if self.debug:
            print(f"\n=== RESULT ===")
            print(f"Looking for {start_item} in T[0,{n}]")
            print(f"T[0,{n}] = {self._T.get((0, n), set())}")
            print(f"Accepted: {accepted}")

        return accepted

    def _process_partial(self, i: int, j: int, item: PartialItem):
        """Process a partial item with terminal/nonterminal expansion."""
        # Left expansion
        if item not in self._q_left(i, j):
            for exp in self.hcover.get_left_expansions(item):
                symbol = exp.symbol
                new_item = exp.result

                if symbol is None:
                    if self._add_to_T(i, j, new_item):
                        self._agenda.append((i, j, new_item))
                        self._used_left_expansions.add(exp)
                        self._record_derivation(i, j, new_item, rule=exp, children=[(i, j, item)], terminal="ε")
                        self._q_right(i, j).add(item)
                        if self.debug:
                            print(f"  Added: T[{i},{j}] += {new_item} (ε)")
                    continue

                if self.grammar.is_terminal(symbol):
                    # Terminal: check if token at i-1 matches
                    if i > 0 and self._tokens[i - 1] == symbol:
                        if self._add_to_T(i - 1, j, new_item):
                            self._agenda.append((i - 1, j, new_item))
                            self._used_left_expansions.add(exp)
                            self._record_derivation(i - 1, j, new_item, rule=exp, children=[(i, j, item)], terminal=symbol)
                            self._q_right(i, j).add(item)
                            if self.debug:
                                print(f"  Added: T[{i - 1},{j}] += {new_item}")
                else:
                    # Nonterminal: look for I_symbol in T[k, i]
                    target = CompleteItem(symbol)
                    for k in range(i):
                        if target in self._T.get((k, i), set()):
                            if self._add_to_T(k, j, new_item):
                                self._agenda.append((k, j, new_item))
                                self._used_left_expansions.add(exp)
                                self._record_derivation(k, j, new_item, rule=exp, children=[(k, i, target), (i, j, item)])
                                self._q_right(i, j).add(item)
                                if self.debug:
                                    print(f"  Added: T[{k},{j}] += {new_item}")

        # Right expansion
        if item not in self._q_right(i, j):
            for exp in self.hcover.get_right_expansions(item):
                symbol = exp.symbol
                new_item = exp.result

                if symbol is None:
                    if self._add_to_T(i, j, new_item):
                        self._agenda.append((i, j, new_item))
                        self._used_right_expansions.add(exp)
                        self._record_derivation(i, j, new_item, rule=exp, children=[(i, j, item)], terminal="ε")
                        self._q_left(i, j).add(item)
                        if self.debug:
                            print(f"  Added: T[{i},{j}] += {new_item} (ε)")
                    continue

                if self.grammar.is_terminal(symbol):
                    # Terminal: check if token at j matches
                    if j < self._n and self._tokens[j] == symbol:
                        if self._add_to_T(i, j + 1, new_item):
                            self._agenda.append((i, j + 1, new_item))
                            self._used_right_expansions.add(exp)
                            self._record_derivation(i, j + 1, new_item, rule=exp, children=[(i, j, item)], terminal=symbol)
                            self._q_left(i, j).add(item)
                            if self.debug:
                                print(f"  Added: T[{i},{j + 1}] += {new_item}")
                else:
                    # Nonterminal: look for I_symbol in T[j, k]
                    target = CompleteItem(symbol)
                    for k in range(j + 1, self._n + 1):
                        if target in self._T.get((j, k), set()):
                            if self._add_to_T(i, k, new_item):
                                self._agenda.append((i, k, new_item))
                                self._used_right_expansions.add(exp)
                                self._record_derivation(i, k, new_item, rule=exp, children=[(i, j, item), (j, k, target)])
                                self._q_left(i, j).add(item)
                                if self.debug:
                                    print(f"  Added: T[{i},{k}] += {new_item}")

    def _process_complete(self, i: int, j: int, item: CompleteItem):
        """Process a complete item, triggering waiting expansions."""
        symbol = item.symbol

        # Project: this nonterminal might be a head for other productions
        for proj in self.hcover.get_projections(symbol):
            proj_item = proj.lhs
            if self._add_to_T(i, j, proj_item):
                self._agenda.append((i, j, proj_item))
                self._used_projections.add(proj)
                self._record_derivation(i, j, proj_item, rule=proj, children=[(i, j, item)])
                if self.debug:
                    print(f"  Added: T[{i},{j}] += {proj_item}")

        # Trigger waiting left expansions: items at [j, k] needing symbol on left
        for k in range(j + 1, self._n + 1):
            for other in list(self._T.get((j, k), set())):
                if isinstance(other, PartialItem):
                    if other in self._q_left(j, k):
                        continue
                    for exp in self.hcover.get_left_expansions(other):
                        if exp.symbol == symbol:
                            if self._add_to_T(i, k, exp.result):
                                self._agenda.append((i, k, exp.result))
                                self._used_left_expansions.add(exp)
                                self._record_derivation(i, k, exp.result, rule=exp, children=[(i, j, item), (j, k, other)])
                                self._q_right(j, k).add(other)
                                if self.debug:
                                    print(f"  Added: T[{i},{k}] += {exp.result}")

        # Trigger waiting right expansions: items at [k, i] needing symbol on right
        for k in range(i):
            for other in list(self._T.get((k, i), set())):
                if isinstance(other, PartialItem):
                    if other in self._q_right(k, i):
                        continue
                    for exp in self.hcover.get_right_expansions(other):
                        if exp.symbol == symbol:
                            if self._add_to_T(k, j, exp.result):
                                self._agenda.append((k, j, exp.result))
                                self._used_right_expansions.add(exp)
                                self._record_derivation(k, j, exp.result, rule=exp, children=[(k, i, other), (i, j, item)])
                                self._q_left(k, i).add(other)
                                if self.debug:
                                    print(f"  Added: T[{k},{j}] += {exp.result}")

    @property
    def T(self) -> dict[tuple[int, int], set[HItem]]:
        """Access the recognition matrix (for inspection after recognition)."""
        return self._T

    def get_used_hcover(self) -> UsedHCover:
        """Return the H-cover rules that were actually used during recognition.

        This filters out unreachable states, showing only rules that contributed
        to the recognition of the input.
        """
        return UsedHCover(
            grammar=self.grammar,
            projections=self._used_projections.copy(),
            left_expansions=self._used_left_expansions.copy(),
            right_expansions=self._used_right_expansions.copy(),
        )

    def get_derivation(self) -> DerivationStep | None:
        """Return the derivation tree for the accepted sentence.

        Returns None if the sentence was not accepted or no derivation was found.
        """
        start_item = CompleteItem(self.grammar.start)
        key = (0, self._n, start_item)
        return self._derivations.get(key)

    def format_derivation(self) -> str:
        """Format the derivation tree as a string.

        Returns a tree representation showing how the input was derived.
        """
        deriv = self.get_derivation()
        if deriv is None:
            return "No derivation found (sentence not accepted)"
        return deriv.format(self._tokens)
