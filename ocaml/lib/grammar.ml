(** Grammar representation for head-driven parsing. *)

type symbol = string

type production = {
  lhs : symbol;
  rhs : symbol array;
  head_pos : int;
}

let head prod =
  if Array.length prod.rhs = 0 then
    invalid_arg "Empty RHS has no head"
  else
    prod.rhs.(prod.head_pos - 1)
let epsilon_tokens = ["ε"; "eps"; "epsilon"]

module StringSet = Set.Make(String)

type t = {
  start : symbol;
  mutable productions : production list;
  mutable nonterminals : StringSet.t;
  mutable terminals : StringSet.t;
}

let create ?(start = "S") () = {
  start;
  productions = [];
  nonterminals = StringSet.empty;
  terminals = StringSet.empty;
}

let recompute_symbols t =
  let nonterms =
    List.fold_left (fun acc p -> StringSet.add p.lhs acc) StringSet.empty t.productions
  in
  let rhs_symbols =
    List.fold_left (fun acc p ->
      Array.fold_left (fun acc sym -> StringSet.add sym acc) acc p.rhs
    ) StringSet.empty t.productions
  in
  t.nonterminals <- nonterms;
  t.terminals <- StringSet.diff rhs_symbols nonterms

let add_production t ~lhs ~rhs ~head_pos =
  let rhs_arr = Array.of_list rhs in
  let n = Array.length rhs_arr in
  if n = 0 then begin
    if head_pos <> 0 then
      invalid_arg "Empty RHS must use head_pos=0"
  end else if head_pos < 1 || head_pos > n then
    invalid_arg (Printf.sprintf "Head position %d out of range for RHS of length %d" head_pos n);
  let prod = { lhs; rhs = rhs_arr; head_pos } in
  let idx = List.length t.productions in
  t.productions <- t.productions @ [prod];
  recompute_symbols t;
  idx

let start t = t.start

let productions t = Array.of_list t.productions

let get_production t idx =
  let prods = productions t in
  if idx < 0 || idx >= Array.length prods then
    invalid_arg (Printf.sprintf "Production index %d out of range" idx);
  prods.(idx)

let num_productions t = List.length t.productions

let is_terminal t sym = StringSet.mem sym t.terminals

let is_nonterminal t sym = StringSet.mem sym t.nonterminals

let productions_with_head t h =
  let prods = productions t in
  Array.to_list prods
  |> List.mapi (fun i p -> (i, p))
  |> List.filter (fun (_, p) -> head p = h)

let parse_rhs_with_head parts =
  let rhs = ref [] in
  let head_pos = ref None in
  let parts = List.filter (fun s -> s <> "") parts in
  if parts = [] then
    ([], 0)
  else if List.length parts = 1 && List.mem (List.hd parts) epsilon_tokens then
    ([], 0)
  else begin
    List.iteri (fun i part ->
    let part = String.trim part in
    if String.length part >= 2 && part.[0] = '[' && part.[String.length part - 1] = ']' then begin
      let sym = String.sub part 1 (String.length part - 2) in
      if List.mem sym epsilon_tokens then
        invalid_arg "Cannot mark epsilon as head";
      head_pos := Some (i + 1);  (* 1-indexed *)
      rhs := sym :: !rhs
    end else if part <> "" then begin
      if List.mem part epsilon_tokens then
        invalid_arg "Epsilon production must be empty (no symbols)";
      rhs := part :: !rhs
    end
  ) parts;
    let rhs = List.rev !rhs in
    let head_pos = match !head_pos with
      | Some p -> p
      | None -> 1  (* Default: first symbol is head *)
    in
    (rhs, head_pos)
  end

let from_string ?(start = "S") text =
  let g = create ~start () in
  String.split_on_char '\n' text
  |> List.iter (fun line ->
       let line = String.trim line in
       if line <> "" && not (String.length line > 0 && line.[0] = '#') then
         match String.index_opt line '-' with
         | None -> failwith ("Invalid production format: " ^ line)
         | Some idx ->
           (* Check for -> *)
           if idx + 1 < String.length line && line.[idx + 1] = '>' then begin
             let lhs = String.trim (String.sub line 0 idx) in
             let rhs_str = String.sub line (idx + 2) (String.length line - idx - 2) in
             let parts = String.split_on_char ' ' (String.trim rhs_str) in
             let rhs, head_pos = parse_rhs_with_head parts in
             ignore (add_production g ~lhs ~rhs ~head_pos)
           end else
             failwith ("Invalid production format: " ^ line)
     );
  g

let pp_production fmt prod =
  if Array.length prod.rhs = 0 then
    Format.fprintf fmt "%s -> ε" prod.lhs
  else
    let rhs_strs = Array.mapi (fun i sym ->
      if i = prod.head_pos - 1 then
        "[" ^ sym ^ "]"
      else
        sym
    ) prod.rhs in
    Format.fprintf fmt "%s -> %s" prod.lhs (String.concat " " (Array.to_list rhs_strs))

let nullable_nonterminals t =
  let nullable = ref StringSet.empty in
  List.iter (fun p ->
    if Array.length p.rhs = 0 then
      nullable := StringSet.add p.lhs !nullable
  ) t.productions;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun p ->
      if not (StringSet.mem p.lhs !nullable) then begin
        if Array.length p.rhs = 0 then begin
          nullable := StringSet.add p.lhs !nullable;
          changed := true
        end else begin
          let all_nullable = ref true in
          Array.iter (fun sym ->
            if not (StringSet.mem sym t.nonterminals) then
              all_nullable := false
            else if not (StringSet.mem sym !nullable) then
              all_nullable := false
          ) p.rhs;
          if !all_nullable then begin
            nullable := StringSet.add p.lhs !nullable;
            changed := true
          end
        end
      end
    ) t.productions
  done;
  StringSet.elements !nullable

let ensure_single_start t =
  let start = t.start in
  let start_count =
    List.fold_left (fun acc p -> if p.lhs = start then acc + 1 else acc) 0 t.productions
  in
  if start_count <= 1 then
    t
  else
    let symbols = StringSet.add start (StringSet.union t.nonterminals t.terminals) in
    let rec pick idx =
      let suffix = if idx = 0 then "" else string_of_int idx in
      let candidate = start ^ "_START" ^ suffix in
      if StringSet.mem candidate symbols then
        pick (idx + 1)
      else
        candidate
    in
    let new_start = pick 0 in
    let g = create ~start:new_start () in
    List.iter (fun p ->
      ignore (add_production g ~lhs:p.lhs ~rhs:(Array.to_list p.rhs) ~head_pos:p.head_pos)
    ) t.productions;
    ignore (add_production g ~lhs:new_start ~rhs:[start] ~head_pos:1);
    g

let pp fmt t =
  Format.fprintf fmt "Grammar(start=%s)@." t.start;
  let prods = productions t in
  Array.iteri (fun i p ->
    Format.fprintf fmt "  [%d] %a@." i pp_production p
  ) prods
