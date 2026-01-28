(** CLI entry point for the head-driven recognizer. *)

open Algorithm7

(* Example grammar from the paper (G_cl) *)
let example_grammar = {|
# Grammar G_cl from Satta & Stock (1994)
# S -> NP VP
# VP -> cl v NP  (head: v, position 2)
# NP -> det n    (head: det, position 1)

S -> NP [VP]
VP -> cl [v] NP
NP -> [det] n
|}

let usage () =
  Printf.eprintf {|Usage: algorithm7 [OPTIONS] INPUT

Head-driven tabular recognizer (Algorithm 7)

Options:
  -g, --grammar FILE    Path to grammar file
  -e, --example         Use the example grammar from the paper
  --show-grammar        Print the grammar and exit
  --show-hcover         Print the h-cover and exit
  -d, --debug           Enable debug output
  -h, --help            Show this help

Example:
  algorithm7 --example "det n cl v det n"
  algorithm7 --grammar grammar.txt "det n cl v det n"
|};
  exit 1

type options = {
  mutable grammar_file : string option;
  mutable use_example : bool;
  mutable show_grammar : bool;
  mutable show_hcover : bool;
  mutable debug : bool;
  mutable input : string option;
}

let parse_args () =
  let opts = {
    grammar_file = None;
    use_example = false;
    show_grammar = false;
    show_hcover = false;
    debug = false;
    input = None;
  } in
  let args = Array.to_list Sys.argv |> List.tl in
  let rec parse = function
    | [] -> ()
    | ("-h" | "--help") :: _ -> usage ()
    | ("-g" | "--grammar") :: file :: rest ->
      opts.grammar_file <- Some file;
      parse rest
    | ("-e" | "--example") :: rest ->
      opts.use_example <- true;
      parse rest
    | "--show-grammar" :: rest ->
      opts.show_grammar <- true;
      parse rest
    | "--show-hcover" :: rest ->
      opts.show_hcover <- true;
      parse rest
    | ("-d" | "--debug") :: rest ->
      opts.debug <- true;
      parse rest
    | arg :: _rest when String.length arg > 0 && arg.[0] = '-' ->
      Printf.eprintf "Unknown option: %s\n" arg;
      usage ()
    | arg :: rest ->
      opts.input <- Some arg;
      parse rest
  in
  parse args;
  opts

let () =
  let opts = parse_args () in

  (* Load grammar *)
  let grammar =
    if opts.use_example then
      Grammar.from_string example_grammar
    else match opts.grammar_file with
      | Some path ->
        let ic = open_in path in
        let content = really_input_string ic (in_channel_length ic) in
        close_in ic;
        Grammar.from_string content
      | None ->
        Printf.eprintf "Error: Must specify --grammar or --example\n";
        exit 1
  in

  (* Show grammar if requested *)
  if opts.show_grammar then begin
    Format.printf "%a@." Grammar.pp grammar;
    exit 0
  end;

  (* Create recognizer *)
  let config = Recognizer.{ debug = opts.debug } in
  let recognizer = Recognizer.create ~config grammar in

  (* Show h-cover if requested *)
  if opts.show_hcover then begin
    Format.printf "%a@." Hcover.pp (Recognizer.hcover recognizer);
    exit 0
  end;

  (* Check for input *)
  match opts.input with
  | None ->
    Printf.eprintf "Error: No input string provided\n";
    exit 1
  | Some input_str ->
    (* Parse input *)
    let tokens = String.split_on_char ' ' input_str
                 |> List.filter (fun s -> s <> "") in

    (* Recognize *)
    let result = Recognizer.recognize recognizer tokens in

    if result then begin
      Printf.printf "ACCEPTED: '%s' is in L(G)\n" input_str;
      exit 0
    end else begin
      Printf.printf "REJECTED: '%s' is not in L(G)\n" input_str;
      exit 1
    end
