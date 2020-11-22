module CF=Cerb_frontend
module L = Local
module G = Global
module Loc = Locations
module LC = LogicalConstraints
module RE = Resources
module IT = IndexTerms
module BT = BaseTypes
module LS = LogicalSorts
module LRT = LogicalReturnTypes
module RT = ReturnTypes
module AT = ArgumentTypes
module LFT = ArgumentTypes.Make(LogicalReturnTypes)
module FT = ArgumentTypes.Make(ReturnTypes)
module LT = ArgumentTypes.Make(False)
module TE = TypeErrors
module SymSet = Set.Make(Sym)

open IT
open Loc
open TypeErrors
open Environment
open Local
open Resultat
open LogicalConstraints
open CF.Mucore
open Pp
open BT

(* some of this is informed by impl_mem *)





(*** meta types ***************************************************************)
type pattern = BT.t mu_pattern
type ctor = BT.t mu_ctor
type cti = PreProcess.ctype_information
type 'bty pexpr = (cti, BT.t, 'bty) mu_pexpr
type 'bty expr = (cti, BT.t, 'bty) mu_expr
type 'bty value = (cti, BT.t, 'bty) mu_value
type 'bty object_value = (cti, 'bty) mu_object_value
type mem_value = CF.Impl_mem.mem_value
type pointer_value = CF.Impl_mem.pointer_value
type 'bty label_defs = (LT.t, cti, BT.t, 'bty) mu_label_defs


(*** mucore pp setup **********************************************************)
module PP_MUCORE = CF.Pp_mucore.Make(CF.Pp_mucore.Basic)(Pp_typs)
(* let pp_budget () = Some !debug_level *)
let pp_budget () = Some !print_level
let pp_expr e = PP_MUCORE.pp_expr (pp_budget ()) e
let pp_pexpr e = PP_MUCORE.pp_pexpr (pp_budget ()) e



(*** variable binding *********************************************************)

let rec bind_logical (delta : L.t) (lrt : LRT.t) : L.t = 
  match lrt with
  | Logical ((s, ls), rt) ->
     let s' = Sym.fresh () in
     let rt' = LRT.subst_var {before=s; after=s'} rt in
     bind_logical (add_l s' ls delta) rt'
  | Resource (re, rt) -> bind_logical (add_ur re delta) rt
  | Constraint (lc, rt) -> bind_logical (add_uc lc delta) rt
  | I -> delta

let bind_computational (delta : L.t) (name : Sym.t) (rt : RT.t) : L.t =
  let Computational ((s, bt), rt) = rt in
  let s' = Sym.fresh () in
  let rt' = LRT.subst_var {before = s; after = s'} rt in
  let delta' = add_a name (bt, s') (add_l s' (Base bt) delta) in
  bind_logical delta' rt'
    

let bind (name : Sym.t) (rt : RT.t) : L.t =
  bind_computational L.empty name rt
  
let bind_logically (rt : RT.t) : ((BT.t * Sym.t) * L.t, type_error) m =
  let Computational ((s, bt), rt) = rt in
  let s' = Sym.fresh () in
  let rt' = LRT.subst_var {before = s; after = s'} rt in
  let delta = add_l s' (Base bt) L.empty in
  let delta' = bind_logical delta rt' in
  return ((bt, s'), delta')


(*** auxiliaries **************************************************************)

let ensure_logical_sort (loc : loc) ~(expect : LS.t) (has : LS.t) : (unit, type_error) m =
  if LS.equal has expect 
  then return () 
  else fail loc (Mismatch {has; expect})

let ensure_base_type (loc : loc) ~(expect : BT.t) (has : BT.t) : (unit, type_error) m =
  ensure_logical_sort loc ~expect:(LS.Base expect) (LS.Base has)


let check_computational_bound loc s local = 
  match Local.bound_to s local with
  | None -> fail loc (Unbound_name (Sym s))
  | Some (Computational _) -> return ()
  | Some b -> 
     fail loc (Kind_mismatch {expect = KComputational; has = VB.kind b})

let get_struct_decl loc global tag = 
  let open Global in
  match SymMap.find_opt tag global.struct_decls with
    | Some decl -> return decl
    | None -> fail loc (Missing_struct tag)

let get_member_type loc tag member decl = 
  let open Global in
  match List.assoc_opt Id.equal member decl.members with
  | Some asd -> return asd
  | None -> fail loc (Missing_member (tag, member))



(*** pattern matching *********************************************************)

let pattern_match (loc : loc) (this : IT.t) (pat : pattern) 
                  (expect : BT.t) : (L.t, type_error) m =
  let rec aux (local' : L.t) (this : IT.t) (pat : pattern) 
              (expect : BT.t) : (L.t, type_error) m = 
    match pat with
    | M_Pattern (annots, M_CaseBase (o_s, has_bt)) ->
       let* () = ensure_base_type loc ~expect has_bt in
       let s' = Sym.fresh () in 
       let local' = add_l s' (Base has_bt) local' in
       let* local' = match o_s with
         | Some s when Option.is_some (bound_to s local') -> 
            fail loc (Name_bound_twice (Sym s))
         | Some s -> return (add_a s (has_bt, s') local')
         | None -> return local'
       in
       let local' = add_uc (LC (EQ (this, S s'))) local' in
       return local'
    | M_Pattern (annots, M_CaseCtor (constructor, pats)) ->
       match expect, constructor, pats with
       | expect, (M_Cnil item_bt), [] ->
          let* () = ensure_base_type loc ~expect (List item_bt) in
          return local'
       | _, (M_Cnil item_bt), _ ->
          fail loc (Number_arguments {has = List.length pats; expect = 0})
       | (List item_bt), M_Ccons, [p1; p2] ->
          let* local' = aux local' (Head this) p1 item_bt in
          let* local' = aux local' (Tail this) p2 expect in
          return local'
       | _, M_Ccons, [p1; p2] ->
          let err = 
            !^"cons pattern incompatible with expect type" ^/^ 
              BT.pp false expect 
          in
          fail loc (Generic err)
       | _, M_Ccons, _ -> 
          fail loc (Number_arguments {has = List.length pats; expect = 2})
       | (Tuple bts), M_Ctuple, pats ->
          let rec components local' i pats bts =
            match pats, bts with
            | pat :: pats', bt :: bts' ->
               let* local' = aux local' (Nth (expect, i, this)) pat bt in
               components local' (i+1) pats' bts'
            | [], [] -> 
               return local'
            | _, _ ->
               let expect = i + List.length bts in
               let has = i + List.length pats in
               fail loc (Number_arguments {expect; has})
          in
          components local' 0 pats bts
       | _, M_Ctuple, _ ->
          let err = 
            !^"tuple pattern incompatible with expect type" ^/^ 
              BT.pp false expect
          in
          fail loc (Generic err)
       | _, M_Cspecified, [pat] ->
          aux local' this pat expect
       | _, M_Cspecified, _ ->
          fail loc (Number_arguments {expect = 1; has = List.length pats})
       | _, M_Carray, _ ->
          Debug_ocaml.error "todo: array types"
       | _, M_CivCOMPL, _
       | _, M_CivAND, _
       | _, M_CivOR, _
       | _, M_CivXOR, _
       | _, M_Cfvfromint, _
       | _, M_Civfromfloat, _
         ->
          Debug_ocaml.error "todo: Civ.."
  in
  aux L.empty this pat expect

  
(* The pattern-matching might de-struct 'bt'. For easily making
   constraints carry over to those values, record (lname,bound) as a
   logical variable and record constraints about how the variables
   introduced in the pattern-matching relate to (name,bound). *)
let pattern_match_rt (loc : loc) (pat : pattern) (rt : RT.t) : (L.t, type_error) m =
  let* ((bt, s'), delta) = bind_logically rt in
  let* delta' = pattern_match loc (S s') pat bt in
  return (delta' ++ delta)





(*** function call typing and subtyping ***************************************)

(* Spine is parameterised by RT_Sig, so it can be used both for
   function and label types (which don't have a return type) *)


(* let substs_for_predicate_instantiation loc local definition args = 
 *   let open Global in
 *   let* () = 
 *     let has = List.length definition.arguments in
 *     let expect = List.length args in
 *     if has = expect then return ()
 *     else fail loc (Number_arguments {has; expect})
 *   in
 *   let* substs = 
 *     ListM.mapM (fun (arg, (spec_arg, expected_sort)) ->
 *         return (Subst.{before = spec_arg; after = arg})
 *       ) (List.combine args definition.arguments)
 *   in
 *   return substs *)





type arg = {lname : Sym.t; bt : BT.t; loc : loc}
type args = arg list

let arg_of_sym (loc : loc) (local : L.t) (sym : Sym.t) : (arg, type_error) m = 
  let* () = check_computational_bound loc sym local in
  let (bt,lname) = get_a sym local in
  return {lname; bt; loc}

let arg_of_asym (loc : loc) (local : L.t) (asym : 'bty asym) : (arg, type_error) m = 
  let loc = Loc.update_a loc asym.annot in
  arg_of_sym loc local asym.item

let args_of_asyms (loc : loc) (local : L.t) (asyms : 'bty asyms) : (args, type_error) m = 
  ListM.mapM (arg_of_asym loc local) asyms


let pp_unis (unis : Sym.t Uni.t) : Pp.document = 
 let pp_entry (sym, Uni.{resolved}) =
   match resolved with
   | Some res -> Sym.pp sym ^^^ !^"resolved as" ^^^ Sym.pp res
   | None -> Sym.pp sym ^^^ !^"unresolved"
 in
 Pp.list pp_entry (SymMap.bindings unis)






module Prompt = struct

  type resource_request = 
    { local : Local.t;
      unis : Sym.t Uni.unis;
      situation: situation;
      loc: Loc.t;
      resource : RE.t;
    }

  type packing_request = 
    { local : Local.t;
      situation: situation;
      loc: Loc.t;
      lft : LFT.t;
    }

  type 'a m = 
    | Done of 'a
    | RequestResource of resource_request * ((Sym.t Uni.unis * Local.t) -> 'a m)
    | RequestPacking of packing_request * ((LRT.t * Local.t) -> 'a m)
    | Nondet of ('a m) list * 'a m
    | Error of Locations.t * Tools.stacktrace option * type_error

  module Operators = struct

    let return a = 
      Done a

    let fail loc err = 
      Error (loc, Tools.do_stack_trace (),  err)

    let request_resource loc situation local unis resource =
      RequestResource (
          {loc; local; unis; situation; resource}, 
          fun reply -> Done reply
        )

    let request_packing loc situation local lft =
      RequestPacking (
          {loc; local; situation; lft}, 
          fun reply -> Done reply
        )

    let try_choices choices else_choice = 
      Nondet (choices, else_choice)

    let rec bind m f = 
      match m with
      | Done a -> 
         f a
      | RequestResource (request, c) -> 
         RequestResource (request, fun r -> bind (c r) f)
      | RequestPacking (request, c) -> 
         RequestPacking (request, fun r -> bind (c r) f)
      | Nondet (choices,else_choice) -> 
         Nondet (List.map (fun choice -> bind choice f) choices, bind else_choice f)
      | Error (loc, stacktrace, err) -> 
         Error (loc, stacktrace, err)

    let (let*) = bind

  end

end



module Spine (I : AT.I_Sig) = struct

  module FT = AT.Make(I)
  module NFT = NormalisedArgumentTypes.Make(I)

  let pp_argslocs =
    Pp.list (fun ca -> parens (BT.pp false ca.bt ^/^ bar ^/^ Sym.pp ca.lname))

  open Prompt
  open Prompt.Operators


  let spine (loc : loc) situation  {local; global} 
        (arguments : arg list) (ftyp : FT.t) : (I.t * L.t) m =
    
    let open NFT in
    let ftyp = NFT.normalise ftyp in

    let unis = SymMap.empty in

    let* ftyp_l = 
      let rec check_computational args ftyp = 
        match args, ftyp with
        | (arg :: args), (Computational ((s, bt), ftyp))
             when BT.equal arg.bt bt ->
           let ftyp' = NFT.subst_var {before = s; after = arg.lname} ftyp in
           check_computational args ftyp'
        | (arg :: _), (Computational ((_, bt), _))  ->
           fail arg.loc (Mismatch {has = Base arg.bt; expect = Base bt})
        | [], (L ftyp) -> 
           return ftyp
        | _ -> 
           let expect = NFT.count_computational ftyp in
           let has = List.length arguments in
           fail loc (Number_arguments {expect; has})
      in
      check_computational arguments ftyp 
    in

    let* ((unis, lspec), ftyp_r) = 
      let rec delay_logical (unis, lspec) ftyp =
        match ftyp with
        | Logical ((s, ls), ftyp) ->
           let s' = Sym.fresh () in
           let unis = SymMap.add s' Uni.{resolved = None} unis in
           let ftyp' = NFT.subst_var_l {before = s; after = s'} ftyp in
           delay_logical (unis, lspec @ [(s', ls)]) ftyp'
        | R ftyp -> 
           return ((unis, lspec), ftyp)
      in
      delay_logical (unis, []) ftyp_l
    in

    let* (local, unis, ftyp_c) = 
      let rec infer_resources local unis = function
        | Resource (re, ftyp) -> 
           let* (unis, local) = request_resource loc situation local unis re in
           let new_substs = Uni.find_resolved local unis in
           let ftyp' = NFT.subst_vars_r new_substs ftyp in
           infer_resources local unis ftyp'
        | C ftyp ->
           return (local, unis, ftyp)
      in
      infer_resources local unis ftyp_r
    in

    let () = 
      List.iter (fun (s, ls) ->
          let Uni.{resolved} = SymMap.find s unis in
          match resolved with
          | None -> Debug_ocaml.error ("Unconstrained_logical_variable " ^ Sym.pp_string s)
          | Some sym ->
             if not (LS.equal (get_l sym local) ls) then
               Debug_ocaml.error "type-incorrectly instantiated logical variable"
        ) lspec
    in

    let* rt = 
      let rec check_constraints = function
        | Constraint (c, ftyp) ->
           let (holds, _, s_) = 
             Solver.constraint_holds loc {local; global} false c in
           if holds 
           then check_constraints ftyp 
           else fail loc (Unsat_constraint c)
        | I rt -> 
           return rt
      in
      check_constraints ftyp_c
    in

    return (rt, local)

end

module Spine_FT = Spine(ReturnTypes)
module Spine_LFT = Spine(LogicalReturnTypes)
module Spine_LT = Spine(False)




(*** resource inference *******************************************************)


let rec remove_ownership_prompt (loc: loc) situation {local;global} (pointer: IT.t) (need_size: RE.size) = 
  let open Prompt.Operators in
  if Z.equal need_size Z.zero then 
    return local
  else
    let o_resource = Solver.resource_for_pointer loc {local; global} pointer in
    match o_resource with
    | Some (resource_name, Predicate pred) -> 
       fail loc (Cannot_unpack (pred, situation))
    | Some (resource_name, Uninit {size = have_size; _})
    | Some (resource_name, Padding {size = have_size; _})
    | Some (resource_name, Points {size = have_size; _})
      ->
       if Z.ge_big_int need_size have_size then 
         let local = L.use_resource resource_name [loc] local in
         remove_ownership_prompt loc situation {local; global} (Offset (pointer, Num have_size)) 
           (Z.sub need_size have_size)
       else
         (* if the resource is bigger than needed, keep the remainder
            as unitialised memory *)
         let local = L.use_resource resource_name [loc] local in
         let local = 
           add_ur (RE.Uninit {pointer = Offset (pointer, Num need_size); 
                              size = Z.sub have_size need_size}) local
         in
         return local
    | None -> 
       let olast_used = Solver.used_resource_for_pointer loc {local;global} pointer in
       fail loc (Missing_ownership (None, olast_used, situation))





let rec resource_request_prompt loc situation {local; global} request unis = 
  let open Prompt.Operators in
  let pointer = RE.pointer request in
  match request with
  | Uninit {pointer; size} ->
     let* local = remove_ownership_prompt loc situation {local; global} pointer size in
     return (unis, local)
  | Padding {pointer; size} ->
     let* local = remove_ownership_prompt loc situation {local; global} pointer size in
     return (unis, local)
  | Points {pointer; _} ->
     let o_resource = Solver.resource_for_pointer loc {local; global} pointer in
     begin match o_resource with
     | Some (resource_name, resource) -> 
        begin match RE.unify request (RE.set_pointer resource pointer) unis with
        | Some unis -> 
           let local = use_resource resource_name [loc] local in
           return (unis, local)
        | None -> 
           fail loc (Resource_mismatch {expect = request; has = resource; situation})
        end
     | None -> 
        let olast_used = Solver.used_resource_for_pointer loc {local;global} pointer in
        fail loc (Missing_ownership (None, olast_used, situation))
     end
  | Predicate p ->
     let o_resource = Solver.resource_for_pointer loc {local; global} pointer in
     begin match o_resource with
     | Some (resource_name, resource) -> 
        begin match RE.unify request (RE.set_pointer resource pointer) unis with
        | Some unis -> 
           let local = use_resource resource_name [loc] local in
           return (unis, local)
        | None ->         
           let def = match Global.get_predicate_def loc global p.name with
             | Some def -> def
             | None -> Debug_ocaml.error "missing predicate definition"
           in
           let packing_attempts = 
             List.map (fun clause ->
                 let* (lrt, local) = request_packing loc situation local clause in
                 let local = bind_logical local lrt in
                 resource_request_prompt loc situation {local; global} request unis
               ) (def.pack_functions p.pointer)
           in
           let else_choice = 
             fail loc (Resource_mismatch {expect = request; has = resource; situation}) 
           in
           try_choices packing_attempts else_choice
        end
     | None -> 
        let olast_used = Solver.used_resource_for_pointer loc {local;global} pointer in
        fail loc (Missing_ownership (None, olast_used, situation))
     end



let rec handle_prompt : 'a. Global.t -> 'a Prompt.m -> ('a, type_error) m =
  fun global prompt ->
  match prompt with
  | Prompt.Done a -> 
     return a
  | Prompt.Error (loc,tr,error) -> 
     Error (loc,tr,error)
  | Prompt.RequestResource ({loc; local; unis; situation; resource}, c) ->
     let* (unis, local) = 
       handle_prompt global 
         (resource_request_prompt loc situation {local; global} resource unis) in
     handle_prompt global (c (unis, local))
  | RequestPacking ({loc; local; situation; lft}, c) ->
     let* (lrt, local) = 
       handle_prompt global 
         (Spine_LFT.spine loc situation {local; global} [] lft) in
     handle_prompt global (c (lrt, local))
  | Nondet ([],else_choice) ->
     handle_prompt global else_choice
  | Nondet (choice :: choices, else_choice) ->
     msum (handle_prompt global choice)
       (handle_prompt global (Nondet (choices, else_choice)))





let calltype_ft loc {local; global} args (ftyp : FT.t) : (RT.t * L.t, type_error) m =
  let prompt = Spine_FT.spine loc FunctionCall {local; global} args ftyp in
  let* (rt, local) = handle_prompt global prompt in
  return (rt, local)

let calltype_lt loc {local; global} args (ltyp : LT.t) : (False.t * L.t, type_error) m =
  let prompt = Spine_LT.spine loc LabelCall{local; global} args ltyp in
  let* (rt, local) = handle_prompt global prompt in
  return (rt, local)

(* The "subtyping" judgment needs the same resource/lvar/constraint
   inference as the spine judgment. So implement the subtyping
   judgment 'arg <: RT' by type checking 'f(arg)' for 'f: RT -> False'. *)
let subtype (loc : loc) {local; global} arg (rtyp : RT.t) : (L.t, type_error) m =
  let lt = LT.of_rt rtyp (LT.I False.False) in
  let prompt = Spine_LT.spine loc Subtyping {local; global} [arg] lt in
  let* (False.False, local) = handle_prompt global prompt in
  return local

let remove_ownership (loc: loc) situation {local;global} (pointer: IT.t) (need_size: RE.size) = 
  let prompt = remove_ownership_prompt loc situation {local; global} pointer need_size in
  handle_prompt global prompt




let unpack_resources loc {local; global} = 
  let rec aux local = 
    let* (local, changed) = 
      ListM.fold_leftM (fun (local, changed) (resource_name, resource) ->
          match resource with
          | RE.Predicate p ->
             let def = match Global.get_predicate_def loc global p.name with
               | Some def -> def
               | None -> Debug_ocaml.error "missing predicate definition"
             in
             let* possible_unpackings = 
               ListM.filter_mapM (fun clause ->
                   (* let test_local = L.use_resource resource_name [loc] local in *)
                   let prompt = Spine_LFT.spine loc Unpacking {local = local; global} [] clause in
                   let* (lrt, test_local) = handle_prompt global prompt in
                   let test_local = bind_logical test_local lrt in
                   let is_reachable = Solver.is_consistent loc {local = test_local; global} in
                   return (if is_reachable then Some test_local else None)
                 ) (def.unpack_functions p.pointer)
             in
             begin match possible_unpackings with
             | [] -> Debug_ocaml.error "inconsistent state in every possible resource unpacking"
             | [new_local] -> return (new_local, true)
             | _ -> return (local, changed)
             end
          | _ ->
             return (local, changed)
        ) (local, false) (L.all_resources local)
    in
    if changed then aux local else return local
  in
  aux local

  


(*** pure value inference *****************************************************)

(* these functions return types `{x : bt | phi(x)}` *)
type vt = Sym.t * BT.t * LC.t 

let rt_of_vt (ret,bt,constr) = 
  RT.Computational ((ret, bt), LRT.Constraint (constr, I))


let infer_tuple (loc : loc) {local; global} (args : args) : (vt, type_error) m = 
  let ret = Sym.fresh () in
  let bts = List.map (fun arg -> arg.bt) args in
  let bt = Tuple bts in
  let constrs = 
    List.mapi (fun i arg -> IT.EQ (Nth (bt, i, S ret), S arg.lname)) args 
  in
  return (ret, bt, LC (And constrs))

let infer_constructor (loc : loc) {local; global} (constructor : ctor) 
                      (args : args) : (vt, type_error) m = 
  let ret = Sym.fresh () in
  match constructor, args with
  | M_Ctuple, _ -> 
     infer_tuple loc {local; global} args
  | M_Carray, _ -> 
     Debug_ocaml.error "todo: array types"
  | M_CivCOMPL, _
  | M_CivAND, _
  | M_CivOR, _
  | M_CivXOR, _ 
    -> 
     Debug_ocaml.error "todo: Civ..."
  | M_Cspecified, [arg] ->
     return (ret, arg.bt, LC (EQ (S ret, S arg.lname)))
  | M_Cspecified, _ ->
     fail loc (Number_arguments {has = List.length args; expect = 1})
  | M_Cnil item_bt, [] -> 
     return (ret, List item_bt, LC (EQ (S ret, Nil item_bt)))
  | M_Cnil item_bt, _ -> 
     fail loc (Number_arguments {has = List.length args; expect=0})
  | M_Ccons, [arg1; arg2] -> 
     let* () = ensure_base_type arg2.loc ~expect:(List arg1.bt) arg2.bt in
     let constr = LC (EQ (S ret, Cons (S arg1.lname, S arg2.lname))) in
     return (ret, arg2.bt, constr)
  | M_Ccons, _ ->
     fail loc (Number_arguments {has = List.length args; expect = 2})
  | M_Cfvfromint, _ -> 
     fail loc (Unsupported !^"floats")
  | M_Civfromfloat, _ -> 
     fail loc (Unsupported !^"floats")


let ct_of_ct loc ct = 
  match Sctypes.of_ctype ct with
  | Some ct -> return ct
  | None -> fail loc (Unsupported (!^"ctype" ^^^ CF.Pp_core_ctype.pp_ctype ct))

let infer_ptrval (loc : loc) {local; global} (ptrval : pointer_value) : (vt, type_error) m =
  let ret = Sym.fresh () in
  CF.Impl_mem.case_ptrval ptrval
    ( fun ct -> 
      let* ct = ct_of_ct loc ct in
      let lcs = 
        [IT.Null (S ret);
         IT.Representable (ST_Pointer, S ret);
         (* check: aligned? *)
         IT.Aligned (ST.of_ctype ct, S ret);]
      in
      return (ret, Loc, LC (And lcs)) )
    ( fun sym -> return (ret, FunctionPointer sym, LC (Bool true)) )
    ( fun _prov loc -> return (ret, Loc, LC (EQ (S ret, Pointer loc))) )
    ( fun () -> Debug_ocaml.error "unspecified pointer value" )

let rec infer_mem_value (loc : loc) {local; global} (mem : mem_value) : (vt, type_error) m =
  let open BT in
  CF.Impl_mem.case_mem_value mem
    ( fun ct -> fail loc (Unspecified ct) )
    ( fun _ _ -> 
      fail loc (Unsupported !^"infer_mem_value: concurrent read case") )
    ( fun it iv -> 
      let ret = Sym.fresh () in
      let v = Memory.integer_value_to_num loc iv in
      return (ret, Integer, LC (EQ (S ret, Num v))) )
    ( fun ft fv -> fail loc (Unsupported !^"floats") )
    ( fun _ ptrval -> infer_ptrval loc {local; global} ptrval  )
    ( fun mem_values -> infer_array loc {local; global} mem_values )
    ( fun tag mvals -> 
      let mvals = List.map (fun (member, _, mv) -> (member, mv)) mvals in
      infer_struct loc {local; global} tag mvals )
    ( fun tag id mv -> infer_union loc {local; global} tag id mv )

and infer_struct (loc : loc) {local; global} (tag : tag) 
                 (member_values : (member * mem_value) list) : (vt, type_error) m =
  (* might have to make sure the fields are ordered in the same way as
     in the struct declaration *)
  let ret = Sym.fresh () in
  let* spec = get_struct_decl loc global tag in
  let rec check fields spec =
    match fields, spec with
    | ((member, mv) :: fields), ((smember, (_, sbt)) :: spec) 
         when member = smember ->
       let* constrs = check fields spec in
       let* (s, bt, LC lc) = infer_mem_value loc {local; global} mv in
       let* () = ensure_base_type loc ~expect:sbt bt in
       let this = IT.Member (tag, S ret, member) in
       let constr = IT.subst_it {before = s; after = this} lc in
       return (constrs @ [constr])
    | [], [] -> 
       return []
    | ((id, mv) :: fields), ((smember, sbt) :: spec) ->
       Debug_ocaml.error "mismatch in fields in infer_struct"
    | [], ((member, _) :: _) ->
       fail loc (Generic (!^"field" ^/^ Id.pp member ^^^ !^"missing"))
    | ((member,_) :: _), [] ->
       fail loc (Generic (!^"supplying unexpected field" ^^^ Id.pp member))
  in
  let* constraints = check member_values spec.members in
  return (ret, Struct tag, LC (And constraints))

and infer_union (loc : loc) {local; global} (tag : tag) (id : Id.t) 
                (mv : mem_value) : (vt, type_error) m =
  Debug_ocaml.error "todo: union types"

and infer_array (loc : loc) {local; global} (mem_values : mem_value list) = 
  Debug_ocaml.error "todo: arrays"

let infer_object_value (loc : loc) {local; global} 
                       (ov : 'bty object_value) : (vt, type_error) m =
  match ov with
  | M_OVinteger iv ->
     let ret = Sym.fresh () in
     let i = Memory.integer_value_to_num loc iv in
     return (ret, Integer, LC (EQ (S ret, Num i)))
  | M_OVpointer p -> 
     infer_ptrval loc {local; global} p
  | M_OVarray items ->
     Debug_ocaml.error "todo: arrays"
  | M_OVstruct (tag, fields) -> 
     let mvals = List.map (fun (member,_,mv) -> (member, mv)) fields in
     infer_struct loc {local; global} tag mvals       
  | M_OVunion (tag, id, mv) -> 
     infer_union loc {local; global} tag id mv
  | M_OVfloating iv ->
     fail loc (Unsupported !^"floats")

let infer_value (loc : loc) {local; global} (v : 'bty value) : (vt, type_error) m = 
  match v with
  | M_Vobject ov
  | M_Vloaded (M_LVspecified ov) 
    ->
     infer_object_value loc {local; global} ov
  | M_Vunit ->
     return (Sym.fresh (), Unit, LC (Bool true))
  | M_Vtrue ->
     let ret = Sym.fresh () in
     return (ret, Bool, LC (S ret))
  | M_Vfalse -> 
     let ret = Sym.fresh () in
     return (ret, Bool, LC (Not (S ret)))
  | M_Vlist (ibt, asyms) ->
     let ret = Sym.fresh () in
     let* args = args_of_asyms loc local asyms in
     let* () = 
       ListM.iterM (fun arg -> ensure_base_type loc ~expect:ibt arg.bt) args 
     in
     let its = List.map (fun arg -> IT.S arg.lname) args in
     return (ret, List ibt, LC (EQ (S ret, List (its, ibt))))
  | M_Vtuple asyms ->
     let* args = args_of_asyms loc local asyms in
     infer_tuple loc {local; global} args









(* logic around markers in the environment *)

(* pop_return: "pop" the local environment back until last mark and
   add to `rt` *)
let pop_return (rt : RT.t) (local : L.t) : RT.t * L.t = 
  let (RT.Computational (abinding, lrt)) = rt in
  let rec aux vbs acc = 
    match vbs with
    | [] -> acc
    | (_, VB.Computational _) :: vbs ->
       aux vbs acc
    | (s, VB.Logical ls) :: vbs ->
       let s' = Sym.fresh () in
       let acc = LRT.subst_var {before = s;after = s'} acc in
       aux vbs (LRT.Logical ((s', ls), acc))
    | (_, VB.Resource re) :: vbs ->
       aux vbs (LRT.Resource (re,acc))
    | (_, VB.UsedResource _) :: vbs ->
       aux vbs acc
    | (_, VB.Constraint lc) :: vbs ->
       aux vbs (LRT.Constraint (lc,acc))
  in
  let (new_local, old_local) = since local in
  (RT.Computational (abinding, aux new_local lrt), old_local)

(* pop_empty: "pop" the local environment back until last mark and
   drop the content, while ensuring that it does not contain unused
   resources *)
(* all_empty: do the same for the whole local environment (without
   supplying a marker) *)
let (pop_empty, all_empty) = 
    let rec aux loc = function
      | (s, VB.Resource resource) :: _ -> 
         fail loc (Unused_resource {resource})
      | _ :: rest -> aux loc rest
      | [] -> return ()
    in
  let pop_empty loc local = 
    let (new_local, old_local) = since local in
    let* () = aux loc new_local in
    return old_local
  in
  let all_empty loc local = 
    let new_local = all local in
    let* () = aux loc new_local in
    return ()
  in
  (pop_empty, all_empty)




module Fallible = struct

  (* `t` is used for inferring/checking the type of unreachable control-flow
     positions, including after Run/Goto: Goto has no return type (because the
     control flow does not return there), but instead returns `False`. Type
     checking of pure expressions returns a local environment or `False`; type
     inference of impure expressions returns either a return type and a local
     environment or `False` *)
  type 'a t = 
    | Normal of 'a
    | False

  type 'a fallible = 'a t

  (* bind: check if the monadic argument evaluates to `False`; if so, the value
     is `False, otherwise whatever the continuation (taking a non-False
     argument) returns *)
  let mbind (m : ('a t, 'e) m) (f : 'a -> ('b t, 'e) m) : ('b t, 'e) m =
    let* aof = m in
    match aof with
    | Normal a -> f a
    | False -> return False

  (* special syntax for `or_false` *)
  let (let*?) = mbind

  let pp (ppf : 'a -> Pp.document) (m : 'a t) : Pp.document = 
    match m with
    | Normal a -> ppf a
    | False -> if !unicode then !^"\u{22A5}" else !^"bot"

  let non_false (ms : ('a t) list) : 'a list = 
    List.filter_map (function
        | Normal a -> Some a
        | False -> None
      ) ms

end

open Fallible

(* merging information after control-flow join points  *)

(* note: first argument is the "summarised" return type so far *)
let merge_return_types loc (LC c, rt) (LC c2, rt2) = 
  let RT.Computational ((lname, bt), lrt) = rt in
  let RT.Computational ((lname2, bt2), lrt2) = rt2 in
  let* () = ensure_base_type loc ~expect:bt bt2 in
  let rec aux lrt lrt2 = 
    match lrt, lrt2 with
    | LRT.I, LRT.I -> 
       return LRT.I
    | LRT.Logical ((s, ls), lrt1), _ ->
       let* lrt = aux lrt1 lrt2 in
       return (LRT.Logical ((s, ls), lrt))
    | LRT.Constraint (LC lc, lrt1), _ ->
       let* lrt = aux lrt1 lrt2 in
       return (LRT.Constraint (LC lc, lrt))
    | _, LRT.Logical ((s, ls), lrt2) ->
       let s' = Sym.fresh () in
       let* lrt = aux lrt (LRT.subst_var {before = s; after = s'} lrt2) in
       return (LRT.Logical ((s', ls), lrt))
    | _, Constraint (LC lc, lrt2) ->
       let* lrt = aux lrt lrt2 in
       return (LRT.Constraint (LC (Impl (c2, lc)), lrt))
    | Resource _, _
    | _, Resource _ -> 
       fail loc (Generic !^"Cannot infer type of this (cannot merge)")
  in
  let lrt2' = LRT.subst_var {before = lname2; after = lname} lrt2 in
  let* lrt = aux lrt lrt2' in
  return (LC (Or [c; c2]), RT.Computational ((lname, bt), lrt))


let big_merge_return_types (loc : loc) (name, bt) 
                           (crts : (LC.t * RT.t) list) : (LC.t * RT.t, type_error) m =
  ListM.fold_leftM (merge_return_types loc) 
    (LC.LC (IT.Bool true), RT.Computational ((name, bt), LRT.I)) crts

let merge_paths 
      (loc : loc) 
      (local_or_falses : (L.t fallible) list) : L.t fallible =
  let locals = non_false local_or_falses in
  match locals with
  | [] -> False
  | first :: _ -> 
     (* for every local environment L: merge L L = L *)
     let local = L.big_merge first locals in 
     Normal local

let merge_return_paths
      (loc : loc)
      (rt_local_or_falses : (((LC.t * RT.t) * L.t) fallible) list) 
    : ((RT.t * L.t) fallible, type_error) m =
  let rts_locals = non_false rt_local_or_falses in
  let rts, locals = List.split rts_locals in
  match rts_locals with
  | [] -> return False
  | ((_,RT.Computational (b,_)), first_local) :: _ -> 
     let* (_, rt) = big_merge_return_types loc b rts in 
     let local = L.big_merge first_local locals in 
     let result = (Normal (rt, local)) in
     return result




let false_if_unreachable (loc : loc) {local; global} : (unit fallible, type_error) m =
  let is_reachable = Solver.is_consistent loc {local; global} in
  return (if is_reachable then Normal () else False)


(*** pure expression inference ************************************************)

(* infer_pexpr: the raw type inference logic for pure expressions;
   returns a return type and a "reduced" local environment *)
(* infer_pexpr_pop: place a marker in the local environment, run
   the raw type inference, and return, in addition to what the raw
   inference returns, all logical (logical variables, resources,
   constraints) in the local environment *)

let rec infer_pexpr (loc : loc) {local; global} 
                    (pe : 'bty pexpr) : ((RT.t * L.t) fallible, type_error) m = 
  let (M_Pexpr (annots, _bty, pe_)) = pe in
  let loc = Loc.update_a loc annots in
  debug 3 (lazy (action "inferring pure expression"));
  debug 3 (lazy (item "expr" (pp_pexpr pe)));
  debug 3 (lazy (item "ctxt" (L.pp local)));
  let*? (rt, local) = match pe_ with
    | M_PEsym sym ->
       let ret = Sym.fresh () in
       let* arg = arg_of_sym loc local sym in
       let constr = LC (EQ (S ret, S arg.lname)) in
       let rt = RT.Computational ((ret, arg.bt), Constraint (constr, I)) in
       return (Normal (rt, local))
    | M_PEimpl i ->
       let bt = G.get_impl_constant global i in
       return (Normal (RT.Computational ((Sym.fresh (), bt), I), local))
    | M_PEval v ->
       let* vt = infer_value loc {local; global} v in
       return (Normal (rt_of_vt vt, local))
    | M_PEconstrained _ ->
       Debug_ocaml.error "todo: PEconstrained"
    | M_PEundef (loc2, undef) ->
       let loc = Loc.update loc loc2 in
       let (reachable, model) = 
         Solver.is_reachable_and_model loc {local; global} 
       in
       if not reachable 
       then (Pp.warn !^"unexpected unreachable Undefined"; return False)
       else fail loc (Undefined_behaviour (undef, model))
    | M_PEerror (err, asym) ->
       let* arg = arg_of_asym loc local asym in
       fail arg.loc (StaticError err)
    | M_PEctor (ctor, asyms) ->
       let* args = args_of_asyms loc local asyms in
       let* vt = infer_constructor loc {local; global} ctor args in
       return (Normal (rt_of_vt vt, local))
    | M_PEarray_shift _ ->
       Debug_ocaml.error "todo: PEarray_shift"
    | M_PEmember_shift (asym, tag, member) ->
       let* arg = arg_of_asym loc local asym in
       let* () = ensure_base_type arg.loc ~expect:Loc arg.bt in
       let ret = Sym.fresh () in
       let* decl = get_struct_decl loc global tag in
       let* _member_bt = get_member_type loc tag member decl in
       let shifted_pointer = IT.MemberOffset (tag, S arg.lname, member) in
       let constr = LC (EQ (S ret, shifted_pointer)) in
       let rt = RT.Computational ((ret, Loc), Constraint (constr, I)) in
       return (Normal (rt, local))
    | M_PEnot asym ->
       let* arg = arg_of_asym loc local asym in
       let* () = ensure_base_type arg.loc ~expect:Bool arg.bt in
       let ret = Sym.fresh () in 
       let constr = (LC (EQ (S ret, Not (S arg.lname)))) in
       let rt = RT.Computational ((ret, Bool), Constraint (constr, I)) in
       return (Normal (rt, local))
    | M_PEop (op, asym1, asym2) ->
       let* arg1 = arg_of_asym loc local asym1 in
       let* arg2 = arg_of_asym loc local asym2 in
       let open CF.Core in
       let binop_typ (op : CF.Core.binop) (v1 : IT.t) (v2 : IT.t) =
         let open BT in
         match op with
         | OpAdd -> (((Integer, Integer), Integer), IT.Add (v1, v2))
         | OpSub -> (((Integer, Integer), Integer), IT.Sub (v1, v2))
         | OpMul -> (((Integer, Integer), Integer), IT.Mul (v1, v2))
         | OpDiv -> (((Integer, Integer), Integer), IT.Div (v1, v2))
         | OpRem_t -> (((Integer, Integer), Integer), IT.Rem_t (v1, v2))
         | OpRem_f -> (((Integer, Integer), Integer), IT.Rem_f (v1, v2))
         | OpExp -> (((Integer, Integer), Integer), IT.Exp (v1, v2))
         | OpEq -> (((Integer, Integer), Bool), IT.EQ (v1, v2))
         | OpGt -> (((Integer, Integer), Bool), IT.GT (v1, v2))
         | OpLt -> (((Integer, Integer), Bool), IT.LT (v1, v2))
         | OpGe -> (((Integer, Integer), Bool), IT.GE (v1, v2))
         | OpLe -> (((Integer, Integer), Bool), IT.LE (v1, v2))
         | OpAnd -> (((Bool, Bool), Bool), IT.And [v1; v2])
         | OpOr -> (((Bool, Bool), Bool), IT.Or [v1; v2])
       in
       let (((ebt1, ebt2), rbt), result_it) = 
         binop_typ op (S arg1.lname) (S arg2.lname) 
       in
       let* () = ensure_base_type arg1.loc ~expect:ebt1 arg1.bt in
       let* () = ensure_base_type arg2.loc ~expect:ebt2 arg2.bt in
       let ret = Sym.fresh () in
       let constr = LC (EQ (S ret, result_it)) in
       let rt = RT.Computational ((ret, rbt), Constraint (constr, I)) in
       return (Normal (rt, local))
    | M_PEstruct _ ->
       Debug_ocaml.error "todo: PEstruct"
    | M_PEunion _ ->
       Debug_ocaml.error "todo: PEunion"
    | M_PEmemberof _ ->
       Debug_ocaml.error "todo: M_PEmemberof"
    | M_PEcall (called, asyms) ->
       let* decl_typ = match called with
         | CF.Core.Impl impl -> 
            return (G.get_impl_fun_decl global impl )
         | CF.Core.Sym sym -> 
            let* (_, t) = match G.get_fun_decl global sym with
              | Some t -> return t
              | None -> fail loc (Missing_function sym)
            in
            return t
       in
       let* args = args_of_asyms loc local asyms in
       let* (rt, local) = calltype_ft loc {local; global} args decl_typ in
       return (Normal (rt, local))
    | M_PElet (p, e1, e2) ->
       let*? (rt, local) = infer_pexpr loc {local; global} e1 in
       let* delta = match p with
         | M_Symbol sym -> return (bind sym rt)
         | M_Pat pat -> pattern_match_rt loc pat rt
       in
       infer_pexpr_pop loc delta {local; global} e2
    | M_PEcase _ -> Debug_ocaml.error "PEcase in inferring position"
    | M_PEif (casym, e1, e2) ->
       let* carg = arg_of_asym loc local casym in
       let* () = ensure_base_type carg.loc ~expect:Bool carg.bt in
       let* paths =
         ListM.mapM (fun (lc, e) ->
             let delta = add_uc lc L.empty in
             let*? () = false_if_unreachable loc {local = delta ++ local; global} in
             let*? (rt, local) = infer_pexpr_pop loc delta {local; global} e in
             return (Normal ((lc, rt), local))
           ) [(LC (S carg.lname), e1); (LC (Not (S carg.lname)), e2)]
       in
       merge_return_paths loc paths
  in  
  debug 3 (lazy (item "type" (RT.pp rt)));
  return (Normal (rt, local))

and infer_pexpr_pop (loc : loc) delta {local; global} 
                    (pe : 'bty pexpr) : ((RT.t * L.t) fallible, type_error) m = 
  let local = delta ++ marked ++ local in 
  let*? (rt, local) = infer_pexpr loc {local; global} pe in
  return (Normal (pop_return rt local))


(* check_pexpr: type check the pure expression `e` against return type
   `typ`; returns a "reduced" local environment *)

let rec check_pexpr (loc : loc) {local; global} (e : 'bty pexpr) 
                    (typ : RT.t) : (L.t fallible, type_error) m = 
  let (M_Pexpr (annots, _, e_)) = e in
  let loc = Loc.update_a loc annots in
  debug 3 (lazy (action "checking pure expression"));
  debug 3 (lazy (item "expr" (group (pp_pexpr e))));
  debug 3 (lazy (item "type" (RT.pp typ)));
  debug 3 (lazy (item "ctxt" (L.pp local)));
  match e_ with
  | M_PEif (casym, e1, e2) ->
     let* carg = arg_of_asym loc local casym in
     let* () = ensure_base_type carg.loc ~expect:Bool carg.bt in
     let* paths =
       ListM.mapM (fun (lc, e) ->
           let delta = add_uc lc L.empty in
           let*? () = 
             false_if_unreachable loc {local = delta ++ local; global} 
           in
           check_pexpr_pop loc delta {local; global} e typ
         ) [(LC (S carg.lname), e1); (LC (Not (S carg.lname)), e2)]
     in
     return (merge_paths loc paths)
  | M_PEcase (asym, pats_es) ->
     let* arg = arg_of_asym loc local asym in
     let* paths = 
       ListM.mapM (fun (pat, pe) ->
           (* TODO: make pattern matching return (in delta)
              constraints corresponding to the pattern *)
           let* delta = pattern_match arg.loc (S arg.lname) pat arg.bt in
           let*? () = 
             false_if_unreachable loc {local = delta ++ local;global} 
           in
           check_pexpr_pop loc delta {local; global} e typ
         ) pats_es
     in
     return (merge_paths loc paths)
  | M_PElet (p, e1, e2) ->
     let*? (rt, local) = infer_pexpr loc {local; global} e1 in
     let* delta = match p with
       | M_Symbol sym -> return (bind sym rt)
       | M_Pat pat -> pattern_match_rt loc pat rt
     in
     check_pexpr_pop loc delta {local; global} e2 typ
  | _ ->
     let*? (rt, local) = infer_pexpr loc {local; global} e in
     let* ((bt, lname), delta) = bind_logically rt in
     let local = delta ++ marked ++ local in
     let* local = subtype loc {local; global} {bt; lname; loc} typ in
     let* local = pop_empty loc local in
     return (Normal local)

and check_pexpr_pop (loc : loc) delta {local; global} (pe : 'bty pexpr) 
                    (typ : RT.t) : (L.t fallible, type_error) m =
  let local = delta ++ marked ++ local in 
  let*? local = check_pexpr loc {local; global} pe typ in
  let* local = pop_empty loc local in
  return (Normal local)




(*** memory related logic *****************************************************)


  
let load (loc: loc) {local;global} (bt: BT.t) (pointer: IT.t)
         (size: RE.size) (return_it: IT.t) (is_field: BT.member option) =
  let rec aux {local;global} bt pointer size path is_field = 
    match bt with
    | Struct tag ->
       let* decl = get_struct_decl loc global tag in
       let rec aux_members = function
         | (member,(member_ct,member_bt))::members ->
            let member_pointer = IT.MemberOffset (tag,pointer,member) in
            let member_path = IT.Member (tag, path, member) in
            let* constraints = aux_members members in
            let* constraints2 = 
              aux {local;global} member_bt member_pointer 
                (Memory.size_of_ctype loc member_ct) member_path (Some member) 
            in
            return (constraints2 @ constraints)
         | [] -> return []
       in  
       aux_members decl.members
    | _ ->
       let o_resource = Solver.resource_for_pointer loc {local;global} pointer in
       let* pointee = match o_resource with
         | Some (_,resource) -> 
            begin match resource with
            | Points p when Z.equal size p.size -> return p.pointee
            | Points p -> fail loc (Generic !^"resouce of wrong size for load")
            | Uninit _ -> fail loc (Uninitialised is_field)
            | Padding _ -> fail loc (Generic !^"cannot read padding bytes")
            | Predicate pred -> fail loc (Cannot_unpack (pred, Access Load))
            end
         | None -> 
            let olast_used = Solver.used_resource_for_pointer loc {local;global} pointer in
            fail loc (Missing_ownership (is_field, olast_used, Access Load))
       in
       let vls = L.get_l pointee local in
       if LS.equal vls (Base bt) 
       then return [IT.EQ (path, S pointee)]
       else fail loc (Mismatch {has = vls; expect = Base bt})
  in
  let* constraints = aux {local; global} bt pointer size return_it is_field in
  return (LC (And constraints))



(* does not check for the right to write, this is done elsewhere *)
let rec store (loc: loc)
              {local;global}
              (bt: BT.t)
              (pointer: IT.t)
              (size: RE.size)
              (o_value: IT.t option) 
  =
  let open LRT in
  match bt with
  | Struct tag ->
     let* decl = get_struct_decl loc global tag in
     let rec aux = function
       | [] -> return I
       | (member,(member_ct,member_bt))::members ->
          let member_pointer = IT.MemberOffset (tag,pointer,member) in
          let member_size = Memory.size_of_ctype loc member_ct in
          let o_member_value = Option.map (fun v -> IT.Member (tag, v, member)) o_value in
          let* rt = aux members in
          let* rt2 = store loc {local;global} member_bt member_pointer 
                              member_size o_member_value in
          return (rt@@rt2)
     in  
     aux decl.members
  | _ -> 
     let vsym = Sym.fresh () in 
     match o_value with
       | Some v -> 
          let rt = 
            Logical ((vsym, Base bt), 
            Resource (Points {pointer; pointee = vsym; size}, 
            Constraint (LC (EQ (S vsym, v)), I)))
          in
          return rt
       | None -> 
          return (Resource (Uninit {pointer; size}, I))



(* not used right now *)
(* todo: right access kind *)
let pack_stored_struct loc {local; global} (pointer: IT.t) (tag: BT.tag) =
  let size = Memory.size_of_struct loc tag in
  let v = Sym.fresh () in
  let bt = Struct tag in
  let* constraints = load loc {local; global} (Struct tag) pointer size (S v) None in
  let* local = remove_ownership loc (Access Load) {local; global} pointer size in
  let rt = 
    LRT.Logical ((v, Base bt), 
    LRT.Resource (Points {pointer; pointee = v; size},
    LRT.Constraint (constraints, LRT.I)))
  in
  return rt




let ensure_aligned loc {local; global} access pointer ctype = 
  let (aligned, _, _) = 
    Solver.constraint_holds loc {local; global} false
      (LC.LC (Aligned (ST.of_ctype ctype, pointer))) 
  in
  if aligned then return () else fail loc (Misaligned access)






(*** impure expression inference **********************************************)


(* type inference of impure expressions; returns either a return type
   and new local environment or False *)
(* infer_expr: the raw type inference for impure expressions. *)
(* infer_expr_pop: analogously to infer_pexpr: place a marker, run
   the raw type inference, and additionally return whatever is left in
   the local environment since that marker (except for computational
   variables) *)


let rec infer_expr (loc : loc) {local; labels; global} 
                   (e : 'bty expr) : ((RT.t * L.t) fallible, type_error) m = 
  let (M_Expr (annots, e_)) = e in
  let loc = Loc.update_a loc annots in
  debug 3 (lazy (action "inferring expression"));
  debug 3 (lazy (item "expr" (group (pp_expr e))));
  debug 3 (lazy (item "ctxt" (L.pp local)));
  let* r = match e_ with
    | M_Epure pe -> 
       infer_pexpr loc {local; global} pe
    | M_Ememop memop ->
       let* local = unpack_resources loc {local; global} in
       begin match memop with
       | M_PtrEq _ (* (asym 'bty * asym 'bty) *)
       | M_PtrNe _ (* (asym 'bty * asym 'bty) *)
       | M_PtrLt _ (* (asym 'bty * asym 'bty) *)
       | M_PtrGt _ (* (asym 'bty * asym 'bty) *)
       | M_PtrLe _ (* (asym 'bty * asym 'bty) *)
       | M_PtrGe _ (* (asym 'bty * asym 'bty) *)
       | M_Ptrdiff _ (* (actype 'bty * asym 'bty * asym 'bty) *)
       | M_IntFromPtr _ (* (actype 'bty * asym 'bty) *)
       | M_PtrFromInt _ (* (actype 'bty * asym 'bty) *)
         -> 
          Debug_ocaml.error "todo: ememop"
       | M_PtrValidForDeref (act, asym) ->
          (* check *)
          let* local = unpack_resources loc {local; global} in
          let* arg = arg_of_asym loc local asym in
          let ret = Sym.fresh () in
          let size = Memory.size_of_ctype loc act.item.ct in
          let* () = ensure_base_type arg.loc ~expect:Loc arg.bt in
          let o_resource = 
            Solver.resource_for_pointer loc {local; global} (S arg.lname)
          in
          let resource_ok = 
            match Option.bind o_resource (Tools.comp RE.size snd) with
            | Some size' when Z.equal size' size -> true
            | _ -> false
          in
          let (aligned, _, s_) = 
            Solver.constraint_holds loc {local; global} false
              (LC.LC (Aligned (ST.of_ctype act.item.ct, S arg.lname))) 
          in
          let ok = resource_ok && aligned in
          let constr = LC (EQ (S ret, Bool ok)) in
          let rt = RT.Computational ((ret, Bool), Constraint (constr, I)) in
          return (Normal (rt, local))
       | M_PtrWellAligned _ (* (actype 'bty * asym 'bty  ) *)
       | M_PtrArrayShift _ (* (asym 'bty * actype 'bty * asym 'bty  ) *)
       | M_Memcpy _ (* (asym 'bty * asym 'bty * asym 'bty) *)
       | M_Memcmp _ (* (asym 'bty * asym 'bty * asym 'bty) *)
       | M_Realloc _ (* (asym 'bty * asym 'bty * asym 'bty) *)
       | M_Va_start _ (* (asym 'bty * asym 'bty) *)
       | M_Va_copy _ (* (asym 'bty) *)
       | M_Va_arg _ (* (asym 'bty * actype 'bty) *)
       | M_Va_end _ (* (asym 'bty) *) 
         -> 
          Debug_ocaml.error "todo: ememop"
       end
    | M_Eaction (M_Paction (_pol, M_Action (aloc, action_))) ->
       let* local = unpack_resources loc {local; global} in
       begin match action_ with
       | M_Create (asym, act, _prefix) -> 
          let* arg = arg_of_asym loc local asym in
          let* () = ensure_base_type arg.loc ~expect:Integer arg.bt in
          let ret = Sym.fresh () in
          let size = Memory.size_of_ctype loc act.item.ct in
          let* lrt = store loc {local; global} act.item.bt (S ret) size None in
          let rt = 
            RT.Computational ((ret, Loc), 
            LRT.Constraint (LC.LC (Representable (ST_Pointer, S ret)), 
            LRT.Constraint (LC.LC (AlignedI (S arg.lname, S ret)), 
            (* RT.Constraint (LC.LC (EQ (AllocationSize (S ret), Num size)), *)
            lrt)))
          in
          return (Normal (rt, local))
       | M_CreateReadOnly (sym1, ct, sym2, _prefix) -> 
          Debug_ocaml.error "todo: CreateReadOnly"
       | M_Alloc (ct, sym, _prefix) -> 
          Debug_ocaml.error "todo: Alloc"
       | M_Kill (M_Dynamic, asym) -> 
          Debug_ocaml.error "todo: free"
       | M_Kill (M_Static cti, asym) -> 
          let* arg = arg_of_asym loc local asym in
          let* () = ensure_base_type arg.loc ~expect:Loc arg.bt in
          let* () = 
            ensure_aligned loc {local; global} Kill (S arg.lname) cti.ct
          in
          let size = Memory.size_of_ctype loc cti.ct in
          let* local = remove_ownership loc (Access Kill) {local; global} (S arg.lname) size in
          let rt = RT.Computational ((Sym.fresh (), Unit), I) in
          return (Normal (rt, local))
       | M_Store (_is_locking, act, pasym, vasym, mo) -> 
          let* parg = arg_of_asym loc local pasym in
          let* varg = arg_of_asym loc local vasym in
          let* () = ensure_base_type loc ~expect:act.item.bt varg.bt in
          let* () = ensure_base_type loc ~expect:Loc parg.bt in
          let* () = 
            ensure_aligned loc {local; global} Store (S parg.lname) act.item.ct
          in
          (* The generated Core program will in most cases before this
             already have checked whether the store value is
             representable and done the right thing. Pointers, as I
             understand, are an exception. *)
          let* () = 
            let (in_range, _, _) = 
              Solver.constraint_holds loc {local; global} false 
                (LC (Representable (ST.of_ctype act.item.ct, S varg.lname)))
            in
            if in_range then return () else
              fail loc (Generic !^"write value unrepresentable")
          in
          let size = Memory.size_of_ctype loc act.item.ct in
          let* local = 
            remove_ownership parg.loc (Access Store) {local; global} (S parg.lname) size in
          let* bindings = 
            store loc {local; global} varg.bt (S parg.lname) 
              size (Some (S varg.lname)) in
          let rt = RT.Computational ((Sym.fresh (), Unit), bindings) in
          return (Normal (rt, local))
       | M_Load (act, pasym, _mo) -> 
          let* parg = arg_of_asym loc local pasym in
          let* () = ensure_base_type loc ~expect:Loc parg.bt in
          let* () = 
            ensure_aligned loc {local; global} Load (S parg.lname) act.item.ct
          in
          let ret = Sym.fresh () in
          let size = Memory.size_of_ctype loc act.item.ct in
          let* constraints = 
            load loc {local; global} act.item.bt (S parg.lname) size (S ret) None 
          in
          let rt = RT.Computational ((ret, act.item.bt), Constraint (constraints, LRT.I)) in
          return (Normal (rt, local))
       | M_RMW (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: RMW"
       | M_Fence mo -> 
          Debug_ocaml.error "todo: Fence"
       | M_CompareExchangeStrong (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: CompareExchangeStrong"
       | M_CompareExchangeWeak (ct, sym1, sym2, sym3, mo1, mo2) -> 
          Debug_ocaml.error "todo: CompareExchangeWeak"
       | M_LinuxFence mo -> 
          Debug_ocaml.error "todo: LinuxFemce"
       | M_LinuxLoad (ct, sym1, mo) -> 
          Debug_ocaml.error "todo: LinuxLoad"
       | M_LinuxStore (ct, sym1, sym2, mo) -> 
          Debug_ocaml.error "todo: LinuxStore"
       | M_LinuxRMW (ct, sym1, sym2, mo) -> 
          Debug_ocaml.error "todo: LinuxRMW"
       end
    | M_Eskip -> 
       let rt = RT.Computational ((Sym.fresh (), Unit), I) in
       return (Normal (rt, local))
    | M_Eccall (_ctype, afsym, asyms) ->
       let* local = unpack_resources loc {local; global} in
       let* f_arg = arg_of_asym loc local afsym in
       let* args = args_of_asyms loc local asyms in
       begin match f_arg.bt with
         | FunctionPointer sym -> 
            let* (_loc, ft) = match G.get_fun_decl global sym with
              | Some (loc, ft) -> return (loc, ft)
              | None -> fail loc (Missing_function sym)
            in
            let* (rt, local) = calltype_ft loc {local; global} args ft in
            return (Normal (rt, local))
         | _ -> 
            fail (Loc.update_a loc afsym.annot) 
              (Generic !^"expected function pointer")
       end
    | M_Eproc (fname, asyms) ->
       let* local = unpack_resources loc {local; global} in
       let* decl_typ = match fname with
         | CF.Core.Impl impl -> 
            return (G.get_impl_fun_decl global impl)
         | CF.Core.Sym sym ->
            let* (_loc, decl_typ) = match G.get_fun_decl global sym with
              | Some (loc, ft) -> return (loc, ft)
              | None -> fail loc (Missing_function sym)
            in
            return decl_typ
       in
       let* args = args_of_asyms loc local asyms in
       let* (rt, local) = calltype_ft loc {local; global} args decl_typ in
       return (Normal (rt, local))
    | M_Ebound (n, e) ->
       infer_expr loc {local; labels; global} e
    | M_End _ ->
       Debug_ocaml.error "todo: End"
    | M_Erun (label_sym, asyms) ->
       let* local = unpack_resources loc {local; global} in
       let* lt = match SymMap.find_opt label_sym labels with
       | None -> fail loc (Generic (!^"undefined label" ^/^ Sym.pp label_sym))
       | Some lt -> return lt
       in
       let* args = args_of_asyms loc local asyms in
       let* (False, local) = calltype_lt loc {local; global} args lt in
       let* () = all_empty loc local in
       return False
    | M_Ecase _ -> 
       Debug_ocaml.error "Ecase in inferring position"
    | M_Eif (casym, e1, e2) ->
       let* carg = arg_of_asym loc local casym in
       let* () = ensure_base_type carg.loc ~expect:Bool carg.bt in
       let* paths =
         ListM.mapM (fun (lc, e) ->
             let delta = add_uc lc L.empty in
             let*? () = 
               false_if_unreachable loc {local = delta ++ local; global} 
             in
             let*? (rt, local) = infer_expr_pop loc delta {local; labels; global} e in
             return (Normal ((lc, rt), local))
           ) [(LC (S carg.lname), e1); (LC (Not (S carg.lname)), e2)]
       in
       merge_return_paths loc paths
    | M_Elet (p, e1, e2) ->
       let*? (rt, local) = infer_pexpr loc {local; global} e1 in
       let* delta = match p with
         | M_Symbol sym -> return (bind sym rt)
         | M_Pat pat -> pattern_match_rt loc pat rt
       in
       infer_expr_pop loc delta {local; labels; global} e2
    | M_Ewseq (pat, e1, e2)      (* for now, the same as Esseq *)
    | M_Esseq (pat, e1, e2) ->
       let*? (rt, local) = infer_expr loc {local; labels; global} e1 in
       let* delta = pattern_match_rt loc pat rt in
       infer_expr_pop loc delta {local; labels; global} e2
  in
  debug 3 (lazy (match r with
                    | False -> item "type" (parens !^"no return")
                    | Normal (rt,_) -> item "type" (RT.pp rt)));
  return r

and infer_expr_pop (loc : loc) delta {local; labels; global} 
                   (e : 'bty expr) : ((RT.t * L.t) fallible, type_error) m =
  let local = delta ++ marked ++ local in 
  let*? (rt, local) = infer_expr loc {local; labels; global} e in
  return (Normal (pop_return rt local))

(* check_expr: type checking for impure epressions; type checks `e`
   against `typ`, which is either a return type or `False`; returns
   either an updated environment, or `False` in case of Goto *)
let rec check_expr (loc : loc) {local; labels; global} (e : 'bty expr) 
                   (typ : RT.t fallible) : (L.t fallible, type_error) m = 
  let (M_Expr (annots, e_)) = e in
  let loc = Loc.update_a loc annots in
  debug 3 (lazy (action "checking expression"));
  debug 3 (lazy (item "expr" (group (pp_expr e))));
  debug 3 (lazy (item "type" (Fallible.pp RT.pp typ)));
  debug 3 (lazy (item "ctxt" (L.pp local)));
  match e_ with
  | M_Eif (casym, e1, e2) ->
     let* carg = arg_of_asym loc local casym in
     let* () = ensure_base_type carg.loc ~expect:Bool carg.bt in
     let* paths =
       ListM.mapM (fun (lc, e) ->
           let delta = add_uc lc L.empty in
           let*? () = 
             false_if_unreachable loc {local = delta ++ local; global} 
           in
           check_expr_pop loc delta {local; labels; global} e typ 
         ) [(LC (S carg.lname), e1); (LC (Not (S carg.lname)), e2)]
     in
     return (merge_paths loc paths)
  | M_Ecase (asym, pats_es) ->
     let* arg = arg_of_asym loc local asym in
     let* paths = 
       ListM.mapM (fun (pat, pe) ->
           (* TODO: make pattern matching return (in delta)
              constraints corresponding to the pattern *)
           let* delta = pattern_match arg.loc (S arg.lname) pat arg.bt in
           let*? () = 
             false_if_unreachable loc {local = delta ++ local; global} 
           in
           check_expr_pop loc delta {local; labels; global} e typ
         ) pats_es
     in
     return (merge_paths loc paths)
  | M_Elet (p, e1, e2) ->
     let*? (rt, local) = infer_pexpr loc {local; global} e1 in
     let* delta = match p with 
       | M_Symbol sym -> return (bind sym rt)
       | M_Pat pat -> pattern_match_rt loc pat rt
     in
     check_expr_pop loc delta {local; labels; global} e2 typ
  | M_Ewseq (pat, e1, e2)      (* for now, the same as Esseq *)
  | M_Esseq (pat, e1, e2) ->
     let*? (rt, local) = infer_expr loc {local; labels; global} e1 in
     let* delta = pattern_match_rt loc pat rt in
     check_expr_pop loc delta {local; labels; global} e2 typ
  | _ ->
     let*? (rt, local) = infer_expr loc {local; labels; global} e in
     let* ((bt, lname), delta) = bind_logically rt in
     let local = delta ++ marked ++ local in
     match typ with
     | Normal typ ->
        let* local = subtype loc {local; global} {bt; lname; loc} typ in
        let* local = pop_empty loc local in
        return (Normal local)
     | False ->
        let err = 
          !^"This expression returns but is expected" ^/^
            !^"to have noreturn-type." 
        in
        fail loc (Generic err)

and check_expr_pop (loc : loc) delta {labels; local; global} (pe : 'bty expr) 
                   (typ : RT.t fallible) : (L.t fallible, type_error) m =
  let local = delta ++ marked ++ local in 
  let*? local = check_expr loc {labels; local; global} pe typ in
  let* local = pop_empty loc local in
  return (Normal local)


(* check_and_bind_arguments: typecheck the function/procedure/label
   arguments against its specification; returns
   1. the return type, or False, to type check the body against,
   2. a local environment binding the arguments,
   3. a local environment binding only the computational and logical
      arguments (for use when type checking a procedure, to include those 
      arguments in the environment for type checking the labels),
   4. the substitutions of concrete arguments for the specification's
      type variables (this is used for instantiating those type variables
      in label specifications in the function body when type checking a
      procedure. *)
(* the logic is parameterised by RT_Sig so it can be used uniformly
   for functions and procedures (with return type) and labels with
   no-return (False) type. *)
module CBF (I : AT.I_Sig) = struct
  module T = AT.Make(I)
  let check_and_bind_arguments loc arguments (function_typ : T.t) = 
    let rec check acc_substs local pure_local args (ftyp : T.t) =
      match args, ftyp with
      | ((aname,abt) :: args), (T.Computational ((lname, sbt), ftyp))
           when BT.equal abt sbt ->
         (* let new_lname = Sym.fresh_relative aname (fun s -> s^"^") in *)
         let new_lname = Sym.fresh () in
         let subst = Subst.{before=lname;after=new_lname} in
         let ftyp' = T.subst_var subst ftyp in
         let local = add_l new_lname (Base abt) local in
         let local = add_a aname (abt,new_lname) local in
         let pure_local = add_l new_lname (Base abt) pure_local in
         let pure_local = add_a aname (abt,new_lname) pure_local in
         check (acc_substs@[subst]) local pure_local args ftyp'
      | ((aname, abt) :: args), (T.Computational ((sname, sbt), ftyp)) ->
         fail loc (Mismatch {has = (Base abt); expect = Base sbt})
      | [], (T.Computational (_,_))
      | (_ :: _), (T.I _) ->
         let expect = T.count_computational function_typ in
         let has = List.length arguments in
         fail loc (Number_arguments {expect; has})
      | args, (T.Logical ((sname, sls), ftyp)) ->
         let new_lname = Sym.fresh_same sname in
         let subst = Subst.{before = sname; after = new_lname} in
         let ftyp' = T.subst_var subst ftyp in
         let local = add_l new_lname sls local in
         let pure_local = add_l new_lname sls pure_local in
         check (acc_substs@[subst]) local pure_local args ftyp'
      | args, (T.Resource (re, ftyp)) ->
         check acc_substs (add_ur re local) pure_local args ftyp
      | args, (T.Constraint (lc, ftyp)) ->
         let cname = Sym.fresh () in
         let local = add_c cname lc local in
         let pure_local = add_c cname lc pure_local in
         check acc_substs local pure_local args ftyp
      | [], (T.I rt) ->
         return (rt, local, pure_local, acc_substs)
    in
    check [] L.empty L.empty arguments function_typ
end

module CBF_FT = CBF(ReturnTypes)
module CBF_LT = CBF(False)


let check_initial_environment_consistent loc info {local;global} =
  match Solver.is_consistent loc {local; global}, info with
  | true, _ -> 
     return ()
  | false, `Label -> 
     fail loc (Generic (!^"this label makes inconsistent assumptions"))
  | false, `Fun -> 
     fail loc (Generic (!^"this function makes inconsistent assumptions"))


(* check_function: type check a (pure) function *)
let check_function (loc : loc) (global : Global.t) (fsym : Sym.t) 
                   (arguments : (Sym.t * BT.t) list) (rbt : BT.t) 
                   (body : 'bty pexpr) (function_typ : FT.t) : (unit, type_error) m =
  debug 2 (lazy (headline ("checking function " ^ Sym.pp_string fsym)));
  let* (rt, delta, _, _substs) = 
    CBF_FT.check_and_bind_arguments loc arguments function_typ 
  in
  let* () = check_initial_environment_consistent loc `Fun
              {local = delta; global}  
  in
  (* rbt consistency *)
  let* () = 
    let Computational ((sname, sbt), t) = rt in
    ensure_base_type loc ~expect:sbt rbt
  in
  let* local_or_false = 
    check_pexpr_pop loc delta {local = L.empty; global} body rt 
  in
  return ()


(* check_procedure: type check an (impure) procedure *)
let check_procedure (loc : loc) (global : Global.t) (fsym : Sym.t)
                    (arguments : (Sym.t * BT.t) list) (rbt : BT.t) 
                    (body : 'bty expr) (function_typ : FT.t) 
                    (label_defs : 'bty label_defs) : (unit, type_error) m =
  debug 2 (lazy (headline ("checking procedure " ^ Sym.pp_string fsym)));
  let* (rt, delta, pure_delta, substs) = 
    CBF_FT.check_and_bind_arguments loc arguments function_typ 
  in
  let* () = check_initial_environment_consistent loc `Fun
              {local = delta; global}  
  in
  (* rbt consistency *)
  let* () = 
    let Computational ((sname, sbt), t) = rt in
    ensure_base_type loc ~expect:sbt rbt
  in
  let label_defs = 
    Pmap.mapi (fun lsym def ->
        match def with
        | M_Return lt -> 
           let lt = LT.subst_vars substs lt in
           let () = debug 3 (lazy (item (plain (Sym.pp lsym)) (LT.pp lt))) in
           M_Return lt
        | M_Label (lt, args, body, annots) -> 
           let lt = LT.subst_vars substs lt in
           let () = debug 3 (lazy (item (plain (Sym.pp lsym)) (LT.pp lt))) in
           M_Label (lt, args, body, annots)
      ) label_defs 
  in
  let* labels = 
    PmapM.foldM (fun sym def acc ->
        match def with
        | M_Return lt
        | M_Label (lt, _, _, _) -> 
           let* () = 
             WellTyped.WLT.welltyped loc {local = pure_delta; global} lt
           in
           return (SymMap.add sym lt acc)
      ) label_defs SymMap.empty 
  in
  let check_label lsym def () = 
    match def with
    | M_Return lt ->
       return ()
    | M_Label (lt, args, body, annots) ->
       debug 2 (lazy (headline ("checking label " ^ Sym.pp_string lsym)));
       debug 3 (lazy (item "type" (LT.pp lt)));
       let* (rt, delta_label, _, _) = 
         CBF_LT.check_and_bind_arguments loc args lt 
       in
       let* () = check_initial_environment_consistent loc `Label
                   {local = delta; global}  
       in
       let* local_or_false = 
         check_expr_pop loc (delta_label ++ pure_delta) 
           {local = L.empty; labels; global} body False
       in
       return ()
  in
  let* () = PmapM.foldM check_label label_defs () in
  debug 2 (lazy (headline ("checking function body " ^ Sym.pp_string fsym)));
  let* local_or_false = 
    check_expr_pop loc delta 
      {local = L.empty; labels; global} body (Normal rt)
  in
  return ()






                             
(* TODO: 
   - make wellformedness checks check for things being of the right kind
   - separate everywhere separate internal from user errors
   - especially for when *trying* different clauses of predicates: only accept failures of particular kind
   - in counter models, do not use 0 for non-null pointers
   - give types for standard library functions
   - better location information for refined_c annotations
   - fix Ecase "LC (Bool true)"
   - constrain return type shape, maybe also function type shape
 *)
