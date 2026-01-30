(** Tests for the head-driven tabular recognizer. *)

open Algorithm7

(* Simple test framework *)
let tests_run = ref 0
let tests_passed = ref 0
let tests_failed = ref 0

let check name condition =
  incr tests_run;
  if condition then begin
    incr tests_passed;
    Printf.printf "  [PASS] %s\n" name
  end else begin
    incr tests_failed;
    Printf.printf "  [FAIL] %s\n" name
  end

let check_raises name f =
  incr tests_run;
  try
    f ();
    incr tests_failed;
    Printf.printf "  [FAIL] %s (expected exception)\n" name
  with _ ->
    incr tests_passed;
    Printf.printf "  [PASS] %s\n" name

let run_suite name f =
  Printf.printf "\n=== %s ===\n" name;
  f ()

(* ============== Grammar Tests ============== *)

let test_grammar () =
  run_suite "Grammar" (fun () ->
    (* Basic production *)
    let prod = Grammar.{ lhs = "S"; rhs = [|"NP"; "VP"|]; head_pos = 2 } in
    check "basic production lhs" (prod.lhs = "S");
    check "basic production head_pos" (prod.head_pos = 2);
    check "basic production head" (Grammar.head prod = "VP");

    (* Head position validation *)
    check_raises "head_pos=0 raises" (fun () ->
      ignore (Grammar.add_production (Grammar.create ()) ~lhs:"S" ~rhs:["NP"; "VP"] ~head_pos:0));
    check_raises "head_pos=3 raises" (fun () ->
      ignore (Grammar.add_production (Grammar.create ()) ~lhs:"S" ~rhs:["NP"; "VP"] ~head_pos:3));

    (* Empty RHS validation *)
    check_raises "empty rhs raises" (fun () ->
      ignore (Grammar.add_production (Grammar.create ()) ~lhs:"S" ~rhs:[] ~head_pos:1));

    (* Add production *)
    let g = Grammar.create () in
    let idx = Grammar.add_production g ~lhs:"S" ~rhs:["NP"; "VP"] ~head_pos:2 in
    check "add_production returns 0" (idx = 0);
    check "num_productions is 1" (Grammar.num_productions g = 1);
    check "S is nonterminal" (Grammar.is_nonterminal g "S");
    check "NP is terminal" (Grammar.is_terminal g "NP");

    ignore (Grammar.add_production g ~lhs:"NP" ~rhs:["n"] ~head_pos:1);
    ignore (Grammar.add_production g ~lhs:"VP" ~rhs:["v"] ~head_pos:1);
    check "NP is nonterminal" (Grammar.is_nonterminal g "NP");
    check "VP is nonterminal" (Grammar.is_nonterminal g "VP");

    (* From string *)
    let text = {|
      S -> NP [VP]
      VP -> cl [v] NP
      NP -> [det] n
    |} in
    let g = Grammar.from_string text in
    check "from_string: 3 productions" (Grammar.num_productions g = 3);
    let prods = Grammar.productions g in
    check "prod0 head is VP" (Grammar.head prods.(0) = "VP");
    check "prod1 head is v" (Grammar.head prods.(1) = "v");
    check "prod2 head is det" (Grammar.head prods.(2) = "det");

    (* Default head *)
    let g = Grammar.from_string "S -> a b" in
    let prod = Grammar.get_production g 0 in
    check "default head_pos is 1" (prod.head_pos = 1);
    check "default head is a" (Grammar.head prod = "a");

    (* Terminals and nonterminals *)
    let g = Grammar.from_string {|
      S -> [a] B
      B -> [c]
    |} in
    check "a is terminal" (Grammar.is_terminal g "a");
    check "c is terminal" (Grammar.is_terminal g "c");
    check "S is nonterminal" (Grammar.is_nonterminal g "S");
    check "B is nonterminal" (Grammar.is_nonterminal g "B");

    (* Lowercase nonterminal via LHS *)
    let g = Grammar.from_string ~start:"s" "s -> [a]" in
    check "s is nonterminal" (Grammar.is_nonterminal g "s");
    check "a is terminal" (Grammar.is_terminal g "a")
  )

(* ============== HCover Tests ============== *)

let simple_grammar () = Grammar.from_string "S -> [a] b"

let paper_grammar () = Grammar.from_string {|
  S -> NP [VP]
  VP -> cl [v] NP
  NP -> [det] n
|}

let test_hcover () =
  run_suite "HCover" (fun () ->
    (* Projections *)
    let g = simple_grammar () in
    let hc = Hcover.create g in
    let projs = Hcover.get_projections hc "a" in
    check "1 projection for 'a'" (List.length projs = 1);
    check "projection prod_idx is 0" ((List.hd projs).proj_prod_idx = 0);

    (* Initial item *)
    let item = Hcover.initial_item hc 0 in
    check "initial item prod_idx" (item.prod_idx = 0);
    check "initial item s" (item.s = 0);
    check "initial item t" (item.t = 1);

    (* Left expansions *)
    let g = paper_grammar () in
    let hc = Hcover.create g in
    let initial = Hcover.initial_item hc 1 in  (* VP -> cl [v] NP *)
    check "VP initial s=1" (initial.s = 1);
    check "VP initial t=2" (initial.t = 2);
    let left_exps = Hcover.get_left_expansions hc initial in
    check "1 left expansion" (List.length left_exps = 1);
    let exp = List.hd left_exps in
    check "left symbol is cl" (exp.left_symbol = "cl");
    (match exp.left_result with
     | Hcover.Partial p ->
       check "left result s=0" (p.s = 0);
       check "left result t=2" (p.t = 2)
     | Hcover.Complete _ -> check "left result is partial" false);

    (* Right expansions *)
    let right_exps = Hcover.get_right_expansions hc initial in
    check "1 right expansion" (List.length right_exps = 1);
    let exp = List.hd right_exps in
    check "right symbol is NP" (exp.right_symbol = "NP");
    (match exp.right_result with
     | Hcover.Partial p ->
       check "right result s=1" (p.s = 1);
       check "right result t=3" (p.t = 3)
     | Hcover.Complete _ -> check "right result is partial" false);

    (* Completion *)
    let head_item = Hcover.{ prod_idx = 2; s = 0; t = 1 } in
    let right_exps = Hcover.get_right_expansions hc head_item in
    check "1 right completion expansion" (List.length right_exps = 1);
    let exp = List.hd right_exps in
    check "right completion symbol is n" (exp.right_symbol = "n");
    (match exp.right_result with
     | Hcover.Complete c -> check "completion result is NP" (c.symbol = "NP")
     | Hcover.Partial _ -> check "completion result is complete" false)
  )

(* ============== Recognizer Tests ============== *)

let test_recognizer () =
  run_suite "Recognizer" (fun () ->
    (* Single terminal *)
    let g = Grammar.from_string "S -> [a]" in
    let rec' = Recognizer.create g in
    check "accept 'a'" (Recognizer.recognize rec' ["a"]);
    check "reject 'b'" (not (Recognizer.recognize rec' ["b"]));
    check "reject 'a a'" (not (Recognizer.recognize rec' ["a"; "a"]));

    (* Two terminals *)
    let g = Grammar.from_string "S -> [a] b" in
    let rec' = Recognizer.create g in
    check "accept 'a b'" (Recognizer.recognize rec' ["a"; "b"]);
    check "reject 'a'" (not (Recognizer.recognize rec' ["a"]));
    check "reject 'b'" (not (Recognizer.recognize rec' ["b"]));
    check "reject 'b a'" (not (Recognizer.recognize rec' ["b"; "a"]));

    (* Paper grammar *)
    let g = paper_grammar () in
    let rec' = Recognizer.create g in
    check "accept paper example" (Recognizer.recognize rec' ["det"; "n"; "cl"; "v"; "det"; "n"]);
    check "reject missing cl" (not (Recognizer.recognize rec' ["det"; "n"; "v"; "det"; "n"]));
    check "reject wrong order" (not (Recognizer.recognize rec' ["det"; "det"; "n"; "cl"; "v"; "n"]));
    check "reject empty" (not (Recognizer.recognize rec' []));

    (* Recursive grammar: S -> a S b | c *)
    let g = Grammar.from_string {|
      S -> a [S] b
      S -> [c]
    |} in
    let rec' = Recognizer.create g in
    check "recursive: accept 'c'" (Recognizer.recognize rec' ["c"]);
    check "recursive: accept 'a c b'" (Recognizer.recognize rec' ["a"; "c"; "b"]);
    check "recursive: accept 'a a c b b'" (Recognizer.recognize rec' ["a"; "a"; "c"; "b"; "b"]);
    check "recursive: reject 'a c'" (not (Recognizer.recognize rec' ["a"; "c"]));
    check "recursive: reject 'a a c b'" (not (Recognizer.recognize rec' ["a"; "a"; "c"; "b"]));

    (* Ambiguous grammar *)
    let g = Grammar.from_string {|
      S -> S [plus] S
      S -> [a]
    |} in
    let rec' = Recognizer.create g in
    check "ambiguous: accept 'a'" (Recognizer.recognize rec' ["a"]);
    check "ambiguous: accept 'a plus a'" (Recognizer.recognize rec' ["a"; "plus"; "a"]);
    check "ambiguous: accept 'a plus a plus a'" (Recognizer.recognize rec' ["a"; "plus"; "a"; "plus"; "a"]);
    check "ambiguous: reject 'plus'" (not (Recognizer.recognize rec' ["plus"]))
  )

(* ============== Integration Tests ============== *)

let test_integration () =
  run_suite "Integration" (fun () ->
    (* Arithmetic expression grammar *)
    let g = Grammar.from_string ~start:"E" {|
      E -> E [plus] T
      E -> [T]
      T -> T [times] F
      T -> [F]
      F -> lparen [E] rparen
      F -> [id]
    |} in
    let rec' = Recognizer.create g in
    check "arith: accept 'id'" (Recognizer.recognize rec' ["id"]);
    check "arith: accept 'id + id'" (Recognizer.recognize rec' ["id"; "plus"; "id"]);
    check "arith: accept 'id * id'" (Recognizer.recognize rec' ["id"; "times"; "id"]);
    check "arith: accept 'id + id * id'" (Recognizer.recognize rec' ["id"; "plus"; "id"; "times"; "id"]);
    check "arith: accept '(id)'" (Recognizer.recognize rec' ["lparen"; "id"; "rparen"]);
    check "arith: accept '(id + id)'" (Recognizer.recognize rec' ["lparen"; "id"; "plus"; "id"; "rparen"]);
    check "arith: reject unbalanced" (not (Recognizer.recognize rec' ["lparen"; "id"]));
    check "arith: reject missing operand" (not (Recognizer.recognize rec' ["id"; "plus"]))
  )

(* ============== Main ============== *)

let () =
  Printf.printf "Running Algorithm7 Tests\n";
  Printf.printf "========================\n";

  test_grammar ();
  test_hcover ();
  test_recognizer ();
  test_integration ();

  Printf.printf "\n========================\n";
  Printf.printf "Results: %d/%d passed" !tests_passed !tests_run;
  if !tests_failed > 0 then
    Printf.printf " (%d failed)" !tests_failed;
  Printf.printf "\n";

  if !tests_failed > 0 then exit 1
