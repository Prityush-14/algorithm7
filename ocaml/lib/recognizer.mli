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
