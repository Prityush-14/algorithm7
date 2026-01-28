(** Algorithm 7: Head-driven tabular recognizer. *)

type config = {
  debug : bool;
}

let default_config = { debug = false }

(* Module for h-item sets *)
module HItemSet = Set.Make(struct
  type t = Hcover.hitem
  let compare = Hcover.compare_hitem
end)

(* Module for span keys (i, j) *)
module SpanKey = struct
  type t = int * int
  let compare (i1, j1) (i2, j2) =
    let c = Int.compare i1 i2 in
    if c <> 0 then c else Int.compare j1 j2
end

module SpanMap = Map.Make(SpanKey)

type t = {
  config : config;
  hcover : Hcover.t;
}

type state = {
  mutable matrix : HItemSet.t SpanMap.t;
  agenda : (int * int * Hcover.hitem) Queue.t;
  tokens : string array;
  n : int;
}

let create ?(config = default_config) grammar =
  let hcover = Hcover.create grammar in
  { config; hcover }

let hcover t = t.hcover

let add_to_matrix state i j item =
  let key = (i, j) in
  let existing = SpanMap.find_opt key state.matrix |> Option.value ~default:HItemSet.empty in
  if not (HItemSet.mem item existing) then begin
    state.matrix <- SpanMap.add key (HItemSet.add item existing) state.matrix;
    true
  end else
    false

let add_to_agenda state i j item =
  if add_to_matrix state i j item then
    Queue.add (i, j, item) state.agenda

let debug_print config fmt =
  if config.debug then Format.printf fmt
  else Format.ifprintf Format.std_formatter fmt

let process_partial t state i j (item : Hcover.partial_item) =
  let hcover = t.hcover in
  let grammar = Hcover.grammar hcover in

  (* Check for completion first *)
  (match Hcover.get_completion hcover item with
   | Some comp -> add_to_agenda state i j (Complete comp.comp_result)
   | None -> ());

  (* Left expansion *)
  List.iter (fun (exp : Hcover.left_expand_prod) ->
    let symbol = exp.left_symbol in
    let new_item = exp.left_result in

    if Grammar.is_terminal grammar symbol then begin
      (* Terminal: check if token at i-1 matches *)
      if i > 0 && state.tokens.(i - 1) = symbol then
        add_to_agenda state (i - 1) j (Partial new_item)
    end else begin
      (* Nonterminal: look for I_symbol in T[k, i] for all k < i *)
      let target = Hcover.Complete { symbol } in
      for k = 0 to i - 1 do
        let key = (k, i) in
        match SpanMap.find_opt key state.matrix with
        | Some items when HItemSet.mem target items ->
          add_to_agenda state k j (Partial new_item)
        | _ -> ()
      done
    end
  ) (Hcover.get_left_expansions hcover item);

  (* Right expansion *)
  List.iter (fun (exp : Hcover.right_expand_prod) ->
    let symbol = exp.right_symbol in
    let new_item = exp.right_result in

    if Grammar.is_terminal grammar symbol then begin
      (* Terminal: check if token at j matches *)
      if j < state.n && state.tokens.(j) = symbol then
        add_to_agenda state i (j + 1) (Partial new_item)
    end else begin
      (* Nonterminal: look for I_symbol in T[j, k] for all k > j *)
      let target = Hcover.Complete { symbol } in
      for k = j + 1 to state.n do
        let key = (j, k) in
        match SpanMap.find_opt key state.matrix with
        | Some items when HItemSet.mem target items ->
          add_to_agenda state i k (Partial new_item)
        | _ -> ()
      done
    end
  ) (Hcover.get_right_expansions hcover item)

let process_complete t state i j (item : Hcover.complete_item) =
  let hcover = t.hcover in
  let symbol = item.symbol in

  (* Project: this nonterminal might be a head for other productions *)
  List.iter (fun (proj : Hcover.projection_prod) ->
    let initial = Hcover.initial_item hcover proj.proj_prod_idx in
    add_to_agenda state i j (Partial initial)
  ) (Hcover.get_projections hcover symbol);

  (* Trigger waiting left expansions: items at [j, k] needing symbol on left *)
  for k = j + 1 to state.n do
    let key = (j, k) in
    match SpanMap.find_opt key state.matrix with
    | Some items ->
      HItemSet.iter (fun other ->
        match other with
        | Partial pitem ->
          List.iter (fun (exp : Hcover.left_expand_prod) ->
            if exp.left_symbol = symbol then
              add_to_agenda state i k (Partial exp.left_result)
          ) (Hcover.get_left_expansions hcover pitem)
        | Complete _ -> ()
      ) items
    | None -> ()
  done;

  (* Trigger waiting right expansions: items at [k, i] needing symbol on right *)
  for k = 0 to i - 1 do
    let key = (k, i) in
    match SpanMap.find_opt key state.matrix with
    | Some items ->
      HItemSet.iter (fun other ->
        match other with
        | Partial pitem ->
          List.iter (fun (exp : Hcover.right_expand_prod) ->
            if exp.right_symbol = symbol then
              add_to_agenda state k j (Partial exp.right_result)
          ) (Hcover.get_right_expansions hcover pitem)
        | Complete _ -> ()
      ) items
    | None -> ()
  done

let recognize t tokens =
  let tokens_arr = Array.of_list tokens in
  let n = Array.length tokens_arr in
  let hcover = t.hcover in

  let state = {
    matrix = SpanMap.empty;
    agenda = Queue.create ();
    tokens = tokens_arr;
    n;
  } in

  debug_print t.config "Recognizing: %s@." (String.concat " " tokens);
  debug_print t.config "Length n = %d@." n;

  (* Step 1: Initialize - scan terminals and start projections *)
  debug_print t.config "@.=== INIT STEP ===@.";

  Array.iteri (fun i token ->
    debug_print t.config "Position %d: terminal '%s'@." i token;
    (* Get projections where this terminal is the head *)
    List.iter (fun (proj : Hcover.projection_prod) ->
      let initial = Hcover.initial_item hcover proj.proj_prod_idx in
      add_to_agenda state i (i + 1) (Partial initial)
    ) (Hcover.get_projections hcover token)
  ) tokens_arr;

  (* Step 2: Process agenda *)
  debug_print t.config "@.=== MAIN LOOP ===@.";

  while not (Queue.is_empty state.agenda) do
    let (i, j, item) = Queue.pop state.agenda in
    debug_print t.config "@.Processing: T[%d,%d], %a@." i j Hcover.pp_hitem item;
    match item with
    | Partial pitem -> process_partial t state i j pitem
    | Complete citem -> process_complete t state i j citem
  done;

  (* Step 3: Accept check *)
  let start_symbol = Grammar.start (Hcover.grammar hcover) in
  let start_item = Hcover.Complete { symbol = start_symbol } in
  let accepted =
    match SpanMap.find_opt (0, n) state.matrix with
    | Some items -> HItemSet.mem start_item items
    | None -> false
  in

  debug_print t.config "@.=== RESULT ===@.";
  debug_print t.config "Looking for %a in T[0,%d]@." Hcover.pp_hitem start_item n;
  debug_print t.config "Accepted: %b@." accepted;

  accepted
