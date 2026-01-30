(** H-cover construction for head-driven parsing. *)

module StringSet = Set.Make(String)

type partial_item = {
  prod_idx : int;
  s : int;
  t : int;
}

type complete_item = {
  symbol : Grammar.symbol;
}

type hitem =
  | Partial of partial_item
  | Complete of complete_item

type projection_prod = {
  lhs : hitem;
  head : Grammar.symbol;
  proj_prod_idx : int;
}

type left_expand_prod = {
  left_result : hitem;
  left_symbol : Grammar.symbol option;
  left_source : partial_item;
}

type right_expand_prod = {
  right_result : hitem;
  right_source : partial_item;
  right_symbol : Grammar.symbol option;
}

(* Comparison functions *)
let compare_partial a b =
  let c = Int.compare a.prod_idx b.prod_idx in
  if c <> 0 then c else
  let c = Int.compare a.s b.s in
  if c <> 0 then c else
  Int.compare a.t b.t

let compare_complete a b = String.compare a.symbol b.symbol

let compare_hitem a b =
  match a, b with
  | Partial pa, Partial pb -> compare_partial pa pb
  | Complete ca, Complete cb -> compare_complete ca cb
  | Partial _, Complete _ -> -1
  | Complete _, Partial _ -> 1

(* Hash functions for Hashtbl keys *)
let hash_partial p =
  Hashtbl.hash (p.prod_idx, p.s, p.t)

module PartialItemKey = struct
  type t = partial_item
  let equal a b = compare_partial a b = 0
  let hash = hash_partial
end

module PartialTbl = Hashtbl.Make(PartialItemKey)

type t = {
  grammar : Grammar.t;
  projections : (Grammar.symbol, projection_prod list) Hashtbl.t;
  left_expansions : left_expand_prod list PartialTbl.t;
  right_expansions : right_expand_prod list PartialTbl.t;
}

let grammar t = t.grammar

let build grammar =
  let projections = Hashtbl.create 16 in
  let left_expansions = PartialTbl.create 64 in
  let right_expansions = PartialTbl.create 64 in

  let nullable =
    Grammar.nullable_nonterminals grammar
    |> List.fold_left (fun acc sym -> StringSet.add sym acc) StringSet.empty
  in
  let is_nullable sym = StringSet.mem sym nullable in

  let prods = Grammar.productions grammar in
  Array.iteri (fun r prod ->
    let tau = prod.Grammar.head_pos in
    let n = Array.length prod.Grammar.rhs in
    if n = 0 then
      ()
    else begin
    let head = Grammar.head prod in

    (* Projection production: I_{prod.lhs} -> head_H *)
    let proj_lhs =
      if n = 1 then
        Complete { symbol = prod.lhs }
      else
        Partial { prod_idx = r; s = tau - 1; t = tau }
    in
    let proj = { lhs = proj_lhs; head; proj_prod_idx = r } in
    let existing = Hashtbl.find_opt projections head |> Option.value ~default:[] in
    Hashtbl.replace projections head (proj :: existing);

    (* Expansions for length > 1 *)
    if n > 1 then begin
      (* Left expansions: I_r^(s,t) -> X_H I_r^(s+1,t) *)
      for s = 0 to tau - 2 do
        for t = tau to n do
          let result = { prod_idx = r; s; t } in
          if not (result.s = 0 && result.t = n) then begin
            let source = { prod_idx = r; s = s + 1; t } in
            let symbol = prod.Grammar.rhs.(s) in
            let exp = { left_result = Partial result; left_symbol = Some symbol; left_source = source } in
            let existing = PartialTbl.find_opt left_expansions source |> Option.value ~default:[] in
            let exps = exp :: existing in
            let exps =
              if is_nullable symbol then
                { left_result = Partial result; left_symbol = None; left_source = source } :: exps
              else
                exps
            in
            PartialTbl.replace left_expansions source exps
          end
        done
      done;

      (* Right expansions: I_r^(s,t) -> I_r^(s,t-1) Y_H *)
      for s = 0 to tau - 1 do
        for t = tau + 1 to n do
          let result = { prod_idx = r; s; t } in
          if not (result.s = 0 && result.t = n) then begin
            let source = { prod_idx = r; s; t = t - 1 } in
            let symbol = prod.Grammar.rhs.(t - 1) in
            let exp = { right_result = Partial result; right_source = source; right_symbol = Some symbol } in
            let existing = PartialTbl.find_opt right_expansions source |> Option.value ~default:[] in
            let exps = exp :: existing in
            let exps =
              if is_nullable symbol then
                { right_result = Partial result; right_source = source; right_symbol = None } :: exps
              else
                exps
            in
            PartialTbl.replace right_expansions source exps
          end
        done
      done;

      (* Completions as expansions *)
      if tau > 1 then begin
        let source = { prod_idx = r; s = 1; t = n } in
        let symbol = prod.Grammar.rhs.(0) in
        let exp = { left_result = Complete { symbol = prod.lhs }; left_symbol = Some symbol; left_source = source } in
        let existing = PartialTbl.find_opt left_expansions source |> Option.value ~default:[] in
        let exps = exp :: existing in
        let exps =
          if is_nullable symbol then
            { left_result = Complete { symbol = prod.lhs }; left_symbol = None; left_source = source } :: exps
          else
            exps
        in
        PartialTbl.replace left_expansions source exps
      end;

      if tau < n then begin
        let source = { prod_idx = r; s = 0; t = n - 1 } in
        let symbol = prod.Grammar.rhs.(n - 1) in
        let exp = { right_result = Complete { symbol = prod.lhs }; right_source = source; right_symbol = Some symbol } in
        let existing = PartialTbl.find_opt right_expansions source |> Option.value ~default:[] in
        let exps = exp :: existing in
        let exps =
          if is_nullable symbol then
            { right_result = Complete { symbol = prod.lhs }; right_source = source; right_symbol = None } :: exps
          else
            exps
        in
        PartialTbl.replace right_expansions source exps
      end
    end
    end
  ) prods;

  { grammar; projections; left_expansions; right_expansions }

let create = build

let get_projections t head =
  Hashtbl.find_opt t.projections head |> Option.value ~default:[]

let get_left_expansions t item =
  PartialTbl.find_opt t.left_expansions item |> Option.value ~default:[]

let get_right_expansions t item =
  PartialTbl.find_opt t.right_expansions item |> Option.value ~default:[]

let initial_item t prod_idx =
  let prod = Grammar.get_production t.grammar prod_idx in
  let tau = prod.head_pos in
  if Array.length prod.rhs = 1 then
    invalid_arg "No partial items for length-1 productions";
  { prod_idx; s = tau - 1; t = tau }

(* Pretty printers *)
let pp_partial fmt p =
  Format.fprintf fmt "I_%d^(%d,%d)" p.prod_idx p.s p.t

let pp_complete fmt c =
  Format.fprintf fmt "I_%s" c.symbol

let pp_symbol_opt fmt = function
  | None -> Format.fprintf fmt "ε"
  | Some sym -> Format.fprintf fmt "%s" sym

let symbol_opt_to_string = function
  | None -> "ε"
  | Some sym -> sym

let pp_hitem fmt = function
  | Partial p -> pp_partial fmt p
  | Complete c -> pp_complete fmt c

let pp fmt t =
  Format.fprintf fmt "HCover:@.";
  Format.fprintf fmt "  Projections:@.";
  Hashtbl.iter (fun _head projs ->
    List.iter (fun p ->
      Format.fprintf fmt "    %a -> %s_H (prod %d)@."
        pp_hitem p.lhs p.head p.proj_prod_idx
    ) projs
  ) t.projections;
  Format.fprintf fmt "  Left Expansions:@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      Format.fprintf fmt "    %a -> %a %a@."
        pp_hitem e.left_result pp_symbol_opt e.left_symbol pp_partial e.left_source
    ) exps
  ) t.left_expansions;
  Format.fprintf fmt "  Right Expansions:@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      Format.fprintf fmt "    %a -> %a %a@."
        pp_hitem e.right_result pp_partial e.right_source pp_symbol_opt e.right_symbol
    ) exps
  ) t.right_expansions

let pp_explain fmt t =
  let prods = Grammar.productions t.grammar in
  Format.fprintf fmt "H-Cover G_H (covering grammar for G)@.";
  Format.fprintf fmt "==================================================@.";
  Format.fprintf fmt "@.";
  Format.fprintf fmt "Note: Boundary indices (s,t) follow Satta & Stock 1994@.";
  Format.fprintf fmt "  I_r^(s,t) with 0 ≤ s < τ ≤ t ≤ n and (s,t) ≠ (0,n)@.";
  Format.fprintf fmt "  I_A = complete recognition of nonterminal A@.";
  Format.fprintf fmt "@.";

  (* Projections *)
  Format.fprintf fmt "Projections P_H^(1): I_D -> X_H@.";
  Format.fprintf fmt "  (To recognize D, first find its head X)@.";
  Format.fprintf fmt "----------------------------------------@.";
  Hashtbl.iter (fun _head projs ->
    List.iter (fun p ->
      let prod = prods.(p.proj_prod_idx) in
      Format.fprintf fmt "  %a -> %s_H@."
        pp_hitem p.lhs p.head;
      Format.fprintf fmt "    Source: [%d] %a@."
        p.proj_prod_idx Grammar.pp_production prod;
      Format.fprintf fmt "    Meaning: To recognize %a, first find head '%s'@."
        pp_hitem p.lhs p.head;
      Format.fprintf fmt "@."
    ) projs
  ) t.projections;

  (* Left Expansions *)
  Format.fprintf fmt "Left Expansions P_H^(2): I_r^(s-1,t) -> X_{s-1} I_r^(s,t)@.";
  Format.fprintf fmt "  (Extend partial item leftward by consuming X)@.";
  Format.fprintf fmt "----------------------------------------@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      let prod = prods.(e.left_source.prod_idx) in
      Format.fprintf fmt "  %a -> %a %a@."
        pp_hitem e.left_result pp_symbol_opt e.left_symbol pp_partial e.left_source;
      Format.fprintf fmt "    Source: [%d] %a@."
        e.left_source.prod_idx Grammar.pp_production prod;
      (match e.left_result with
       | Partial p ->
         Format.fprintf fmt "    Meaning: Extend left by consuming '%s' at boundary %d@."
           (symbol_opt_to_string e.left_symbol) p.s
       | Complete c ->
         Format.fprintf fmt "    Meaning: Complete %s by consuming '%s' on the left@."
           c.symbol (symbol_opt_to_string e.left_symbol));
      Format.fprintf fmt "@."
    ) exps
  ) t.left_expansions;

  (* Right Expansions *)
  Format.fprintf fmt "Right Expansions P_H^(2): I_r^(s,t+1) -> I_r^(s,t) X_{t+1}@.";
  Format.fprintf fmt "  (Extend partial item rightward by consuming X)@.";
  Format.fprintf fmt "----------------------------------------@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      let prod = prods.(e.right_source.prod_idx) in
      Format.fprintf fmt "  %a -> %a %a@."
        pp_hitem e.right_result pp_partial e.right_source pp_symbol_opt e.right_symbol;
      Format.fprintf fmt "    Source: [%d] %a@."
        e.right_source.prod_idx Grammar.pp_production prod;
      (match e.right_result with
       | Partial p ->
         Format.fprintf fmt "    Meaning: Extend right by consuming '%s' at boundary %d@."
           (symbol_opt_to_string e.right_symbol) p.t
       | Complete c ->
         Format.fprintf fmt "    Meaning: Complete %s by consuming '%s' on the right@."
           c.symbol (symbol_opt_to_string e.right_symbol));
      Format.fprintf fmt "@."
    ) exps
  ) t.right_expansions
