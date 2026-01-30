"""Tests for the head-driven tabular recognizer."""

import pytest

from algorithm7.grammar import Grammar, Production
from algorithm7.hcover import HCover, PartialItem, CompleteItem
from algorithm7.recognizer import Recognizer


class TestProduction:
    def test_basic_production(self):
        prod = Production("S", ("NP", "VP"), head_pos=2)
        assert prod.lhs == "S"
        assert prod.rhs == ("NP", "VP")
        assert prod.head_pos == 2
        assert prod.head == "VP"

    def test_head_position_validation(self):
        with pytest.raises(ValueError):
            Production("S", ("NP", "VP"), head_pos=0)
        with pytest.raises(ValueError):
            Production("S", ("NP", "VP"), head_pos=3)

    def test_empty_rhs_validation(self):
        with pytest.raises(ValueError):
            Production("S", (), head_pos=1)


class TestGrammar:
    def test_add_production(self):
        g = Grammar()
        idx = g.add_production("S", ("NP", "VP"), head_pos=2)
        assert idx == 0
        assert len(g.productions) == 1
        assert "S" in g.nonterminals
        # RHS symbols are terminals unless they appear as LHS in some production
        assert "NP" in g.terminals
        assert "VP" in g.terminals

        g.add_production("NP", ("n",), head_pos=1)
        g.add_production("VP", ("v",), head_pos=1)
        assert "NP" in g.nonterminals
        assert "VP" in g.nonterminals

    def test_from_string(self):
        text = """
        S -> NP [VP]
        VP -> cl [v] NP
        NP -> [det] n
        """
        g = Grammar.from_string(text)
        assert len(g.productions) == 3
        assert g.productions[0].head == "VP"
        assert g.productions[1].head == "v"
        assert g.productions[2].head == "det"

    def test_from_string_default_head(self):
        text = "S -> a b"
        g = Grammar.from_string(text)
        assert g.productions[0].head_pos == 1
        assert g.productions[0].head == "a"

    def test_terminals_nonterminals(self):
        text = """
        S -> [a] B
        B -> [c]
        """
        g = Grammar.from_string(text)
        assert "a" in g.terminals
        assert "c" in g.terminals
        assert "S" in g.nonterminals
        assert "B" in g.nonterminals

    def test_lowercase_nonterminal(self):
        text = "s -> [a]"
        g = Grammar.from_string(text, start="s")
        assert "s" in g.nonterminals
        assert "a" in g.terminals


class TestHCover:
    @pytest.fixture
    def simple_grammar(self):
        text = """
        S -> [a] b
        """
        return Grammar.from_string(text)

    @pytest.fixture
    def paper_grammar(self):
        """Grammar G_cl from the paper."""
        text = """
        S -> NP [VP]
        VP -> cl [v] NP
        NP -> [det] n
        """
        return Grammar.from_string(text)

    def test_projections(self, simple_grammar):
        hc = HCover(simple_grammar)
        # 'a' is the head of production 0
        projs = hc.get_projections("a")
        assert len(projs) == 1
        assert projs[0].prod_idx == 0

    def test_initial_item(self, simple_grammar):
        hc = HCover(simple_grammar)
        # Production 0: S -> [a] b, head at position 1
        item = hc.initial_item(0)
        assert item.prod_idx == 0
        assert item.s == 0
        assert item.t == 1

    def test_left_expansions(self, paper_grammar):
        hc = HCover(paper_grammar)
        # Production 1: VP -> cl [v] NP, head at position 2
        # Initial item: I_1^(1,2)
        initial = hc.initial_item(1)
        assert initial.s == 1
        assert initial.t == 2

        # Should have left expansion to get 'cl'
        left_exps = hc.get_left_expansions(initial)
        assert len(left_exps) == 1
        assert left_exps[0].symbol == "cl"
        assert left_exps[0].result == PartialItem(1, 0, 2)

    def test_right_expansions(self, paper_grammar):
        hc = HCover(paper_grammar)
        # Production 1: VP -> cl [v] NP, head at position 2
        initial = hc.initial_item(1)

        # Should have right expansion to get NP
        right_exps = hc.get_right_expansions(initial)
        assert len(right_exps) == 1
        assert right_exps[0].symbol == "NP"
        assert right_exps[0].result == PartialItem(1, 1, 3)

    def test_completion(self, paper_grammar):
        hc = HCover(paper_grammar)
        # Production 2: NP -> [det] n (2 symbols, head at 1)
        # Completion via right expansion from I_2^(0,1) with symbol 'n'
        head_item = PartialItem(2, 0, 1)
        right_exps = hc.get_right_expansions(head_item)
        assert len(right_exps) == 1
        assert right_exps[0].symbol == "n"
        assert right_exps[0].result == CompleteItem("NP")


class TestRecognizer:
    @pytest.fixture
    def paper_grammar(self):
        """Grammar G_cl from the paper."""
        text = """
        S -> NP [VP]
        VP -> cl [v] NP
        NP -> [det] n
        """
        return Grammar.from_string(text)

    @pytest.fixture
    def simple_grammar(self):
        """A very simple grammar: S -> a"""
        text = "S -> [a]"
        return Grammar.from_string(text)

    @pytest.fixture
    def ab_grammar(self):
        """Grammar: S -> a b"""
        text = "S -> [a] b"
        return Grammar.from_string(text)

    def test_single_terminal(self, simple_grammar):
        rec = Recognizer(grammar=simple_grammar)
        assert rec.recognize(["a"]) is True
        assert rec.recognize(["b"]) is False
        assert rec.recognize(["a", "a"]) is False

    def test_two_terminals(self, ab_grammar):
        rec = Recognizer(grammar=ab_grammar)
        assert rec.recognize(["a", "b"]) is True
        assert rec.recognize(["a"]) is False
        assert rec.recognize(["b"]) is False
        assert rec.recognize(["b", "a"]) is False

    def test_paper_grammar_accept(self, paper_grammar):
        """Test the example from the paper: det n v det n"""
        rec = Recognizer(grammar=paper_grammar)
        # This should be accepted: det n v det n
        # Parses as: [det n] [v [det n]] -> NP VP -> S
        # But wait, the grammar has VP -> cl v NP, so we need 'cl'
        # Let's test: det n cl v det n
        assert rec.recognize(["det", "n", "cl", "v", "det", "n"]) is True

    def test_paper_grammar_reject(self, paper_grammar):
        rec = Recognizer(grammar=paper_grammar)
        # Missing 'cl'
        assert rec.recognize(["det", "n", "v", "det", "n"]) is False
        # Wrong order
        assert rec.recognize(["det", "det", "n", "cl", "v", "n"]) is False
        # Empty
        assert rec.recognize([]) is False

    def test_recursive_grammar(self):
        """Test a grammar with recursion: S -> a S b | c"""
        text = """
        S -> a [S] b
        S -> [c]
        """
        g = Grammar.from_string(text)
        rec = Recognizer(grammar=g)

        # c
        assert rec.recognize(["c"]) is True
        # a c b
        assert rec.recognize(["a", "c", "b"]) is True
        # a a c b b
        assert rec.recognize(["a", "a", "c", "b", "b"]) is True
        # unbalanced
        assert rec.recognize(["a", "c"]) is False
        assert rec.recognize(["a", "a", "c", "b"]) is False

    def test_ambiguous_grammar(self):
        """Test an ambiguous grammar."""
        text = """
        S -> S [plus] S
        S -> [a]
        """
        g = Grammar.from_string(text)
        rec = Recognizer(grammar=g)

        assert rec.recognize(["a"]) is True
        assert rec.recognize(["a", "plus", "a"]) is True
        assert rec.recognize(["a", "plus", "a", "plus", "a"]) is True
        assert rec.recognize(["plus"]) is False

    def test_debug_mode(self, simple_grammar, capsys):
        rec = Recognizer(grammar=simple_grammar, debug=True)
        rec.recognize(["a"])
        captured = capsys.readouterr()
        assert "Recognizing" in captured.out
        assert "INIT STEP" in captured.out
        assert "RESULT" in captured.out


class TestIntegration:
    def test_arithmetic_expression_grammar(self):
        """Test a more complex arithmetic expression grammar."""
        text = """
        E -> E [plus] T
        E -> [T]
        T -> T [times] F
        T -> [F]
        F -> lparen [E] rparen
        F -> [id]
        """
        g = Grammar.from_string(text, start="E")
        rec = Recognizer(grammar=g)

        # id
        assert rec.recognize(["id"]) is True
        # id + id
        assert rec.recognize(["id", "plus", "id"]) is True
        # id * id
        assert rec.recognize(["id", "times", "id"]) is True
        # id + id * id
        assert rec.recognize(["id", "plus", "id", "times", "id"]) is True
        # (id)
        assert rec.recognize(["lparen", "id", "rparen"]) is True
        # (id + id)
        assert rec.recognize(["lparen", "id", "plus", "id", "rparen"]) is True
        # Reject: unbalanced parens
        assert rec.recognize(["lparen", "id"]) is False
        # Reject: missing operand
        assert rec.recognize(["id", "plus"]) is False
