"""Algorithm 7: Head-driven tabular recognizer.

Implementation of the head-driven bidirectional parser from Satta & Stock (1994).
"""

from collections import deque
from dataclasses import dataclass, field

from .grammar import Grammar
from .hcover import HCover, HItem, PartialItem, CompleteItem


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

    def __post_init__(self):
        self.hcover = HCover(self.grammar)

    def _reset(self):
        """Reset the recognizer state."""
        self._T = {}
        self._agenda = deque()

    def _add_to_T(self, i: int, j: int, item: HItem) -> bool:
        """Add an item to T[i,j]. Returns True if it was new."""
        key = (i, j)
        if key not in self._T:
            self._T[key] = set()
        if item not in self._T[key]:
            self._T[key].add(item)
            return True
        return False

    def _add_to_agenda(self, i: int, j: int, item: HItem):
        """Add an item to the agenda if it's new in T."""
        if self._add_to_T(i, j, item):
            self._agenda.append((i, j, item))
            if self.debug:
                print(f"  Added: T[{i},{j}] += {item}")

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

        for i, token in enumerate(tokens):
            if self.debug:
                print(f"Position {i}: terminal '{token}'")

            # Get projections where this terminal is the head
            for proj in self.hcover.get_projections(token):
                # Create initial partial item (just the head)
                initial = self.hcover.initial_item(proj.prod_idx)
                self._add_to_agenda(i, i + 1, initial)

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
        # Check for completion first
        comp = self.hcover.get_completion(item)
        if comp is not None:
            self._add_to_agenda(i, j, comp.result)

        # Left expansion
        for exp in self.hcover.get_left_expansions(item):
            symbol = exp.symbol
            new_item = exp.result

            if self.grammar.is_terminal(symbol):
                # Terminal: check if token at i-1 matches
                if i > 0 and self._tokens[i - 1] == symbol:
                    self._add_to_agenda(i - 1, j, new_item)
            else:
                # Nonterminal: look for I_symbol in T[k, i]
                target = CompleteItem(symbol)
                for k in range(i):
                    if target in self._T.get((k, i), set()):
                        self._add_to_agenda(k, j, new_item)

        # Right expansion
        for exp in self.hcover.get_right_expansions(item):
            symbol = exp.symbol
            new_item = exp.result

            if self.grammar.is_terminal(symbol):
                # Terminal: check if token at j matches
                if j < self._n and self._tokens[j] == symbol:
                    self._add_to_agenda(i, j + 1, new_item)
            else:
                # Nonterminal: look for I_symbol in T[j, k]
                target = CompleteItem(symbol)
                for k in range(j + 1, self._n + 1):
                    if target in self._T.get((j, k), set()):
                        self._add_to_agenda(i, k, new_item)

    def _process_complete(self, i: int, j: int, item: CompleteItem):
        """Process a complete item, triggering waiting expansions."""
        symbol = item.symbol

        # Project: this nonterminal might be a head for other productions
        for proj in self.hcover.get_projections(symbol):
            initial = self.hcover.initial_item(proj.prod_idx)
            self._add_to_agenda(i, j, initial)

        # Trigger waiting left expansions: items at [j, k] needing symbol on left
        for k in range(j + 1, self._n + 1):
            for other in list(self._T.get((j, k), set())):
                if isinstance(other, PartialItem):
                    for exp in self.hcover.get_left_expansions(other):
                        if exp.symbol == symbol:
                            self._add_to_agenda(i, k, exp.result)

        # Trigger waiting right expansions: items at [k, i] needing symbol on right
        for k in range(i):
            for other in list(self._T.get((k, i), set())):
                if isinstance(other, PartialItem):
                    for exp in self.hcover.get_right_expansions(other):
                        if exp.symbol == symbol:
                            self._add_to_agenda(k, j, exp.result)

    @property
    def T(self) -> dict[tuple[int, int], set[HItem]]:
        """Access the recognition matrix (for inspection after recognition)."""
        return self._T
