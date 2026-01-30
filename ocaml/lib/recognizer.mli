(** Algorithm 7: Head-driven tabular recognizer.

    Implementation of the head-driven bidirectional parser from Satta & Stock (1994).
*)

(** Configuration for the recognizer. *)
type config = {
  debug : bool;  (** Enable debug output *)
}

(** Default configuration (debug = false). *)
val default_config : config

(** The recognizer. *)
type t

(** Create a recognizer for a grammar. *)
val create : ?config:config -> Grammar.t -> t

(** Recognize whether a token sequence is in the language.

    @param tokens List of terminal symbols
    @return true if the string is accepted, false otherwise *)
val recognize : t -> string list -> bool

(** Get the h-cover used by this recognizer. *)
val hcover : t -> Hcover.t

(** Subset of H-cover rules that were actually used during recognition. *)
type used_hcover

(** Get the H-cover rules that were used during the last recognition.
    Returns only the rules that contributed to the recognition. *)
val get_used_hcover : t -> used_hcover

(** Format the used H-cover for display.
    @param explain If true, show verbose explanations *)
val format_used_hcover : ?explain:bool -> Grammar.t -> used_hcover -> string

(** Pretty print the used H-cover. *)
val pp_used_hcover : Format.formatter -> used_hcover -> unit

(** Pretty print the used H-cover with verbose explanations. *)
val pp_used_hcover_explain : Grammar.t -> Format.formatter -> used_hcover -> unit

(** A step in the derivation tree. *)
type derivation_step

(** Get the derivation tree for the accepted sentence.
    Returns None if the sentence was not accepted. *)
val get_derivation : t -> derivation_step option

(** Format the derivation tree as a string. *)
val format_derivation : string list -> derivation_step -> string

(** Pretty print the derivation tree. *)
val pp_derivation : string list -> Format.formatter -> derivation_step -> unit
