(** H-cover construction for head-driven parsing. *)

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
  lhs : complete_item;
  head : Grammar.symbol;
  proj_prod_idx : int;
}

type left_expand_prod = {
  left_result : partial_item;
  left_symbol : Grammar.symbol;
  left_source : partial_item;
}

type right_expand_prod = {
  right_result : partial_item;
  right_source : partial_item;
  right_symbol : Grammar.symbol;
}

type complete_prod = {
  comp_result : complete_item;
  comp_source : partial_item;
  comp_prod_idx : int;
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
  completions : complete_prod option PartialTbl.t;
}

let grammar t = t.grammar

let build grammar =
  let projections = Hashtbl.create 16 in
  let left_expansions = PartialTbl.create 64 in
  let right_expansions = PartialTbl.create 64 in
  let completions = PartialTbl.create 32 in

  let prods = Grammar.productions grammar in
  Array.iteri (fun r prod ->
    let tau = prod.Grammar.head_pos in
    let n = Array.length prod.Grammar.rhs in
    let head = Grammar.head prod in

    (* Projection production: I_{prod.lhs} -> head_H *)
    let proj = {
      lhs = { symbol = prod.lhs };
      head;
      proj_prod_idx = r;
    } in
    let existing = Hashtbl.find_opt projections head |> Option.value ~default:[] in
    Hashtbl.replace projections head (proj :: existing);

    (* Generate all possible partial items and their expansions *)
    for s = 1 to tau do
      for t = tau to n do
        let source = { prod_idx = r; s; t } in

        (* Left expansion: if s > 1, we can extend left *)
        if s > 1 then begin
          let result = { prod_idx = r; s = s - 1; t } in
          let symbol = prod.Grammar.rhs.(s - 2) in  (* X_{s-1}, 0-indexed *)
          let exp = { left_result = result; left_symbol = symbol; left_source = source } in
          let existing = PartialTbl.find_opt left_expansions source |> Option.value ~default:[] in
          PartialTbl.replace left_expansions source (exp :: existing)
        end;

        (* Right expansion: if t < n, we can extend right *)
        if t < n then begin
          let result = { prod_idx = r; s; t = t + 1 } in
          let symbol = prod.Grammar.rhs.(t) in  (* X_{t+1}, 0-indexed *)
          let exp = { right_result = result; right_source = source; right_symbol = symbol } in
          let existing = PartialTbl.find_opt right_expansions source |> Option.value ~default:[] in
          PartialTbl.replace right_expansions source (exp :: existing)
        end;

        (* Completion: if spans full RHS (1 to n) *)
        if s = 1 && t = n then begin
          let comp = {
            comp_result = { symbol = prod.lhs };
            comp_source = source;
            comp_prod_idx = r;
          } in
          PartialTbl.replace completions source (Some comp)
        end
      done
    done
  ) prods;

  { grammar; projections; left_expansions; right_expansions; completions }

let create = build

let get_projections t head =
  Hashtbl.find_opt t.projections head |> Option.value ~default:[]

let get_left_expansions t item =
  PartialTbl.find_opt t.left_expansions item |> Option.value ~default:[]

let get_right_expansions t item =
  PartialTbl.find_opt t.right_expansions item |> Option.value ~default:[]

let get_completion t item =
  PartialTbl.find_opt t.completions item |> Option.join

let initial_item t prod_idx =
  let prod = Grammar.get_production t.grammar prod_idx in
  let tau = prod.head_pos in
  { prod_idx; s = tau; t = tau }

(* Pretty printers *)
let pp_partial fmt p =
  Format.fprintf fmt "I_%d^(%d,%d)" p.prod_idx p.s p.t

let pp_complete fmt c =
  Format.fprintf fmt "I_%s" c.symbol

let pp_hitem fmt = function
  | Partial p -> pp_partial fmt p
  | Complete c -> pp_complete fmt c

let pp fmt t =
  Format.fprintf fmt "HCover:@.";
  Format.fprintf fmt "  Projections:@.";
  Hashtbl.iter (fun _head projs ->
    List.iter (fun p ->
      Format.fprintf fmt "    %a -> %s_H (prod %d)@."
        pp_complete p.lhs p.head p.proj_prod_idx
    ) projs
  ) t.projections;
  Format.fprintf fmt "  Left Expansions:@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      Format.fprintf fmt "    %a -> %s %a@."
        pp_partial e.left_result e.left_symbol pp_partial e.left_source
    ) exps
  ) t.left_expansions;
  Format.fprintf fmt "  Right Expansions:@.";
  PartialTbl.iter (fun _source exps ->
    List.iter (fun e ->
      Format.fprintf fmt "    %a -> %a %s@."
        pp_partial e.right_result pp_partial e.right_source e.right_symbol
    ) exps
  ) t.right_expansions;
  Format.fprintf fmt "  Completions:@.";
  PartialTbl.iter (fun _source comp_opt ->
    match comp_opt with
    | Some comp ->
      Format.fprintf fmt "    %a -> %a@."
        pp_complete comp.comp_result pp_partial comp.comp_source
    | None -> ()
  ) t.completions
