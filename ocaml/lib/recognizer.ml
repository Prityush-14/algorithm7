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

module PartialSet = Set.Make(struct
  type t = Hcover.partial_item
  let compare = Hcover.compare_partial
end)

(* Modules for tracking used rules *)
module ProjectionSet = Set.Make(struct
  type t = Hcover.projection_prod
  let compare a b =
    let c = Int.compare a.Hcover.proj_prod_idx b.Hcover.proj_prod_idx in
    if c <> 0 then c else String.compare a.Hcover.head b.Hcover.head
end)

module LeftExpandSet = Set.Make(struct
  type t = Hcover.left_expand_prod
  let compare_symbol_opt a b =
    match a, b with
    | None, None -> 0
    | None, Some _ -> -1
    | Some _, None -> 1
    | Some sa, Some sb -> String.compare sa sb
  let compare a b =
    let c = Hcover.compare_partial a.Hcover.left_source b.Hcover.left_source in
    if c <> 0 then c else
    let c = Hcover.compare_hitem a.Hcover.left_result b.Hcover.left_result in
    if c <> 0 then c else
    compare_symbol_opt a.Hcover.left_symbol b.Hcover.left_symbol
end)

module RightExpandSet = Set.Make(struct
  type t = Hcover.right_expand_prod
  let compare_symbol_opt a b =
    match a, b with
    | None, None -> 0
    | None, Some _ -> -1
    | Some _, None -> 1
    | Some sa, Some sb -> String.compare sa sb
  let compare a b =
    let c = Hcover.compare_partial a.Hcover.right_source b.Hcover.right_source in
    if c <> 0 then c else
    let c = Hcover.compare_hitem a.Hcover.right_result b.Hcover.right_result in
    if c <> 0 then c else
    compare_symbol_opt a.Hcover.right_symbol b.Hcover.right_symbol
end)

type used_hcover = {
  used_projections : ProjectionSet.t;
  used_left_expansions : LeftExpandSet.t;
  used_right_expansions : RightExpandSet.t;
}

(* Derivation tracking *)
type rule_kind =
  | RuleProjection of Hcover.projection_prod
  | RuleLeftExpand of Hcover.left_expand_prod
  | RuleRightExpand of Hcover.right_expand_prod

type derivation_step = {
  deriv_item : Hcover.hitem;
  deriv_span : int * int;
  deriv_rule : rule_kind option;
  deriv_children : derivation_step list;
  deriv_terminal : string option;
}

(* Key for derivation map: (i, j, item) *)
module DerivKey = struct
  type t = int * int * Hcover.hitem
  let compare (i1, j1, item1) (i2, j2, item2) =
    let c = Int.compare i1 i2 in
    if c <> 0 then c else
    let c = Int.compare j1 j2 in
    if c <> 0 then c else
    Hcover.compare_hitem item1 item2
end

module DerivMap = Map.Make(DerivKey)

type t = {
  config : config;
  hcover : Hcover.t;
  mutable last_used : used_hcover;
  mutable last_derivations : derivation_step DerivMap.t;
  mutable last_n : int;
}

type state = {
  mutable matrix : HItemSet.t SpanMap.t;
  agenda : (int * int * Hcover.hitem) Queue.t;
  tokens : string array;
  n : int;
  mutable q_left : PartialSet.t SpanMap.t;
  mutable q_right : PartialSet.t SpanMap.t;
  (* Tracking *)
  mutable used_projections : ProjectionSet.t;
  mutable used_left_expansions : LeftExpandSet.t;
  mutable used_right_expansions : RightExpandSet.t;
  (* Derivation tracking *)
  mutable derivations : derivation_step DerivMap.t;
}

let empty_used = {
  used_projections = ProjectionSet.empty;
  used_left_expansions = LeftExpandSet.empty;
  used_right_expansions = RightExpandSet.empty;
}

let create ?(config = default_config) grammar =
  let grammar = Grammar.ensure_single_start grammar in
  let hcover = Hcover.create grammar in
  { config; hcover; last_used = empty_used; last_derivations = DerivMap.empty; last_n = 0 }

let hcover t = t.hcover

let get_used_hcover t = t.last_used

let add_to_matrix state i j item =
  let key = (i, j) in
  let existing = SpanMap.find_opt key state.matrix |> Option.value ~default:HItemSet.empty in
  if not (HItemSet.mem item existing) then begin
    state.matrix <- SpanMap.add key (HItemSet.add item existing) state.matrix;
    true
  end else
    false

let q_mem qmap key item =
  match SpanMap.find_opt key qmap with
  | Some set -> PartialSet.mem item set
  | None -> false

let q_add qmap key item =
  let existing = SpanMap.find_opt key qmap |> Option.value ~default:PartialSet.empty in
  SpanMap.add key (PartialSet.add item existing) qmap

(* Helper to record derivation (first derivation only) *)
let record_derivation state i j item ~rule ~children ~terminal =
  let key = (i, j, item) in
  if not (DerivMap.mem key state.derivations) then begin
    let child_steps = List.filter_map (fun (ci, cj, citem) ->
      DerivMap.find_opt (ci, cj, citem) state.derivations
    ) children in
    let step = {
      deriv_item = item;
      deriv_span = (i, j);
      deriv_rule = rule;
      deriv_children = child_steps;
      deriv_terminal = terminal;
    } in
    state.derivations <- DerivMap.add key step state.derivations
  end

let debug_print config fmt =
  if config.debug then Format.printf fmt
  else Format.ifprintf Format.std_formatter fmt

let process_partial t state i j (item : Hcover.partial_item) =
  let hcover = t.hcover in
  let grammar = Hcover.grammar hcover in

  (* Left expansion *)
  if not (q_mem state.q_left (i, j) item) then
    List.iter (fun (exp : Hcover.left_expand_prod) ->
      let symbol = exp.left_symbol in
      let new_item = exp.left_result in

      match symbol with
      | None ->
        if add_to_matrix state i j new_item then begin
          Queue.add (i, j, new_item) state.agenda;
          state.used_left_expansions <- LeftExpandSet.add exp state.used_left_expansions;
          record_derivation state i j new_item
            ~rule:(Some (RuleLeftExpand exp))
            ~children:[(i, j, Hcover.Partial item)]
            ~terminal:(Some "ε");
          state.q_right <- q_add state.q_right (i, j) item
        end
      | Some symbol ->
        if Grammar.is_terminal grammar symbol then begin
          (* Terminal: check if token at i-1 matches *)
          if i > 0 && state.tokens.(i - 1) = symbol then
            if add_to_matrix state (i - 1) j new_item then begin
              Queue.add (i - 1, j, new_item) state.agenda;
              state.used_left_expansions <- LeftExpandSet.add exp state.used_left_expansions;
              record_derivation state (i - 1) j new_item
                ~rule:(Some (RuleLeftExpand exp))
                ~children:[(i, j, Hcover.Partial item)]
                ~terminal:(Some symbol);
              state.q_right <- q_add state.q_right (i, j) item
            end
        end else begin
          (* Nonterminal: look for I_symbol in T[k, i] for all k < i *)
          let target = Hcover.Complete { symbol } in
          for k = 0 to i - 1 do
            let key = (k, i) in
            match SpanMap.find_opt key state.matrix with
            | Some items when HItemSet.mem target items ->
              if add_to_matrix state k j new_item then begin
                Queue.add (k, j, new_item) state.agenda;
                state.used_left_expansions <- LeftExpandSet.add exp state.used_left_expansions;
                record_derivation state k j new_item
                  ~rule:(Some (RuleLeftExpand exp))
                  ~children:[(k, i, target); (i, j, Hcover.Partial item)]
                  ~terminal:None;
                state.q_right <- q_add state.q_right (i, j) item
              end
            | _ -> ()
          done
        end
    ) (Hcover.get_left_expansions hcover item);

  (* Right expansion *)
  if not (q_mem state.q_right (i, j) item) then
    List.iter (fun (exp : Hcover.right_expand_prod) ->
      let symbol = exp.right_symbol in
      let new_item = exp.right_result in

      match symbol with
      | None ->
        if add_to_matrix state i j new_item then begin
          Queue.add (i, j, new_item) state.agenda;
          state.used_right_expansions <- RightExpandSet.add exp state.used_right_expansions;
          record_derivation state i j new_item
            ~rule:(Some (RuleRightExpand exp))
            ~children:[(i, j, Hcover.Partial item)]
            ~terminal:(Some "ε");
          state.q_left <- q_add state.q_left (i, j) item
        end
      | Some symbol ->
        if Grammar.is_terminal grammar symbol then begin
          (* Terminal: check if token at j matches *)
          if j < state.n && state.tokens.(j) = symbol then
            if add_to_matrix state i (j + 1) new_item then begin
              Queue.add (i, j + 1, new_item) state.agenda;
              state.used_right_expansions <- RightExpandSet.add exp state.used_right_expansions;
              record_derivation state i (j + 1) new_item
                ~rule:(Some (RuleRightExpand exp))
                ~children:[(i, j, Hcover.Partial item)]
                ~terminal:(Some symbol);
              state.q_left <- q_add state.q_left (i, j) item
            end
        end else begin
          (* Nonterminal: look for I_symbol in T[j, k] for all k > j *)
          let target = Hcover.Complete { symbol } in
          for k = j + 1 to state.n do
            let key = (j, k) in
            match SpanMap.find_opt key state.matrix with
            | Some items when HItemSet.mem target items ->
              if add_to_matrix state i k new_item then begin
                Queue.add (i, k, new_item) state.agenda;
                state.used_right_expansions <- RightExpandSet.add exp state.used_right_expansions;
                record_derivation state i k new_item
                  ~rule:(Some (RuleRightExpand exp))
                  ~children:[(i, j, Hcover.Partial item); (j, k, target)]
                  ~terminal:None;
                state.q_left <- q_add state.q_left (i, j) item
              end
            | _ -> ()
          done
        end
    ) (Hcover.get_right_expansions hcover item)

let process_complete t state i j (item : Hcover.complete_item) =
  let hcover = t.hcover in
  let symbol = item.symbol in

  (* Project: this nonterminal might be a head for other productions *)
  List.iter (fun (proj : Hcover.projection_prod) ->
    let proj_item = proj.Hcover.lhs in
    if add_to_matrix state i j proj_item then begin
      Queue.add (i, j, proj_item) state.agenda;
      state.used_projections <- ProjectionSet.add proj state.used_projections;
      record_derivation state i j proj_item
        ~rule:(Some (RuleProjection proj))
        ~children:[(i, j, Hcover.Complete item)]
        ~terminal:None
    end
  ) (Hcover.get_projections hcover symbol);

  (* Trigger waiting left expansions: items at [j, k] needing symbol on left *)
  for k = j + 1 to state.n do
    let key = (j, k) in
    match SpanMap.find_opt key state.matrix with
    | Some items ->
      HItemSet.iter (fun other ->
        match other with
        | Partial pitem ->
          if q_mem state.q_left (j, k) pitem then () else
          List.iter (fun (exp : Hcover.left_expand_prod) ->
            if exp.left_symbol = Some symbol then
              if add_to_matrix state i k exp.left_result then begin
                Queue.add (i, k, exp.left_result) state.agenda;
                state.used_left_expansions <- LeftExpandSet.add exp state.used_left_expansions;
                record_derivation state i k exp.left_result
                  ~rule:(Some (RuleLeftExpand exp))
                  ~children:[(i, j, Hcover.Complete item); (j, k, other)]
                  ~terminal:None;
                state.q_right <- q_add state.q_right (j, k) pitem
              end
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
          if q_mem state.q_right (k, i) pitem then () else
          List.iter (fun (exp : Hcover.right_expand_prod) ->
            if exp.right_symbol = Some symbol then
              if add_to_matrix state k j exp.right_result then begin
                Queue.add (k, j, exp.right_result) state.agenda;
                state.used_right_expansions <- RightExpandSet.add exp state.used_right_expansions;
                record_derivation state k j exp.right_result
                  ~rule:(Some (RuleRightExpand exp))
                  ~children:[(k, i, other); (i, j, Hcover.Complete item)]
                  ~terminal:None;
                state.q_left <- q_add state.q_left (k, i) pitem
              end
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
    q_left = SpanMap.empty;
    q_right = SpanMap.empty;
    used_projections = ProjectionSet.empty;
    used_left_expansions = LeftExpandSet.empty;
    used_right_expansions = RightExpandSet.empty;
    derivations = DerivMap.empty;
  } in

  debug_print t.config "Recognizing: %s@." (String.concat " " tokens);
  debug_print t.config "Length n = %d@." n;

  (* Step 1: Initialize - scan terminals and start projections *)
  debug_print t.config "@.=== INIT STEP ===@.";

  let nullables = Grammar.nullable_nonterminals (Hcover.grammar hcover) in
  List.iter (fun sym ->
    for i = 0 to n do
      let item = Hcover.Complete { symbol = sym } in
      if add_to_matrix state i i item then begin
        Queue.add (i, i, item) state.agenda;
        record_derivation state i i item ~rule:None ~children:[] ~terminal:(Some "ε")
      end
    done
  ) nullables;

  Array.iteri (fun i token ->
    debug_print t.config "Position %d: terminal '%s'@." i token;
    (* Get projections where this terminal is the head *)
    List.iter (fun (proj : Hcover.projection_prod) ->
      let proj_item = proj.Hcover.lhs in
      if add_to_matrix state i (i + 1) proj_item then begin
        Queue.add (i, i + 1, proj_item) state.agenda;
        state.used_projections <- ProjectionSet.add proj state.used_projections;
        record_derivation state i (i + 1) proj_item
          ~rule:(Some (RuleProjection proj)) ~children:[] ~terminal:(Some token)
      end
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

  (* Store the used rules and derivations *)
  t.last_used <- {
    used_projections = state.used_projections;
    used_left_expansions = state.used_left_expansions;
    used_right_expansions = state.used_right_expansions;
  };
  t.last_derivations <- state.derivations;
  t.last_n <- n;

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

(* Formatting functions for used_hcover *)

let pp_used_hcover fmt (used : used_hcover) =
  Format.fprintf fmt "Used HCover Rules:@.";
  Format.fprintf fmt "  Projections:@.";
  ProjectionSet.iter (fun p ->
    Format.fprintf fmt "    %a -> %s_H (prod %d)@."
      Hcover.pp_hitem p.lhs p.head p.proj_prod_idx
  ) used.used_projections;
  Format.fprintf fmt "  Left Expansions:@.";
  LeftExpandSet.iter (fun e ->
    Format.fprintf fmt "    %a -> %a %a@."
      Hcover.pp_hitem e.left_result Hcover.pp_symbol_opt e.left_symbol Hcover.pp_partial e.left_source
  ) used.used_left_expansions;
  Format.fprintf fmt "  Right Expansions:@.";
  RightExpandSet.iter (fun e ->
    Format.fprintf fmt "    %a -> %a %a@."
      Hcover.pp_hitem e.right_result Hcover.pp_partial e.right_source Hcover.pp_symbol_opt e.right_symbol
  ) used.used_right_expansions

let pp_used_hcover_explain grammar fmt (used : used_hcover) =
  let prods = Grammar.productions grammar in
  Format.fprintf fmt "Used H-Cover Rules (only rules applied during recognition)@.";
  Format.fprintf fmt "============================================================@.";
  Format.fprintf fmt "@.";
  Format.fprintf fmt "Note: Boundary indices (s,t) follow Satta & Stock 1994@.";
  Format.fprintf fmt "@.";

  Format.fprintf fmt "Projections P_H^(1): I_D -> X_H@.";
  Format.fprintf fmt "----------------------------------------@.";
  ProjectionSet.iter (fun p ->
    let prod = prods.(p.proj_prod_idx) in
    Format.fprintf fmt "  %a -> %s_H@."
      Hcover.pp_hitem p.lhs p.head;
    Format.fprintf fmt "    Source: [%d] %a@."
      p.proj_prod_idx Grammar.pp_production prod;
    Format.fprintf fmt "@."
  ) used.used_projections;

  Format.fprintf fmt "Left Expansions P_H^(2):@.";
  Format.fprintf fmt "----------------------------------------@.";
  LeftExpandSet.iter (fun e ->
    let prod = prods.(e.left_source.prod_idx) in
    Format.fprintf fmt "  %a -> %a %a@."
      Hcover.pp_hitem e.left_result Hcover.pp_symbol_opt e.left_symbol Hcover.pp_partial e.left_source;
    Format.fprintf fmt "    Source: [%d] %a@."
      e.left_source.prod_idx Grammar.pp_production prod;
    Format.fprintf fmt "@."
  ) used.used_left_expansions;

  Format.fprintf fmt "Right Expansions P_H^(2):@.";
  Format.fprintf fmt "----------------------------------------@.";
  RightExpandSet.iter (fun e ->
    let prod = prods.(e.right_source.prod_idx) in
    Format.fprintf fmt "  %a -> %a %a@."
      Hcover.pp_hitem e.right_result Hcover.pp_partial e.right_source Hcover.pp_symbol_opt e.right_symbol;
    Format.fprintf fmt "    Source: [%d] %a@."
      e.right_source.prod_idx Grammar.pp_production prod;
    Format.fprintf fmt "@."
  ) used.used_right_expansions

let format_used_hcover ?(explain = false) grammar (used : used_hcover) =
  let buf = Buffer.create 1024 in
  let fmt = Format.formatter_of_buffer buf in
  if explain then
    pp_used_hcover_explain grammar fmt used
  else
    pp_used_hcover fmt used;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

(* Derivation functions *)

let get_derivation t =
  let start_symbol = Grammar.start (Hcover.grammar t.hcover) in
  let start_item = Hcover.Complete { symbol = start_symbol } in
  let key = (0, t.last_n, start_item) in
  DerivMap.find_opt key t.last_derivations

let item_to_string item =
  match item with
  | Hcover.Partial p -> Printf.sprintf "I_%d^(%d,%d)" p.prod_idx p.s p.t
  | Hcover.Complete c -> Printf.sprintf "I_%s" c.symbol

let rec format_derivation_step tokens indent buf step =
  let prefix = String.make (indent * 2) ' ' in
  let (i, j) = step.deriv_span in
  let span_text = if j > i && j <= Array.length tokens then
    String.concat " " (Array.to_list (Array.sub tokens i (j - i)))
  else "" in
  let rule_str = match step.deriv_rule with
    | Some (RuleProjection _) -> "Projection"
    | Some (RuleLeftExpand _) -> "LeftExpand"
    | Some (RuleRightExpand _) -> "RightExpand"
    | None -> ""
  in
  let term_str = match step.deriv_terminal with
    | Some t -> Printf.sprintf " (terminal scan: %s)" t
    | None -> if rule_str <> "" then Printf.sprintf " (%s)" rule_str else ""
  in
  Buffer.add_string buf (Printf.sprintf "%s%s @ [%d,%d] '%s'%s\n"
    prefix (item_to_string step.deriv_item) i j span_text term_str);
  List.iter (format_derivation_step tokens (indent + 1) buf) step.deriv_children

let pp_derivation tokens fmt step =
  let buf = Buffer.create 1024 in
  format_derivation_step (Array.of_list tokens) 0 buf step;
  Format.fprintf fmt "%s" (Buffer.contents buf)

let format_derivation tokens step =
  let buf = Buffer.create 1024 in
  format_derivation_step (Array.of_list tokens) 0 buf step;
  Buffer.contents buf
