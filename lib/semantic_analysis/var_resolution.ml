open Batteries
open Ast

type var_entry = { unique_name : string; from_current_block : bool }

let copy_variable_map m =
  (* return a copy of the map with from_current_block set to false for every entry *)
  Map.map (fun entry -> { entry with from_current_block = false }) m

let rec resolve_exp var_map = function
  | Assignment (left, right) ->
      (* validate that lhs is an lvalue *)
      let _ =
        match left with
        | Var _ -> ()
        | _ ->
            failwith
              (Format.asprintf
                 "Expected lvalue on left-hand side of assignment statement, \
                  found %a"
                 pp_exp left)
      in
      (* recursively process lhs and rhs *)
      Assignment (resolve_exp var_map left, resolve_exp var_map right)
  | CompoundAssignment (op, left, right) ->
      (* validate that lhs is an lvalue *)
      let _ =
        match left with
        | Var _ -> ()
        | _ ->
            failwith
              (Format.asprintf
                 "Expected lvalue on left-hand side of compound assignment \
                  statement, found %a"
                 pp_exp left)
      in
      (* recursively process lhs and rhs *)
      CompoundAssignment
        (op, resolve_exp var_map left, resolve_exp var_map right)
  | PostfixIncr (Var _ as e) -> PostfixIncr (resolve_exp var_map e)
  | PostfixIncr e ->
      failwith
        ("Operand of postfix expression must be lvalue, found " ^ show_exp e)
  | PostfixDecr (Var _ as e) -> PostfixDecr (resolve_exp var_map e)
  | PostfixDecr e ->
      failwith
        ("Operand of postfix expression must be lvalue, found " ^ show_exp e)
  | Var v -> (
      (* rename var from map  *)
      try Var (Map.find v var_map).unique_name
      with Not_found -> failwith (Printf.sprintf "Undeclared variable %s" v))
  (* recursively process operands for unary, binary, and conditional *)
  | Unary (op, e) ->
      (* validate prefix ops*)
      (match (op, e) with
      | (Incr | Decr), Var _ -> ()
      | (Incr | Decr), _ -> failwith "operand of ++/-- must be a variable"
      | _ -> ());
      Unary (op, resolve_exp var_map e)
  | Binary (op, e1, e2) ->
      Binary (op, resolve_exp var_map e1, resolve_exp var_map e2)
  | Conditional { condition; then_result; else_result } ->
      Conditional
        {
          condition = resolve_exp var_map condition;
          then_result = resolve_exp var_map then_result;
          else_result = resolve_exp var_map else_result;
        }
  (* Nothing to do for constant *)
  | Constant _ as c -> c

let resolve_declaration var_map (Declaration { name; init }) =
  match Map.find_opt name var_map with
  | Some { from_current_block = true; _ } ->
      (* variable is present in the map and was defined in the current block *)
      failwith "Duplicate variable declaration"
  | _ ->
      (* variable isn't in the map, or was defined in an outer scope;
       * generate a unique name and add it to the map *)
      let unique_name = Unique_ids.make_named_temporary name in
      let new_map =
        Map.add name { unique_name; from_current_block = true } var_map
      in
      (* resolve initializer if there is one *)
      let resolved_init = Option.map (resolve_exp new_map) init in
      (* return new map and resolved declaration *)
      (new_map, Declaration { name = unique_name; init = resolved_init })

let rec resolve_statement var_map = function
  | Return e -> Return (resolve_exp var_map e)
  | Expression e -> Expression (resolve_exp var_map e)
  | If { condition; then_clause; else_clause } ->
      If
        {
          condition = resolve_exp var_map condition;
          then_clause = resolve_statement var_map then_clause;
          else_clause = Option.map (resolve_statement var_map) else_clause;
        }
  | LabeledStatement (lbl, stmt) ->
      LabeledStatement (lbl, resolve_statement var_map stmt)
  | Goto lbl -> Goto lbl
  | Compound block ->
      let new_variable_map = copy_variable_map var_map in
      Compound (resolve_block new_variable_map block)
  | Null -> Null

and resolve_block_item var_map = function
  | S s ->
      (* resolving a statement doesn't change the variable map *)
      let resolved_s = resolve_statement var_map s in
      (var_map, S resolved_s)
  | D d ->
      (* resolving a declaration does change the variable map *)
      let new_map, resolved_d = resolve_declaration var_map d in
      (new_map, D resolved_d)

and resolve_block var_map (Block items) =
  let _final_map, resolved_items =
    List.fold_left_map resolve_block_item var_map items
  in
  Block resolved_items

let resolve_function_def (Function { name; body = blk }) =
  let resolved_body = resolve_block Map.empty blk in
  Function { name; body = resolved_body }

let resolve (Program fn_def) = Program (resolve_function_def fn_def)
