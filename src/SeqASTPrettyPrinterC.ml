
open Format
open PrintUtils
open SeqAST

let type_of_expr = function
  | Val (_, t)
  | Var (_,t)
  | CallFun ((_,t),_) -> t
  | Opu (_, _) -> Sty "bool" (*only "not" implemented for now*)
  | Op (b, _, _) -> begin
    match b with
    | Equal -> Sty "bool"
    | _ -> Sty "int"
  end

let prefix_args_table = Hashtbl.create 20;;

let ad= "&"
let cast= "(PICC_KnownValue*) &"

let _ =
  (* Hashtbl.add prefix_args_table SeqASTConstC.bool_of_bool_value [ad]; *)
  Hashtbl.add prefix_args_table SeqASTConstC.knownSet_add [""; cast];
  Hashtbl.add prefix_args_table SeqASTConstC.knownSet_register [""; cast];
  Hashtbl.add prefix_args_table SeqASTConstC.knownSet_forget_to_unknown [""; cast];
  Hashtbl.add prefix_args_table SeqASTConstC.handle_dec_ref_count [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.get_handle [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.acquire_handle [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.handle_globalrc [ad];

  Hashtbl.add prefix_args_table SeqASTConstC.bool_of_bool_value [ad];

  Hashtbl.add prefix_args_table SeqASTConstC.init_bool_true [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.init_bool_false [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.init_int_value [ad; ""];
  Hashtbl.add prefix_args_table SeqASTConstC.init_string_value [ad; ""];
  Hashtbl.add prefix_args_table SeqASTConstC.init_channel_value [ad; ""];

  Hashtbl.add prefix_args_table SeqASTConstC.fetch_input_commitment [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.fetch_output_commitment [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.outcommits_of_channel_value [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.incommits_of_channel_value [ad];
  Hashtbl.add prefix_args_table SeqASTConstC.register_input_commitment [""; ad; ""; ""];
  Hashtbl.add prefix_args_table SeqASTConstC.register_output_commitment [""; ad; ""; ""];

  Hashtbl.add prefix_args_table SeqASTConstC.add_name [ad;ad;ad];
  Hashtbl.add prefix_args_table SeqASTConstC.substract_name [ad;ad;ad];
  Hashtbl.add prefix_args_table SeqASTConstC.modulo_name [ad;ad;ad];
  Hashtbl.add prefix_args_table SeqASTConstC.equals_name [ad;ad;ad];
  Hashtbl.add prefix_args_table SeqASTConstC.less_than_name [ad;ad;ad];
  Hashtbl.add prefix_args_table SeqASTConstC.print_str_name [ad];
  (* Hashtbl.add prefix_args_table SeqASTConstC.print_int_name [ad]; == print_str_name *)
  Hashtbl.add prefix_args_table SeqASTConstC.print_info_name [ad]
  
    
let prefixes n l =
    try
      Hashtbl.find prefix_args_table n
    with Not_found -> begin
      let rec f i acc =
	if i == 0 then  acc
	else f (i - 1) ("" :: acc)
      in f (List.length l) []
    end


let rec print_piccType fmt = function
  | Sty s -> fprintf fmt "%s" s
  | Pty ("*", t) -> fprintf fmt "%a*" print_piccType t
  | Pty (s,t) -> fprintf fmt "%s%a" s print_piccType t
  | Fun (t, tl) ->  fprintf fmt "%a (@[ %a @])" print_piccType t 
      (print_list print_piccType ", ") tl
      
let print_binop fmt = function
  | Sum -> fprintf fmt "+"
  | Minus -> fprintf fmt "-"
  | Mult -> fprintf fmt "*"
  | Div -> fprintf fmt "/"
  | Equal -> fprintf fmt "=="

let print_unop fmt = function
  | Not -> fprintf fmt "!"

let rec print_varName fmt = function
  | SimpleName n -> fprintf fmt "%s" n
  | RecordName ((v, (Pty (nt, _))),n) -> 
    fprintf fmt (if nt = "*" then
	"%a->%s" 
      else
	"%a.%s") print_varName v n

  | RecordName ((v, _),n) -> fprintf fmt "%a.%s" print_varName v n
  | ArrayName (v,e) -> fprintf fmt "%a[%a]" print_varName v print_expr e

and print_arg_list prefixes fmt args =
  match prefixes, args with  
  | [], [] -> () (* /!\ No test, but normally only string and channel are given to knownSet *)
  | [p], [x] -> fprintf fmt "%s%a" p print_expr x
  | ph::ptl, ah::atl -> 
    fprintf fmt "%s%a,@ %a" ph print_expr ah (print_arg_list ptl) atl
  | _ -> failwith "Wrong arity in the output code"


and print_expr fmt = function
  | Val (v, _) -> fprintf fmt "%s" v
  | Var (v, _) -> fprintf fmt "%a" print_varName v
  | Op (op, e1, e2) -> fprintf fmt "(%a) %a (%a)" print_expr e1 print_binop op print_expr e2
  | Opu (op, e) -> fprintf fmt "%a (%a)" print_unop op print_expr e

  | CallFun ((SimpleName f, Fun (_, argTypes )), args) -> 
    fprintf fmt "%s(@[ %a @])" f
      (print_arg_list (prefixes f argTypes)) args

  | CallFun ((f,_), args) -> 
    fprintf fmt "%a(@[ %a @])" print_varName f
      (print_list print_expr ", ") args


let string_name_of_varDescr (n, _) =
  print_varName str_formatter n;
  flush_str_formatter ()

let rec print_instr fmt = function
  | Comment str ->
      fprintf fmt "/* %s */@\n" str
  | Debug str ->
    if Settings.debug then
      fprintf fmt "printf(\"%s\\n\");@\n" (Str.global_replace (Str.regexp "\"") "\\\""  str)
  | Switch (e, il) -> 
    fprintf fmt "switch(%a){@\n@[<hov 3>%a@]@\n}" 
      print_expr e (print_list_eol print_instr "") il
  | Case e -> fprintf fmt "case %a:@\n" print_expr e
  | Bloc il -> fprintf fmt "{@\n@[%a@]@\n}" (print_list_eol print_instr "") il
  | Seq il -> fprintf fmt  "%a" (print_list_eol print_instr "") il
  

  | CallProc ((SimpleName f, Fun (_, (argTypes))), args) -> 
    fprintf fmt "%s(@[ %a @]);" f
    (print_arg_list (prefixes f argTypes)) args


  | CallProc ((f,_), el) -> fprintf fmt "%a(@[ %a @]);" print_varName f
    (print_list print_expr ", ") el


  | Declare (v,t) -> fprintf fmt "%a %a;" print_piccType t print_varName v
  | Assign ((v,_), e) -> fprintf fmt "%a = %a;" print_varName v print_expr e
  
  | DeclareFun (( v, (Fun (ret, argType))), args_names, []) ->
    fprintf fmt "%a %a(%a);"
      print_piccType ret
      print_varName v
      (print_list2 print_piccType print_string ", ") (argType, args_names)

  | DeclareFun (( v, (Fun (ret, argType))), args_names, il) ->
    fprintf fmt "%a %a(%a){@\n@[<hov 3>%a@]@\n}"
      print_piccType ret
      print_varName v
      (print_list2 print_piccType print_string ", ") (argType, args_names)
      (print_list print_instr "") il

  | DeclareFun (_,_,_) -> failwith "Must be Fun to be declared as function"
    
  (* foreach (name : type) in (Fun) do () *)
  (* | Foreach ((v,t), e, il) -> (\* !!! *\) *)
  (*   fprintf fmt "foreach %a : %a in %a {@[%a@]}" *)
  (*     print_varName v *)
  (*     print_piccType t *)
  (*     print_expr e *)
  (*     (print_list_eol' print_instr "") il *)

  | Foreach ((v,_), e, il) -> (* !!! *)
    fprintf fmt 
      "{PICC_KnownValue %a;@\n PICC_KnownSet* s=%a;@\nPICC_KNOWNSET_FOREACH(s, @ %a){@\n @[%a@] @\n}@\nPICC_free_knownset(s);@\n}@\n"
      print_varName v
      print_expr e
      print_varName v
      (print_list_eol' print_instr "") il

  | Ite (e, [], []) -> fprintf fmt ""
      
  | Ite (e, il1, []) ->
    fprintf fmt "if ( %a ){@\n@[<hov 3>%a@]}"
      print_expr e
      (print_list_eol' print_instr "") il1
  | Ite (e, il1, il2) ->
    fprintf fmt "if ( %a ){@\n@[<hov 3>%a@]}else{@\n@[<hov 3>%a@]}"
      print_expr e
      (print_list_eol' print_instr "") il1
      (print_list_eol' print_instr "") il2
  
  | Label s ->fprintf fmt "%s:" s
  | Goto s -> fprintf fmt "goto %s;" s
  | Return e -> fprintf fmt "return %a;" print_expr e
  | DoWhile (il, e) -> fprintf fmt "do{@\n%a}while(%a);" 
    (print_list_eol' print_instr "") il
    print_expr e
      

let print_main nb_th entry_point std_gc_fuel quick_gc_fuel active_factor eSize kSize enabled fmt i =
  let inc_list = 
    ["#include <runtime.h>";
     "#include <value.h>";
     "#include <queue.h>";
     "#include <pi_thread_repr.h>";
     "#include <knownset_repr.h>";
     "#include <commit_repr.h>";
     "#include <scheduler_repr.h>"
     ]
  in
  let inc_list = if Settings.debug then "#include <stdio.h>" :: inc_list
      else inc_list
  in
  Format.fprintf fmt
    "%a@\n@\n@\n@\n%a@\n@\n@\n@\nint main(){ PICC_main(%d, %s, %d, %d, %d, %d, %d, %d); return 0;}"
    PrintUtils.(print_list_eol print_string "") inc_list
    print_instr i nb_th entry_point std_gc_fuel quick_gc_fuel active_factor eSize kSize enabled
    

let print_instr_list_std il =
  set_margin 150;
  List.iter (fun i -> Format.printf "%a@\n" print_instr i) il
