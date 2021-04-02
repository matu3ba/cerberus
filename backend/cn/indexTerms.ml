open Subst
open List
open Pp
module BT=BaseTypes
module CT = Sctypes
module CF=Cerb_frontend
module SymSet = Set.Make(Sym)
module SymMap = Map.Make(Sym)


type lit = 
  | Sym of Sym.t
  | Z of Z.t
  | Q of int * int
  | Pointer of Z.t
  | Bool of bool
  | Unit
  | Default of BT.t

(* over integers and reals *)
type 'bt arith_op =
  | Add of 'bt term * 'bt term
  | Sub of 'bt term * 'bt term
  | Mul of 'bt term * 'bt term
  | Div of 'bt term * 'bt term
  | Exp of 'bt term * 'bt term
  | Rem_t of 'bt term * 'bt term
  | Rem_f of 'bt term * 'bt term
  | Min of 'bt term * 'bt term
  | Max of 'bt term * 'bt term

(* over integers and reals *)
and 'bt cmp_op =
  | LT of 'bt term * 'bt term
  | GT of 'bt term * 'bt term
  | LE of 'bt term * 'bt term
  | GE of 'bt term * 'bt term

and 'bt bool_op = 
  | And of 'bt term list
  | Or of 'bt term list
  | Impl of 'bt term * 'bt term
  | Not of 'bt term
  | ITE of 'bt term * 'bt term * 'bt term
  | EQ of 'bt term * 'bt term
  | NE of 'bt term * 'bt term

and 'bt tuple_op = 
  | Tuple of 'bt term list
  | NthTuple of int * 'bt term

and 'bt struct_op =
  | Struct of BT.tag * (BT.member * 'bt term) list
  | StructMember of BT.tag * 'bt term * BT.member
  | StructMemberOffset of BT.tag * 'bt term * BT.member

and 'bt pointer_op = 
  | Null
  | AddPointer of 'bt term * 'bt term
  | SubPointer of 'bt term * 'bt term
  | MulPointer of 'bt term * 'bt term
  | LTPointer of 'bt term * 'bt term
  | LEPointer of 'bt term * 'bt term
  | IntegerToPointerCast of 'bt term
  | PointerToIntegerCast of 'bt term

and 'bt list_op = 
  | Nil
  | Cons of 'bt term * 'bt term
  | List of 'bt term list
  | Head of 'bt term
  | Tail of 'bt term
  | NthList of int * 'bt term

and 'bt set_op = 
  | SetMember of 'bt term * 'bt term
  | SetUnion of ('bt term) List1.t
  | SetIntersection of ('bt term) List1.t
  | SetDifference of 'bt term * 'bt term
  | Subset of 'bt term * 'bt term

and 'bt array_op = 
  | ConstArray of 'bt term
  | ArrayGet of 'bt term * 'bt term
  | ArraySet of 'bt term * 'bt term * 'bt term
  | ArrayEqualOnRange of 'bt term * 'bt term * 'bt term * 'bt term

and 'bt ct_pred = 
  | MinInteger of CF.Ctype.integerType
  | MaxInteger of CF.Ctype.integerType
  | Representable of CT.t * 'bt term
  | AlignedI of 'bt term * 'bt term
  | Aligned of CT.t * 'bt term

and 'bt term_ =
  | Lit of lit
  | Arith_op of 'bt arith_op
  | Bool_op of 'bt bool_op
  | Cmp_op of 'bt cmp_op
  | Tuple_op of 'bt tuple_op
  | Struct_op of 'bt struct_op
  | Pointer_op of 'bt pointer_op
  | List_op of 'bt list_op
  | Set_op of 'bt set_op
  | Array_op of 'bt array_op
  | CT_pred of 'bt ct_pred

and 'bt term =
  | IT of 'bt term_ * 'bt



type typed = BT.t term
type untyped = unit term

type it = typed
type t = typed


let bt (IT (_, bt)) : BT.t = bt


let rec equal (IT (it, _)) (IT (it', _)) = 

  let lit it it' =
    match it, it' with
    | Sym sym, Sym sym' -> Sym.equal sym sym'
    | Z n, Z n' -> Z.equal n n'
    | Q (n1,n2), Q (n1',n2') -> n1 = n1' && n2 = n2'
    | Pointer p, Pointer p' -> Z.equal p p'
    | Bool b, Bool b' -> b = b'
    | Unit, Unit -> true
    | Default bt, Default bt' -> BT.equal bt bt'
    | Sym _, _ -> false
    | Z _, _ -> false
    | Q _, _ -> false
    | Pointer _, _ -> false
    | Bool _, _ -> false
    | Unit, _ -> false
    | Default _, _ -> false
  in

  let arith_op it it' =
    match it, it' with
    | Add (t1,t2), Add (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Sub (t1,t2), Sub (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Mul (t1,t2), Mul (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Div (t1,t2), Div (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Exp (t1,t2), Exp (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Rem_t (t1,t2), Rem_t (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Rem_f (t1,t2), Rem_f (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Min (t1,t2), Min (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Max (t1,t2), Max (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | Add _, _ -> false
    | Sub _, _ -> false
    | Mul _, _ -> false 
    | Div _, _ -> false
    | Exp _, _ -> false
    | Rem_t _, _ -> false
    | Rem_f _, _ -> false
    | Min _, _ -> false
    | Max _, _ -> false
  in

  let cmp_op it it' = 
    match it, it' with
    | LT (t1,t2), LT (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | GT (t1,t2), GT (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | LE (t1,t2), LE (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | GE (t1,t2), GE (t1',t2') -> equal t1 t1' && equal t2 t2' 
    | LT _, _ -> false
    | GT _, _ -> false
    | LE _, _ -> false
    | GE _, _ -> false
  in

  let bool_op it it' = 
    match it, it' with
    | And ts, And ts' -> 
       List.equal equal ts ts'
    | Or ts, Or ts' -> 
       List.equal equal ts ts'
    | Impl (t1,t2), Impl (t1',t2') -> 
       equal t1 t1' && equal t2 t2' 
    | Not t, Not t' -> 
       equal t t' 
    | ITE (t1,t2,t3), ITE (t1',t2',t3') -> 
       equal t1 t1' && equal t2 t2' && equal t3 t3'
    | EQ (t1,t2), EQ (t1',t2') -> 
       equal t1 t1' && equal t2 t2' 
    | NE (t1,t2), NE (t1',t2') -> 
       equal t1 t1' && equal t2 t2' 
    | And _, _ -> 
       false
    | Or _, _ -> 
       false
    | Impl _, _ -> 
       false
    | Not _, _ ->
       false
    | ITE _, _ ->
       false
    | EQ _, _ -> 
       false
    | NE _, _ -> 
       false
  in

  let tuple_op it it' =
    match it, it' with
    | Tuple its, Tuple its' -> 
       List.equal equal its its'
    | NthTuple (n,t), NthTuple (n',t') -> 
       n = n' && equal t t' 
    | Tuple _, _ -> false
    | NthTuple _, _ -> false
  in

  let struct_op it it' =
    match it, it' with
    | Struct (tag, members), Struct (tag2, members2) ->
       Sym.equal tag tag2 && 
         List.equal (fun (m,t) (m',t') -> Id.equal m m' && equal t t') 
           members members2
    | StructMember (tag,t,member), StructMember (tag',t',member') ->
       Sym.equal tag tag' && equal t t' && Id.equal member member'
    | StructMemberOffset (tag,t,member), StructMemberOffset (tag',t',member') ->
       Sym.equal tag tag' && equal t t' && Id.equal member member'
    | Struct _, _ -> false
    | StructMember _, _ -> false
    | StructMemberOffset _, _ -> false
  in

  let pointer_op it it' =
    match it, it' with
    | Null, Null -> 
       true
    | AddPointer (t1, t2), AddPointer (t1', t2') -> 
       equal t1 t1' && equal t2 t2'
    | SubPointer (t1, t2), SubPointer (t1', t2') -> 
       equal t1 t1' && equal t2 t2'
    | MulPointer (t1, t2), MulPointer (t1', t2') -> 
       equal t1 t1' && equal t2 t2'
    | LTPointer (t1, t2), LTPointer (t1', t2') -> 
       equal t1 t1' && equal t2 t2'
    | LEPointer (t1, t2), LEPointer (t1', t2') -> 
       equal t1 t1' && equal t2 t2'
    | IntegerToPointerCast t1, IntegerToPointerCast t2 -> 
       equal t1 t2
    | PointerToIntegerCast t1, PointerToIntegerCast t2 -> 
       equal t1 t2
    | Null, _ -> false
    | AddPointer _, _ -> false
    | SubPointer _, _ -> false
    | MulPointer _, _ -> false
    | LTPointer _, _ -> false
    | LEPointer _, _ -> false
    | IntegerToPointerCast _, _ -> false
    | PointerToIntegerCast _, _ -> false
  in

  let list_op it it' = 
    match it, it' with
    | Nil, Nil -> 
       true
    | Cons (t1,t2), Cons (t1',t2') -> 
       equal t1 t1' && equal t2 t2'
    | List its, List its' ->
       List.equal equal its its'
    | Head t, Head t' ->
       equal t t'
    | Tail t, Tail t' ->
       equal t t'
    | NthList (n,t), NthList (n',t') ->
       n = n' && equal t t'
    | Nil, _ -> false
    | Cons _, _ -> false
    | List _, _ -> false
    | Head _, _ -> false
    | Tail _, _ -> false
    | NthList _, _ -> false
  in


  let set_op it it' =
    match it, it' with
    | SetMember (t1,t2), SetMember (t1',t2') ->
       equal t1 t1' && equal t1' t2'
    | SetUnion ts, SetUnion ts' ->
       List1.equal equal ts ts'
    | SetIntersection ts, SetIntersection ts' ->
       List1.equal equal ts ts'
    | SetDifference (t1, t2), SetDifference (t1', t2') ->
       equal t1 t1' && equal t1' t2'
    | Subset (t1, t2), Subset (t1', t2') ->
       equal t1 t1' && equal t1' t2'
    | SetMember _, _ -> false
    | SetUnion _, _ -> false
    | SetIntersection _, _ -> false
    | SetDifference _, _ -> false
    | Subset _, _ -> false
  in

  let array_op it it' =
    match it, it' with
    | ConstArray t, ConstArray t' ->
       equal t t'
    | ArrayGet (t1,t2), ArrayGet (t1',t2') ->
       equal t1 t1' && equal t2 t2'
    | ArraySet (t1,t2,t3), ArraySet (t1',t2',t3') ->
       equal t1 t1' && equal t2 t2' && equal t3 t3'
    | ArrayEqualOnRange (t1,t2,t3,t4), ArrayEqualOnRange (t1',t2',t3',t4') ->
       equal t1 t1' && equal t2 t2' && equal t3 t3' && equal t4 t4'
    | ConstArray _, _ -> false
    | ArrayGet _, _ -> false
    | ArraySet _, _ -> false
    | ArrayEqualOnRange _, _ -> false
  in

  let ct_pred it it' = 
    match it, it' with
    | Aligned (rt, t), Aligned (rt', t') ->
       CT.equal rt rt' && equal t t'
    | AlignedI (t1, t2), AlignedI (t1', t2') ->
       equal t1 t1' && equal t2 t2'
    | Representable (rt, t), Representable (rt', t') ->
       CT.equal rt rt' && equal t t'
    | MinInteger it, MinInteger it' ->
       CF.Ctype.integerTypeEqual it it'
    | MaxInteger it, MaxInteger it' ->
       CF.Ctype.integerTypeEqual it it'
    | Aligned _, _ -> false
    | AlignedI _, _ -> false
    | Representable _, _ -> false
    | MinInteger _, _ -> false
    | MaxInteger _, _ -> false
  in


  match it, it' with
  | Lit it, Lit it' -> lit it it'
  | Arith_op it, Arith_op it' -> arith_op it it'
  | Bool_op it, Bool_op it' -> bool_op it it'
  | Cmp_op it, Cmp_op it' -> cmp_op it it'
  | Tuple_op it, Tuple_op it' -> tuple_op it it'
  | Struct_op it, Struct_op it' -> struct_op it it'
  | Pointer_op it, Pointer_op it' -> pointer_op it it'
  | List_op it, List_op it' -> list_op it it'
  | Set_op it, Set_op it' -> set_op it it'
  | Array_op it, Array_op it' -> array_op it it'
  | CT_pred it, CT_pred it' -> ct_pred it it'
  | Lit _, _ -> false
  | Arith_op _, _ -> false
  | Bool_op _, _ -> false
  | Cmp_op _, _ -> false
  | Tuple_op _, _ -> false
  | Struct_op _, _ -> false
  | Pointer_op _, _ -> false
  | List_op _, _ -> false
  | Set_op _, _ -> false
  | Array_op _, _ -> false
  | CT_pred _, _ -> false





let pp (it : 'bt term) : PPrint.document = 

  let rec aux atomic (IT (it, bt)) = 

    let mparens pped = if atomic then parens pped else pped in
    
    let lit = function
      | Sym sym -> Sym.pp sym
      | Z i -> Z.pp i
      | Q (i,i') -> c_app !^"frac" [!^(string_of_int i); !^(string_of_int i')]
      | Pointer i -> Z.pp i
      | Bool true -> !^"true"
      | Bool false -> !^"false"
      | Unit -> !^"void"
      | Default bt -> parens (!^("default") ^^^ colon ^^^ BT.pp bt)
    in

    let arith_op = function
      | Add (it1,it2) -> 
         mparens (flow (break 1) [aux true it1; plus; aux true it2])
      | Sub (it1,it2) -> 
         mparens (flow (break 1) [aux true it1; minus; aux true it2])
      | Mul (it1,it2) -> 
         mparens (flow (break 1) [aux true it1; star; aux true it2])
      | Div (it1,it2) -> 
         mparens (flow (break 1) [aux true it1; slash; aux true it2])
      | Exp (it1,it2) -> 
         c_app !^"power" [aux true it1; aux true it2]
      | Rem_t (it1,it2) -> 
         c_app !^"rem_t" [aux true it1; aux true it2]
      | Rem_f (it1,it2) -> 
         c_app !^"rem_f" [aux true it1; aux true it2]
      | Min (it1,it2) -> 
         c_app !^"min" [aux true it1; aux true it2]
      | Max (it1,it2) -> 
         c_app !^ "max" [aux true it1; aux true it2]
    in

    let cmp_op = function
      | LT (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; langle; aux true o2])
      | GT (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; rangle; aux true o2])
      | LE (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; (langle ^^ equals); aux true o2])
      | GE (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; (rangle ^^ equals); aux true o2])
    in

    let bool_op = function
      | And o -> 
         Pp.group (mparens (flow_map (break 1 ^^ !^"&&" ^^ break 1) (aux false) o))
      | Or o -> 
         Pp.group (mparens (flow_map (break 1 ^^ !^"||" ^^ break 1) (aux false) o))
      | Impl (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; (equals ^^ rangle); aux true o2])
      | Not (o1) -> 
         mparens (!^"not" ^^^ aux true o1)
      | ITE (o1,o2,o3) -> 
         mparens (flow (break 1) [aux true o1; !^"?"; aux true o2; colon; aux true o3])
      | EQ (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; equals ^^ equals; aux true o2])
      | NE (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; !^"!="; aux true o2])
    in

    let tuple_op = function
      | NthTuple (n,it2) -> 
         mparens (aux true it2 ^^ dot ^^ !^("component" ^ string_of_int n))
      | Tuple its -> 
         braces (separate_map (semi ^^ space) (aux false) its)
    in

    let struct_op = function
      | Struct (_tag, members) ->
         braces (flow_map (comma ^^ break 1) (fun (member,it) -> 
                     Id.pp member ^^^ equals ^^^ aux false it 
                   ) members)
      | StructMember (_tag, t, member) ->
         aux true t ^^ dot ^^ Id.pp member
      | StructMemberOffset (_tag, t, member) ->
         mparens (ampersand ^^ aux true t ^^ !^"->" ^^ Id.pp member)
    in

    let pointer_op = function    
      | Null -> 
         !^"null"
      | AddPointer (t1, t2) ->
         mparens (flow (break 1) [aux true t1; plus ^^ dot; aux true t2])
      | SubPointer (t1, t2) ->
         mparens (flow (break 1) [aux true t1; minus ^^ dot; aux true t2])
      | MulPointer (t1, t2) ->
         mparens (flow (break 1) [aux true t1; star ^^ dot; aux true t2])
      | LTPointer (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; langle; aux true o2])
      | LEPointer (o1,o2) -> 
         mparens (flow (break 1) [aux true o1; langle ^^ equals; aux true o2])
      | IntegerToPointerCast t ->
         mparens (parens(!^"pointer") ^^ aux true t)
      | PointerToIntegerCast t ->
         mparens (parens(!^"integer") ^^ aux true t)
    in

    let ct_pred = function
      | Aligned (rt, t) ->
         c_app !^"aligned" [CT.pp rt; aux false t]
      | AlignedI (t, t') ->
         c_app !^"aligned" [aux false t; aux false t']
      | MinInteger it ->
         c_app !^"min" [CF.Pp_core_ctype.pp_integer_ctype it]
      | MaxInteger it ->
         c_app !^"max" [CF.Pp_core_ctype.pp_integer_ctype it]
      | Representable (rt, t) ->
         c_app !^"repr" [CT.pp rt; aux false t]
    in

    let list_op = function    
      | Head (o1) -> 
         c_app !^"hd" [aux false o1]
      | Tail (o1) -> 
         c_app !^"tl" [aux false o1]
      | Nil -> 
         brackets empty
      | Cons (t1,t2) -> 
         mparens (aux true t1 ^^ colon ^^ colon ^^ aux true t2)
      | List its -> 
         mparens (brackets (separate_map (comma ^^ space) (aux false) its))
      | NthList (n, t) ->
         mparens (aux true t ^^ brackets !^(string_of_int n))
    in

    let set_op = function
      | SetMember (t1,t2) ->
         c_app !^"member" [aux false t1; aux false t2]
      | SetUnion ts ->
         c_app !^"union" (List.map (aux false) (List1.to_list ts))
      | SetIntersection ts ->
         c_app !^"intersection" (List.map (aux false) (List1.to_list ts))
      | SetDifference (t1, t2) ->
         c_app !^"difference" [aux false t1; aux false t2]
      | Subset (t1, t2) ->
         c_app !^"subset" [aux false t1; aux false t2]
    in

    let array_op = function    
      | ConstArray t ->
         c_app !^"all" [aux false t]
      | ArrayGet (t1,t2) ->
         aux true t1 ^^ lbracket ^^ aux false t2 ^^ rbracket
      | ArraySet (t1,t2,t3) ->
         aux false t1 ^^ lbracket ^^ aux false t2 ^^^ equals ^^^ aux false t3 ^^ rbracket
      | ArrayEqualOnRange (t1,t2,t3,t4) ->
         c_app !^"equalOnRange" [aux false t1; aux false t2; aux false t3; aux false t4]
    in

    match it with
    | Lit it -> lit it
    | Arith_op it -> arith_op it
    | Cmp_op it -> cmp_op it
    | Bool_op it -> bool_op it
    | Tuple_op it -> tuple_op it
    | Struct_op it -> struct_op it
    | Pointer_op it -> pointer_op it
    | CT_pred it -> ct_pred it
    | List_op it -> list_op it
    | Set_op it -> set_op it
    | Array_op it -> array_op it

  in

  aux false it


let rec free_vars : 'bt. 'bt term -> SymSet.t =

  let lit : lit -> SymSet.t = function
    | Sym symbol -> SymSet.singleton symbol
    | Z _ -> SymSet.empty
    | Q _ -> SymSet.empty
    | Pointer _ -> SymSet.empty
    | Bool _ -> SymSet.empty
    | Unit -> SymSet.empty
    | Default _ -> SymSet.empty
  in

  let arith_op : 'bt arith_op -> SymSet.t = function
    | Add (it, it') -> free_vars_list [it; it']
    | Sub (it, it') -> free_vars_list [it; it']
    | Mul (it, it') -> free_vars_list [it; it']
    | Div (it, it') -> free_vars_list [it; it']
    | Exp (it, it') -> free_vars_list [it; it']
    | Rem_t (it, it') -> free_vars_list [it; it']
    | Rem_f (it, it') -> free_vars_list [it; it']
    | Min (it, it') -> free_vars_list [it; it']
    | Max (it, it') -> free_vars_list [it; it']
  in

  let cmp_op : 'bt cmp_op -> SymSet.t = function
    | LT (it, it') -> free_vars_list [it; it']
    | GT (it, it') -> free_vars_list [it; it']
    | LE (it, it') -> free_vars_list [it; it']
    | GE (it, it') -> free_vars_list [it; it']
  in

  let bool_op : 'bt bool_op -> SymSet.t = function
    | And its -> free_vars_list its
    | Or its -> free_vars_list its
    | Impl (it, it') -> free_vars_list [it; it']
    | Not it -> free_vars it
    | ITE (it,it',it'') -> free_vars_list [it;it';it'']
    | EQ (it, it') -> free_vars_list [it; it']
    | NE (it, it') -> free_vars_list [it; it']
  in

  let tuple_op : 'bt tuple_op -> SymSet.t = function
    | Tuple its -> free_vars_list its
    | NthTuple ( _, it) -> free_vars it
  in
  
  let struct_op : 'bt struct_op -> SymSet.t = function
    | Struct (_tag, members) -> free_vars_list (map snd members)
    | StructMember (_tag, it, s) -> free_vars_list [it;it]
    | StructMemberOffset (_tag, it, s) -> free_vars_list [it;it]
  in

  let pointer_op : 'bt pointer_op -> SymSet.t = function
    | Null -> SymSet.empty
    | AddPointer (it, it') -> free_vars_list [it; it']
    | SubPointer (it, it') -> free_vars_list [it; it']
    | MulPointer (it, it') -> free_vars_list [it; it']
    | LTPointer (it, it')  -> free_vars_list [it; it']
    | LEPointer (it, it') -> free_vars_list [it; it']
    | IntegerToPointerCast t -> free_vars t
    | PointerToIntegerCast t -> free_vars t
  in

  let ct_pred : 'bt ct_pred -> SymSet.t = function
    | Aligned (_rt, t) -> free_vars t
    | AlignedI (t, t') -> free_vars_list [t; t']
    | MinInteger _ -> SymSet.empty
    | MaxInteger _ -> SymSet.empty
    | Representable (_rt,t) -> free_vars t
  in

  let list_op : 'bt list_op -> SymSet.t = function
    | Nil  -> SymSet.empty
    | Cons (it, it') -> free_vars_list [it; it']
    | List its -> free_vars_list its
    | Head it -> free_vars it
    | Tail it -> free_vars it
    | NthList (_,it) -> free_vars it
  in

  let set_op : 'bt set_op -> SymSet.t = function
    | SetMember (t1,t2) -> free_vars_list [t1;t2]
    | SetUnion ts -> free_vars_list (List1.to_list ts)
    | SetIntersection ts -> free_vars_list (List1.to_list ts)
    | SetDifference (t1, t2) -> free_vars_list [t1;t2]
    | Subset (t1, t2) -> free_vars_list [t1;t2]
  in

  let array_op : 'bt array_op -> SymSet.t = function
    | ConstArray t -> free_vars t
    | ArrayGet (t1,t2) -> free_vars_list [t1;t2]
    | ArraySet (t1,t2,t3) -> free_vars_list [t1;t2;t3]
    | ArrayEqualOnRange (t1,t2,t3,t4) -> free_vars_list [t1;t2;t3; t4]
  in
  
  fun (IT (it, _)) ->
  match it with
  | Lit it -> lit it
  | Arith_op it -> arith_op it
  | Cmp_op it -> cmp_op it
  | Bool_op it -> bool_op it
  | Tuple_op it -> tuple_op it
  | Struct_op it -> struct_op it
  | Pointer_op it -> pointer_op it
  | CT_pred it -> ct_pred it
  | List_op it -> list_op it
  | Set_op it -> set_op it
  | Array_op it -> array_op it


and free_vars_list l = 
  List.fold_left (fun acc sym -> 
      SymSet.union acc (free_vars sym)
    ) SymSet.empty l


let json it : Yojson.Safe.t = `String (Pp.plain (pp it))



let map_sym (type bt) (f : Sym.t -> bt -> bt term) =

  let rec aux = 

    let lit it bt = 
      match it with
      | Sym symbol -> f symbol bt
      | it -> IT (Lit it, bt)
    in

    let arith_op it bt = 
      let it = match it with
        | Add (it, it') -> Add (aux it, aux it')
        | Sub (it, it') -> Sub (aux it, aux it')
        | Mul (it, it') -> Mul (aux it, aux it')
        | Div (it, it') -> Div (aux it, aux it')
        | Exp (it, it') -> Exp (aux it, aux it')
        | Rem_t (it, it') -> Rem_t (aux it, aux it')
        | Rem_f (it, it') -> Rem_f (aux it, aux it')
        | Min (it, it') -> Min (aux it, aux it')
        | Max (it, it') -> Max (aux it, aux it')
      in
      IT (Arith_op it, bt)
    in

    let cmp_op it bt = 
      let it = match it with
        | LT (it, it') -> LT (aux it, aux it')
        | GT (it, it') -> GT (aux it, aux it')
        | LE (it, it') -> LE (aux it, aux it')
        | GE (it, it') -> GE (aux it, aux it')
      in
      IT (Cmp_op it, bt)
    in

    let bool_op it bt = 
      let it = match it with
        | And its -> And (map (aux) its)
        | Or its -> Or (map (aux) its)
        | Impl (it, it') -> Impl (aux it, aux it')
        | Not it -> Not (aux it)
        | ITE (it,it',it'') -> ITE (aux it, aux it', aux it'')
        | EQ (it, it') -> EQ (aux it, aux it')
        | NE (it, it') -> NE (aux it, aux it')
      in
      IT (Bool_op it, bt)
    in

    let tuple_op it bt = 
      let it = match it with
        | Tuple its ->
           Tuple (map aux its)
        | NthTuple (n, it') ->
           NthTuple (n, aux it')
      in
      IT (Tuple_op it, bt)
    in
    
    let struct_op it bt =
      let it = match it with
        | Struct (tag, members) ->
           let members = map (fun (member,it) -> (member,aux it)) members in
           Struct (tag, members)
        | StructMember (tag, t, f) ->
           StructMember (tag, aux t, f)
        | StructMemberOffset (tag,t,f) ->
           StructMemberOffset (tag,aux t, f)
      in
      IT (Struct_op it, bt)
    in

    let pointer_op it bt =
      let it = match it with
        | Null -> 
           Null
        | AddPointer (it, it') -> 
           AddPointer (aux it, aux it')
        | SubPointer (it, it') -> 
           SubPointer (aux it, aux it')
        | MulPointer (it, it') -> 
           MulPointer (aux it, aux it')
        | LTPointer (it, it') -> 
           LTPointer (aux it, aux it')
        | LEPointer (it, it') -> 
           LEPointer (aux it, aux it')
        | IntegerToPointerCast t -> 
           IntegerToPointerCast (aux t)
        | PointerToIntegerCast t -> 
           PointerToIntegerCast (aux t)
      in
      IT (Pointer_op it, bt)
    in

    let ct_pred it bt =
      let it = match it with
        | Aligned (rt,t) -> Aligned (rt, aux t)
        | AlignedI (t,t') -> AlignedI (aux t, aux t')
        | MinInteger it -> MinInteger it
        | MaxInteger it -> MaxInteger it
        | Representable (rt,t) -> Representable (rt,aux t)
      in
      IT (CT_pred it, bt)
    in

    let list_op it bt =
      let it = match it with
        | Nil -> Nil
        | Cons (it1,it2) -> Cons (aux it1, aux it2)
        | List its -> List (map aux its)
        | Head it -> Head (aux it)
        | Tail it -> Tail (aux it)
        | NthList (i, it) -> NthList (i, aux it)
      in
      IT (List_op it, bt)
    in

    let set_op it bt = 
      let it = match it with
        | SetMember (t1,t2) -> SetMember (aux t1, aux t2)
        | SetUnion ts -> SetUnion (List1.map aux ts)
        | SetIntersection ts -> SetIntersection (List1.map aux ts)
        | SetDifference (t1, t2) -> SetDifference (aux t1, aux t2)
        | Subset (t1, t2) -> Subset (aux t1, aux t2)
      in
      IT (Set_op it, bt)
    in

    let array_op it bt = 
      let it = match it with
        | ConstArray t ->
           ConstArray (aux t)
        | ArrayGet (t1, t2) ->
           ArrayGet (aux t1, aux t2)
        | ArraySet (t1, t2, t3) ->
           ArraySet (aux t1, aux t2, aux t3)
        | ArrayEqualOnRange (t1, t2, t3, t4) ->
           ArrayEqualOnRange (aux t1, aux t2, aux t3, aux t4)
      in
      IT (Array_op it, bt)
    in

    fun (IT (it, bt)) ->
    match it with
    | Lit it -> lit it bt
    | Arith_op it -> arith_op it bt
    | Cmp_op it -> cmp_op it bt
    | Bool_op it -> bool_op it bt
    | Tuple_op it -> tuple_op it bt
    | Struct_op it -> struct_op it bt
    | Pointer_op it -> pointer_op it bt
    | CT_pred it -> ct_pred it bt
    | List_op it -> list_op it bt
    | Set_op it -> set_op it bt
    | Array_op it -> array_op it bt

  in

  fun it -> aux it


let subst_var (subst : (Sym.t, Sym.t) Subst.t) it =
  map_sym (fun s bt ->
      IT (Lit (Sym (Sym.subst subst s)), bt)
    ) it

let subst_vars it = make_substs subst_var it


let subst_it (subst : (Sym.t, 'bt term) Subst.t) it =
  map_sym (fun s bt ->
      if Sym.equal s subst.before 
      then subst.after
      else IT (Lit (Sym s), bt)
    ) it

let subst_its it = make_substs subst_it it


let unify it it' res = 
  let equal_it = equal in
  let open Option in
  let open Uni in
  if equal_it it it' then return res else
    match it with
    | IT (Lit (Sym s), _) ->
       let@ uni = SymMap.find_opt s res in
       begin match uni.resolved with
       | Some it_res when equal_it it_res it' -> return res 
       | Some s -> fail
       | None -> return (SymMap.add s {resolved = Some it'} res)
       end
    | _ -> fail





let is_sym = function
  | IT (Lit (Sym sym), bt) -> Some (sym, bt)
  | _ -> None



(* shorthands *)


(* lit *)
let sym_ (bt, sym) = IT (Lit (Sym sym), bt)
let z_ n = IT (Lit (Z n), BT.Integer)
let q_ (n,n') = IT (Lit (Q (n,n')), BT.Real)
let pointer_ n = IT (Lit (Pointer n), BT.Loc)
let bool_ b = IT (Lit (Bool b), BT.Bool)
let unit_ = IT (Lit Unit, BT.Unit)
let default_ bt = IT (Lit (Default bt), bt)
let int_ n = z_ (Z.of_int n)

(* arith_op *)
let add_ (it, it') = IT (Arith_op (Add (it, it')), bt it)
let sub_ (it, it') = IT (Arith_op (Sub (it, it')), bt it)
let mul_ (it, it') = IT (Arith_op (Mul (it, it')), bt it)
let div_ (it, it') = IT (Arith_op (Div (it, it')), bt it)
let exp_ (it, it') = IT (Arith_op (Exp (it, it')), bt it)
let rem_t_ (it, it') = IT (Arith_op (Rem_t (it, it')), BT.Integer)
let rem_f_ (it, it') = IT (Arith_op (Rem_f (it, it')), BT.Integer)
let min_ (it, it') = IT (Arith_op (Min (it, it')), bt it)
let max_ (it, it') = IT (Arith_op (Max (it, it')), bt it)

(* cmp_op *)
let lt_ (it, it') = IT (Cmp_op (LT (it, it')), BT.Bool)
let gt_ (it, it') = IT (Cmp_op (GT (it, it')), BT.Bool)
let le_ (it, it') = IT (Cmp_op (LE (it, it')), BT.Bool)
let ge_ (it, it') = IT (Cmp_op (GE (it, it')), BT.Bool)

(* bool_op *)
let and_ its = IT (Bool_op (And its), BT.Bool)
let or_ its = IT (Bool_op (Or its), BT.Bool)
let impl_ (it, it') = IT (Bool_op (Impl (it, it')), BT.Bool)
let not_ it = IT (Bool_op (Not it), BT.Bool)
let ite_ (it, it', it'') = IT (Bool_op (ITE (it, it', it'')), bt it')
let eq_ (it, it') = IT (Bool_op (EQ (it, it')), BT.Bool)
let eq__ it it' = eq_ (it, it')
let ne_ (it, it') = IT (Bool_op (NE (it, it')), BT.Bool)

(* tuple_op *)
let tuple_ its = IT (Tuple_op (Tuple its), BT.Tuple (List.map bt its))
let nthTuple_ ~item_bt (n, it) = IT (Tuple_op (NthTuple (n, it)), item_bt)

(* struct_op *)
let struct_ (tag, members) = 
  IT (Struct_op (Struct (tag, members)), BT.Struct tag) 
let structMember_ ~member_bt (tag, it, member) = 
  IT (Struct_op (StructMember (tag, it, member)), member_bt)
let structMemberOffset_ (tag, it, member) = 
  IT (Struct_op (StructMemberOffset (tag, it, member)), BT.Loc)

(* pointer_op *)
let null_ = IT (Pointer_op Null, BT.Loc)
let addPointer_ (it, it') = IT (Pointer_op (AddPointer (it, it')), BT.Loc)
let subPointer_ (it, it') = IT (Pointer_op (SubPointer (it, it')), BT.Loc)
let mulPointer_ (it, it') = IT (Pointer_op (MulPointer (it, it')), BT.Loc)
let ltPointer_ (it, it') = IT (Pointer_op (LTPointer (it, it')), BT.Bool)
let lePointer_ (it, it') = IT (Pointer_op (LEPointer (it, it')), BT.Bool)
let disjoint_ ((p1, s1), (p2, s2)) = 
  or_ [lePointer_ (addPointer_ (p1, s1), p2); 
       lePointer_ (addPointer_ (p2, s2), p1)] 
let integerToPointerCast_ it = IT (Pointer_op (IntegerToPointerCast it), BT.Loc)
let pointerToIntegerCast_ it = IT (Pointer_op (PointerToIntegerCast it), BT.Integer)

(* list_op *)
let nil_ ~item_bt = IT (List_op Nil, BT.List item_bt)
let cons_ (it, it') = IT (List_op (Cons (it, it')), bt it')
let list_ ~item_bt its = IT (List_op (List its), BT.List item_bt)
let head_ ~item_bt it = IT (List_op (Head it), item_bt)
let tail_ it = IT (List_op (Tail it), bt it)
let nthList_ ~item_bt (n, it) = IT (List_op (NthList (n, it)), item_bt)

(* set_op *)
let setMember_ bt (it, it') = IT (Set_op (SetMember (it, it')), BT.Bool)
let setUnion_ its = IT (Set_op (SetUnion its), bt (List1.head its))
let setIntersection_ its = IT (Set_op (SetIntersection its), bt (List1.head its))
let setDifference_ (it, it') = IT (Set_op (SetDifference (it, it')), bt it)
let subset_ (it, it') = IT (Set_op (Subset (it, it')), BT.Bool)

(* array_op *)
let constArray_ ~item_bt it = 
  IT (Array_op (ConstArray it), BT.Array item_bt)
let arrayGet_ ~item_bt (it, it') = 
  IT (Array_op (ArrayGet (it, it')), item_bt)
let arraySet_ ~item_bt (it, it', it'') = 
  IT (Array_op (ArraySet (it, it', it'')), BT.Array item_bt)
let arrayEqualOnRange_ (it, it', it'', it''') = 
  IT (Array_op (ArrayEqualOnRange (it, it', it'', it''')), BT.Bool)

(* ct_pred *)
let minInteger_ t = 
  IT (CT_pred (MinInteger t), BT.Integer)
let maxInteger_ t = 
  IT (CT_pred (MaxInteger t), BT.Integer)
let representable_ (t, it) = 
  IT (CT_pred (Representable (t, it)), BT.Bool)
let aligned_ (t, it) = 
  IT (CT_pred (Aligned (t, it)), BT.Bool)
let alignedI_ (it, it') = 
  IT (CT_pred (AlignedI (it, it')), BT.Bool)


let def_ sym e = eq_ (sym_ (bt e, sym), e)

let in_range within (min, max) = 
  and_ [le_ (min, within); le_ (within, max)]

let in_footprint within (pointer, size) = 
  and_ [lePointer_ (pointer, within); 
        ltPointer_ (within, addPointer_ (pointer, size))]




let disjoint_from fp fps =
  List.map (fun fp' -> disjoint_ (fp, fp')) fps



let good_pointer_it pointer_it pointee_sct = 
  match pointee_sct with
  | CT.Sctype (_, Void) ->
     representable_ (CT.pointer_sct pointee_sct, pointer_it);
  | _ -> 
     and_ [
         representable_ (CT.pointer_sct pointee_sct, pointer_it);
         aligned_ (pointee_sct, pointer_it);
       ]

let good_pointer pointer pointee_sct = 
  let pointer_it = sym_ (BT.Loc, pointer) in
  good_pointer_it pointer_it pointee_sct


let good_value v sct =
  let v_it = sym_ (BT.of_sct sct, v) in
  match sct with
  | Sctype (_, Pointer (qualifiers, pointee_sct)) ->
     good_pointer v pointee_sct
  | _ ->
     representable_ (sct, v_it)



let simp (lcs : t list) term = 

  let values = 
    List.fold_right (fun (IT (it, bt)) values ->
        match it with
        | Bool_op (EQ (it, it')) ->
           begin match is_sym it with
           | Some (sym, _) -> SymMap.add sym it' values
           | None -> values
           end
        | _ -> values
      ) lcs SymMap.empty
  in

  let is_true = function
    | IT (Lit (Bool true), _) -> true
    | _ -> false
  in

  let is_false = function
    | IT (Lit (Bool false), _) -> true
    | _ -> false
  in

  let rec aux (IT (it, bt)) =
    match it with
    | Lit it -> lit it bt
    | Arith_op it -> arith_op it bt
    | Bool_op it -> bool_op it bt
    | Cmp_op it -> cmp_op it bt
    | Tuple_op it -> IT (Tuple_op it, bt)
    | Struct_op it -> IT (Struct_op it, bt)
    | Pointer_op it -> pointer_op it bt
    | List_op it -> IT (List_op it, bt)
    | Set_op it -> IT (Set_op it, bt)
    | Array_op it -> IT (Array_op it, bt)
    | CT_pred it -> IT (CT_pred it, bt)

  and lit it bt = 
    match it with
    | Sym sym ->
       begin match SymMap.find_opt sym values with
       | Some it -> it
       | None -> IT (Lit (Sym sym), bt)
       end
    | Z z ->
       IT (Lit (Z z), bt)
    | Q (i1, i2) ->
       IT (Lit (Q (i1, i2)), bt)
    | Pointer z ->
       IT (Lit (Pointer z), bt)
    | Bool b ->
       IT (Lit (Bool b), bt)
    | Unit ->
       IT (Lit Unit, bt)
    | Default bt' ->
       IT (Lit (Default bt'), bt)

  and arith_op it bt = 
    match it with
    | Add (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a, b with
       | IT (Lit (Q (i1, j1)), _), IT (Lit (Q (i2, j2)), _) 
            when j1 = j2 ->
          IT (Lit (Q (i1 + i2, j1)), bt)
       | _, IT (Lit (Q (0, _)), _) ->
          a
       | IT (Lit (Q (0, _)), _), _ ->
          b
       | _, _ ->
          IT (Arith_op (Add (a, b)), bt)
       end
    | Sub (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a, b, bt with
       | _, IT (Lit (Q (0, _)), _), _ -> 
          a
       | _, _, BT.Integer when equal a b -> 
          IT (Lit (Z Z.zero), bt)
       | _, _, BT.Real when equal a b -> 
          IT (Lit (Q (0, 1)), bt)
       | _, _, _ ->
          IT (Arith_op (Sub (a, b)), bt) 
       end
    | Mul (a, b) ->
       IT (Arith_op (Mul (aux a, aux b)), bt) 
    | Div (a, b) ->
       let a = aux a in
       let b = aux b in 
       begin match a, b with
       | _, IT (Lit (Z b), _) when Z.equal b (Z.of_int 1) -> 
          a
       | _ ->
          IT (Arith_op (Div (a, b)), bt) 
       end
    | Exp (a, b) ->
       IT (Arith_op (Exp (aux a, aux b)), bt) 
    | Rem_t (a, b) ->
       let a = aux a in
       let b = aux b in 
       begin match a, b with
       | _, IT (Lit (Z b), _) when Z.equal b (Z.of_int 1) -> 
          IT (Lit (Z Z.zero), bt)
       | _ ->
          IT (Arith_op (Rem_t (a, b)), bt) 
       end
    | Rem_f (a, b) ->
       let a = aux a in
       let b = aux b in 
       begin match a, b with
       | _, IT (Lit (Z b), _) when Z.equal b (Z.of_int 1) -> 
          IT (Lit (Z Z.zero), bt)
       | _ ->
          IT (Arith_op (Rem_f (a, b)), bt) 
       end
    | Min (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a, b with
       | _ when equal a b -> 
          a
       | IT (Lit (Q (i1, j1)), _), IT (Lit (Q (i2, j2)), _) 
            when i1 <= i2 && j1 = j2 ->
          a
       | IT (Lit (Q (i1, j1)), _), IT (Lit (Q (i2, j2)), _) 
            when i1 > i2 && j1 = j2 ->
          b
       | _ ->
          IT (Arith_op (Min (a, b)), bt)
       end
    | Max (a, b)  ->
       let a = aux a in
       let b = aux b in
       if equal a b then a 
       else IT (Arith_op (Max (a, b)), bt)

  and bool_op it bt = 
    match it with
    | And its ->
       let its = List.map aux its in
       if List.exists is_false its then 
         IT (Lit (Bool false), bt)
       else if List.for_all is_true its then
         IT (Lit (Bool true), bt)
       else
         IT (Bool_op (And its), bt)
    | Or its ->
       let its = List.map aux its in
       if List.exists is_true its then
         IT (Lit (Bool true), bt)
       else if List.for_all is_false its then
         IT (Lit (Bool false), bt)
       else
         IT (Bool_op (Or its), bt)
    | Impl (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a with
       | IT (Lit (Bool true), _) ->
          b
       | IT (Lit (Bool false), _) ->
          IT (Lit (Bool true), bt) 
       | _ ->
          IT (Bool_op (Impl (a, b)), bt)
       end
    | Not a ->
       IT (Bool_op (Not (aux a)), bt)
    | ITE (a, b, c) ->
       let a = aux a in
       let b = aux b in
       let c = aux c in
       begin match a with
       | IT (Lit (Bool true), _) -> b
       | IT (Lit (Bool false), _) -> c
       | _ when equal b c -> b
       | _ -> IT (Bool_op (ITE (a, b, c)), bt)
       end
    | EQ (a, b) ->
       let a = aux a in
       let b = aux b in
       if equal a b 
       then IT (Lit (Bool true), bt)
       else IT (Bool_op (EQ (aux a, aux b)), bt)
    | NE (a, b) ->
       IT (Bool_op (NE (aux a, aux b)), bt)

  and cmp_op it bt = 
    let cmp_rule mk z_op int_op a b =
      let a = aux a in
      let b = aux b in
       match a, b with
       | IT (Lit (Z z1), _), IT (Lit (Z z2), _) ->
          IT (Lit (Bool (z_op z1 z2)), bt)
       | IT (Lit (Q (i1, j1)), _), IT (Lit (Q (i2, j2)), _) when j1 = j2 ->
          IT (Lit (Bool (int_op i1 i2)), bt)
       | _, _ ->
          IT (Cmp_op (mk (a, b)), bt)
    in
    match it with
    | LT (a, b) -> cmp_rule (fun (a, b) -> LT (a, b)) Z.lt_big_int (<) a b
    | GT (a, b) -> cmp_rule (fun (a, b) -> GT (a, b)) Z.gt_big_int (>) a b
    | LE (a, b) -> cmp_rule (fun (a, b) -> LE (a, b)) Z.le_big_int (<=) a b
    | GE (a, b) -> cmp_rule (fun (a, b) -> GE (a, b)) Z.ge_big_int (>=) a b

  (* revisit when memory model changes *)
  and pointer_op it bt = 
    match it with
    | Null -> 
       IT (Pointer_op Null, bt)
    | AddPointer (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a, b with
       | IT (Pointer_op (AddPointer (aa, IT (Lit (Z i), _))), _), 
         IT (Lit (Z j), _) ->
          IT (Pointer_op (AddPointer (aa, IT (Lit (Z (Z.add_big_int i j)), Integer))), bt)
       | _ ->
          IT (Pointer_op (AddPointer (a, b)), bt)
       end
    | SubPointer (a, b) ->
       IT (Pointer_op (SubPointer (aux a, aux b)), bt)
    | MulPointer (a, b) ->
       IT (Pointer_op (MulPointer (aux a, aux b)), bt)
    | LTPointer (a, b) ->
       IT (Pointer_op (LTPointer (aux a, aux b)), bt)
    | LEPointer (a, b) ->
       let a = aux a in
       let b = aux b in
       begin match a, b with
       | IT (Pointer_op (AddPointer (base1, IT (Lit (Z offset1), _))), _),  
         IT (Pointer_op (AddPointer (base2, IT (Lit (Z offset2), _))), _) when
              equal base1 base2 ->
          if Z.le_big_int offset1 offset2 then 
            IT (Lit (Bool true), bt)
          else if Z.gt_big_int offset1 offset2 then
            IT (Lit (Bool false), bt)
          else
            IT (Pointer_op (LEPointer (a, b)), bt)
       | _ -> 
          IT (Pointer_op (LEPointer (a, b)), bt)
       end
    | IntegerToPointerCast a ->
       IT (Pointer_op (IntegerToPointerCast (aux a)), bt)
    | PointerToIntegerCast a ->
       IT (Pointer_op (PointerToIntegerCast (aux a)), bt)       
  in
  

  aux term



(* rubbish hash function *)
let hash (IT (it, _bt)) =
  match it with
  | Arith_op it -> 1
  | Cmp_op it -> 2
  | Bool_op it -> 3
  | Tuple_op it -> 4
  | Struct_op it -> 5
  | Pointer_op it -> 6
  | CT_pred it -> 7
  | List_op it -> 8
  | Set_op it -> 9
  | Array_op it -> 10
  | Lit lit ->
     begin match lit with
     | Z z -> 11
     | Q (i, j) -> 12
     | Pointer p -> 13
     | Bool b -> 14
     | Unit -> 15
     | Default bt -> 16
     | Sym (Symbol (_,i, _)) -> 100 + i
     end

