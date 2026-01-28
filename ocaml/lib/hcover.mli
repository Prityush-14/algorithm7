(** H-cover construction for head-driven parsing.

    Implements Definitions 4 and 5 from Satta & Stock (1994).

    An h-cover transforms a CFG G into G_H with:
    - H-items as nonterminals
    - Projection productions P_H^(1): I_D -> X_H (complete item from head)
    - Expansion productions P_H^(2): partial item extensions
*)

(** Partial h-item I_r^(s,t).

    Represents partial recognition of production r,
    having processed symbols from position s to t (1-indexed, inclusive).
*)
type partial_item = {
  prod_idx : int;  (** Production index r *)
  s : int;         (** Left boundary (1-indexed) *)
  t : int;         (** Right boundary (1-indexed) *)
}

(** Complete h-item I_A.

    Represents complete recognition of nonterminal A.
*)
type complete_item = {
  symbol : Grammar.symbol;
}

(** Union type for all h-items. *)
type hitem =
  | Partial of partial_item
  | Complete of complete_item

(** Projection production: I_D -> X_H

    where D is a nonterminal and X is its head.
*)
type projection_prod = {
  lhs : complete_item;      (** I_D *)
  head : Grammar.symbol;    (** X_H (the head symbol) *)
  proj_prod_idx : int;      (** Which production this projects from *)
}

(** Left-expansion production: I_r^(s-1,t) -> X_{s-1} I_r^(s,t)

    Extends a partial item leftward.
*)
type left_expand_prod = {
  left_result : partial_item;   (** I_r^(s-1,t) *)
  left_symbol : Grammar.symbol; (** X_{s-1} *)
  left_source : partial_item;   (** I_r^(s,t) *)
}

(** Right-expansion production: I_r^(s,t+1) -> I_r^(s,t) X_{t+1}

    Extends a partial item rightward.
*)
type right_expand_prod = {
  right_result : partial_item;   (** I_r^(s,t+1) *)
  right_source : partial_item;   (** I_r^(s,t) *)
  right_symbol : Grammar.symbol; (** X_{t+1} *)
}

(** Completion production: I_A -> I_r^(1,|alpha|)

    Completes a nonterminal when a partial item spans the full RHS.
*)
type complete_prod = {
  comp_result : complete_item;   (** I_A *)
  comp_source : partial_item;    (** I_r^(1,|alpha|) *)
  comp_prod_idx : int;           (** Production index *)
}

(** The h-cover of a grammar. *)
type t

(** Build the h-cover from a grammar. *)
val create : Grammar.t -> t

(** Get the underlying grammar. *)
val grammar : t -> Grammar.t

(** Get projection productions for a head symbol. *)
val get_projections : t -> Grammar.symbol -> projection_prod list

(** Get left-expansion productions for a partial item. *)
val get_left_expansions : t -> partial_item -> left_expand_prod list

(** Get right-expansion productions for a partial item. *)
val get_right_expansions : t -> partial_item -> right_expand_prod list

(** Get completion production for a partial item (if it spans full RHS). *)
val get_completion : t -> partial_item -> complete_prod option

(** Get initial partial item for a production (just the head). *)
val initial_item : t -> int -> partial_item

(** Comparison functions for use in Map/Set. *)
val compare_partial : partial_item -> partial_item -> int
val compare_complete : complete_item -> complete_item -> int
val compare_hitem : hitem -> hitem -> int

(** Pretty printers. *)
val pp_partial : Format.formatter -> partial_item -> unit
val pp_complete : Format.formatter -> complete_item -> unit
val pp_hitem : Format.formatter -> hitem -> unit
val pp : Format.formatter -> t -> unit
