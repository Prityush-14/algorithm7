(** Grammar representation for head-driven parsing. *)

type symbol = string

type production = {
  lhs : symbol;
  rhs : symbol array;
  head_pos : int;
}

let head prod = prod.rhs.(prod.head_pos - 1)

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

let is_uppercase_start s =
  String.length s > 0 &&
  let c = s.[0] in
  c >= 'A' && c <= 'Z'

let add_production t ~lhs ~rhs ~head_pos =
  let rhs_arr = Array.of_list rhs in
  let n = Array.length rhs_arr in
  if n = 0 then
    invalid_arg "Production RHS cannot be empty";
  if head_pos < 1 || head_pos > n then
    invalid_arg (Printf.sprintf "Head position %d out of range for RHS of length %d" head_pos n);
  let prod = { lhs; rhs = rhs_arr; head_pos } in
  let idx = List.length t.productions in
  t.productions <- t.productions @ [prod];
  t.nonterminals <- StringSet.add lhs t.nonterminals;
  Array.iter (fun sym ->
    if is_uppercase_start sym then
      t.nonterminals <- StringSet.add sym t.nonterminals
    else
      t.terminals <- StringSet.add sym t.terminals
  ) rhs_arr;
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
  List.iteri (fun i part ->
    let part = String.trim part in
    if String.length part >= 2 && part.[0] = '[' && part.[String.length part - 1] = ']' then begin
      let sym = String.sub part 1 (String.length part - 2) in
      head_pos := Some (i + 1);  (* 1-indexed *)
      rhs := sym :: !rhs
    end else if part <> "" then
      rhs := part :: !rhs
  ) parts;
  let rhs = List.rev !rhs in
  let head_pos = match !head_pos with
    | Some p -> p
    | None -> 1  (* Default: first symbol is head *)
  in
  (rhs, head_pos)

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
             let parts = String.split_on_char ' ' (String.trim rhs_str)
                        |> List.filter (fun s -> s <> "") in
             let rhs, head_pos = parse_rhs_with_head parts in
             ignore (add_production g ~lhs ~rhs ~head_pos)
           end else
             failwith ("Invalid production format: " ^ line)
     );
  g

let pp_production fmt prod =
  let rhs_strs = Array.mapi (fun i sym ->
    if i = prod.head_pos - 1 then
      "[" ^ sym ^ "]"
    else
      sym
  ) prod.rhs in
  Format.fprintf fmt "%s -> %s" prod.lhs (String.concat " " (Array.to_list rhs_strs))

let pp fmt t =
  Format.fprintf fmt "Grammar(start=%s)@." t.start;
  let prods = productions t in
  Array.iteri (fun i p ->
    Format.fprintf fmt "  [%d] %a@." i pp_production p
  ) prods
