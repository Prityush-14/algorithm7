(** Grammar representation for head-driven parsing. *)

(** A grammar symbol. Nonterminals are all LHS symbols. *)
type symbol = string

(** A production with head annotation.

    - [lhs]: Left-hand side nonterminal
    - [rhs]: Right-hand side symbols (array for O(1) indexing)
    - [head_pos]: 1-indexed position of the head in rhs (tau_r in the paper);
      use 0 for epsilon productions
*)
type production = {
  lhs : symbol;
  rhs : symbol array;
  head_pos : int;
}

(** Get the head symbol of a production. *)
val head : production -> symbol

(** A context-free grammar with head annotations. *)
type t

(** Create an empty grammar with given start symbol (default "S"). *)
val create : ?start:symbol -> unit -> t

(** Add a production and return its index.
    @raise Invalid_argument if head_pos is out of range. *)
val add_production : t -> lhs:symbol -> rhs:symbol list -> head_pos:int -> int

(** Get the start symbol. *)
val start : t -> symbol

(** Get all productions as an array. *)
val productions : t -> production array

(** Get production by index.
    @raise Invalid_argument if index is out of range. *)
val get_production : t -> int -> production

(** Number of productions. *)
val num_productions : t -> int

(** Check if symbol is a terminal. *)
val is_terminal : t -> symbol -> bool

(** Check if symbol is a nonterminal. *)
val is_nonterminal : t -> symbol -> bool

(** Get all (index, production) pairs with given head symbol. *)
val productions_with_head : t -> symbol -> (int * production) list

(** Parse grammar from string representation.

    Format per line:
    {[
      LHS -> sym1 sym2 [head] sym3
    ]}

    The head symbol is marked with square brackets.
    If no head is marked, the first symbol is the head.
    Lines starting with # are comments.
    Epsilon productions can be written as `A -> ε`, `A -> eps`, `A -> epsilon`,
    or an empty RHS (`A ->`).

    Example:
    {[
      S -> NP [VP]
      VP -> cl [v] NP
      NP -> [det] n
    ]}

    @raise Failure if parsing fails. *)
val from_string : ?start:symbol -> string -> t

(** Pretty print a production. *)
val pp_production : Format.formatter -> production -> unit

(** Pretty print a grammar. *)
val pp : Format.formatter -> t -> unit

(** Compute nullable nonterminals (A =>* ε). *)
val nullable_nonterminals : t -> symbol list

(** Ensure a single start production.
    If multiple productions rewrite the start symbol, a fresh start
    symbol is introduced with a single production S' -> S. *)
val ensure_single_start : t -> t
