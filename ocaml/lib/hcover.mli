(** H-cover construction for head-driven parsing.

    Implements Definitions 4 and 5 from Satta & Stock (1994).

    An h-cover transforms a CFG G into G_H with:
    - H-items as nonterminals
    - Projection productions P_H^(1): I_D or I_r^(τ-1,τ) -> X_H
    - Expansion productions P_H^(2): partial item extensions
*)

(** Partial h-item I_r^(s,t).

    Represents partial recognition of production r,
    having processed symbols from boundary s to t (0-indexed, inclusive).
*)
type partial_item = {
  prod_idx : int;  (** Production index r *)
  s : int;         (** Left boundary (0-indexed) *)
  t : int;         (** Right boundary (0-indexed) *)
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
  lhs : hitem;              (** I_D or I_r^(τ-1,τ) for n_r>1 *)
  head : Grammar.symbol;    (** X_H (the head symbol) *)
  proj_prod_idx : int;      (** Which production this projects from *)
}

(** Left-expansion production: I_r^(s-1,t) -> X_{s-1} I_r^(s,t)

    Extends a partial item leftward.
*)
type left_expand_prod = {
  left_result : hitem;          (** I_r^(s-1,t) or I_D *)
  left_symbol : Grammar.symbol; (** X_{s-1} *)
  left_source : partial_item;   (** I_r^(s,t) *)
}

(** Right-expansion production: I_r^(s,t+1) -> I_r^(s,t) X_{t+1}

    Extends a partial item rightward.
*)
type right_expand_prod = {
  right_result : hitem;          (** I_r^(s,t+1) or I_D *)
  right_source : partial_item;   (** I_r^(s,t) *)
  right_symbol : Grammar.symbol; (** X_{t+1} *)
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

(** Verbose pretty printer with explanations.
    Shows source productions and explains what each rule means. *)
val pp_explain : Format.formatter -> t -> unit
