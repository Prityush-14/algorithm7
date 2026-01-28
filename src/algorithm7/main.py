"""CLI entry point for the head-driven recognizer."""

import argparse
import sys

from .grammar import Grammar
from .recognizer import Recognizer


# Example grammar from the paper (G_cl)
EXAMPLE_GRAMMAR = """
# Grammar G_cl from Satta & Stock (1994)
# S -> NP VP
# VP -> cl v NP  (head: v, position 2)
# NP -> det n    (head: det, position 1)

S -> NP [VP]
VP -> cl [v] NP
NP -> [det] n
"""


def main():
    parser = argparse.ArgumentParser(
        description="Head-driven tabular recognizer (Algorithm 7)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  algorithm7 --example "det n v det n"
  algorithm7 --grammar grammar.txt "det n v det n"
  algorithm7 --grammar grammar.txt --debug "det n v det n"

Grammar format (one production per line):
  S -> NP [VP]       # VP is the head
  VP -> cl [v] NP    # v is the head (position 2)
  NP -> [det] n      # det is the head (position 1)

Square brackets mark the head of each production.
If no head is marked, the first symbol is used.
        """
    )
    parser.add_argument(
        "input",
        nargs="?",
        help="Input string to recognize (space-separated tokens)"
    )
    parser.add_argument(
        "--grammar", "-g",
        type=str,
        help="Path to grammar file"
    )
    parser.add_argument(
        "--example", "-e",
        action="store_true",
        help="Use the example grammar from the paper"
    )
    parser.add_argument(
        "--show-grammar",
        action="store_true",
        help="Print the grammar and exit"
    )
    parser.add_argument(
        "--show-hcover",
        action="store_true",
        help="Print the h-cover and exit"
    )
    parser.add_argument(
        "--debug", "-d",
        action="store_true",
        help="Enable debug output"
    )

    args = parser.parse_args()

    # Load grammar
    if args.example:
        grammar = Grammar.from_string(EXAMPLE_GRAMMAR)
    elif args.grammar:
        with open(args.grammar) as f:
            grammar = Grammar.from_string(f.read())
    else:
        print("Error: Must specify --grammar or --example", file=sys.stderr)
        sys.exit(1)

    # Show grammar if requested
    if args.show_grammar:
        print(grammar)
        sys.exit(0)

    # Create recognizer
    recognizer = Recognizer(grammar=grammar, debug=args.debug)

    # Show h-cover if requested
    if args.show_hcover:
        print(recognizer.hcover)
        sys.exit(0)

    # Check for input
    if not args.input:
        print("Error: No input string provided", file=sys.stderr)
        sys.exit(1)

    # Parse input
    tokens = args.input.split()

    # Recognize
    result = recognizer.recognize(tokens)

    if result:
        print(f"ACCEPTED: '{args.input}' is in L(G)")
    else:
        print(f"REJECTED: '{args.input}' is not in L(G)")

    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
