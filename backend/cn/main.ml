open Builtins
module CF=Cerb_frontend
module CB=Cerb_backend
open CB.Pipeline
open Setup

module A=CF.AilSyntax


let return = CF.Exception.except_return
let (let@) = CF.Exception.except_bind



type core_file = (unit,unit) CF.Core.generic_file
type mu_file = unit Mucore.mu_file


type file =
  | CORE of core_file
  | MUCORE of mu_file



let print_file filename file =
  match file with
  | CORE file ->
     Pp.print_file (filename ^ ".core") (CF.Pp_core.All.pp_file file);
  | MUCORE file ->
     Pp.print_file (filename ^ ".mucore")
       (Pp_mucore.pp_file file);


module Log : sig
  val print_log_file : (string * file) -> unit
end = struct
  let print_count = ref 0
  let print_log_file (filename, file) =
    if !Cerb_debug.debug_level > 0 then
      begin
        Cerb_colour.do_colour := false;
        let count = !print_count in
        let file_path =
          (Filename.get_temp_dir_name ()) ^
            Filename.dir_sep ^
            (string_of_int count ^ "__" ^ filename)
        in
        print_file file_path file;
        print_count := 1 + !print_count;
        Cerb_colour.do_colour := true;
      end
end

open Log






let frontend ~macros ~incl_dirs ~incl_files astprints ~do_peval ~filename ~magic_comment_char_dollar =
  let open CF in
  Cerb_global.set_cerb_conf
    ~backend_name:"Cn"
    ~exec:false
    (* execution mode *) Random
    ~concurrency:false
    (* error verbosity *) Basic
    ~defacto:false
    ~permissive:false
    ~agnostic:false
    ~ignore_bitfields:false;
  Ocaml_implementation.set Ocaml_implementation.HafniumImpl.impl;
  Switches.set 
    (["inner_arg_temps"; "at_magic_comments"] 
     @ (if magic_comment_char_dollar then ["magic_comment_char_dollar"] else []));
  Core_peval.config_unfold_stdlib := Sym.has_id_with Setup.unfold_stdlib_name;
  let@ stdlib = load_core_stdlib () in
  let@ impl = load_core_impl stdlib impl_name in
  let conf = Setup.conf macros incl_dirs incl_files astprints in
  let@ (_, ail_prog_opt, prog0) = c_frontend_and_elaboration ~cnnames:cn_builtin_fun_names (conf, io) (stdlib, impl) ~filename in
  let@ () =  begin
    if conf.typecheck_core then
      let@ _ = Core_typing.typecheck_program prog0 in return ()
    else
      return ()
  end in
  let markers_env, ail_prog = Option.get ail_prog_opt in
  Tags.set_tagDefs prog0.Core.tagDefs;
  let prog1 = Remove_unspecs.rewrite_file prog0 in
  let prog2 = if do_peval then Core_peval.rewrite_file prog1 else prog1 in
  let prog3 = Milicore.core_to_micore__file Locations.update prog2 in
  let prog4 = Milicore_label_inline.rewrite_file prog3 in
  let statement_locs = CStatements.search (snd ail_prog) in
  print_log_file ("original", CORE prog0);
  print_log_file ("without_unspec", CORE prog1);
  print_log_file ("after_peval", CORE prog2);
  return (prog4, (markers_env, ail_prog), statement_locs)


let handle_frontend_error = function
  | CF.Exception.Exception ((_, CF.Errors.CORE_TYPING _) as err) ->
     prerr_string (CF.Pp_errors.to_string err);
     prerr_endline @@ Cerb_colour.(ansi_format ~err:true [Bold; Red] "error: ") ^
       "this is likely a bug in the Core elaboration.";
     exit 2
  | CF.Exception.Exception err ->
     prerr_endline (CF.Pp_errors.to_string err);
     exit 2
  | CF.Exception.Result result ->
     result




let opt_comma_split = function
  | None -> []
  | Some str -> String.split_on_char ',' str

let check_input_file filename =
  if not (Sys.file_exists filename) then
    CF.Pp_errors.fatal ("file \""^filename^"\" does not exist")
  else
    let ext = String.equal (Filename.extension filename) in
    if not (ext ".c" || ext ".h") then
      CF.Pp_errors.fatal ("file \""^filename^"\" has wrong file extension")

let _maybe_executable_check ~with_ownership_checking ~filename ?output_filename ?output_dir ail_prog mu_file statement_locs =
  Option.iter (fun output_filename ->
      Cerb_colour.without_colour (fun () ->
          Executable_spec.main ~with_ownership_checking filename ail_prog output_dir output_filename mu_file statement_locs)
        ())
    output_filename

let main
      filename
      macros
      incl_dirs
      incl_files
      loc_pp
      debug_level
      print_level
      print_sym_nums
      slow_smt_threshold
      slow_smt_dir
      no_timestamps
      json
      state_file
      diag
      lemmata
      only
      skip
      csv_times
      log_times
      random_seed
      solver_logging
      output_decorated_dir
      output_decorated
      with_ownership_checking
      astprints
      use_vip
      no_use_ity
      use_peval
      batch
      no_inherit_loc
      magic_comment_char_dollar
  =
  if json then begin
      if debug_level > 0 then
        CF.Pp_errors.fatal ("debug level must be 0 for json output");
      if print_level > 0 then
        CF.Pp_errors.fatal ("print level must be 0 for json output");
    end;
  begin (*flags *)
    Cerb_debug.debug_level := debug_level;
    Pp.loc_pp := loc_pp;
    Pp.print_level := print_level;
    CF.Pp_symbol.pp_cn_sym_nums := print_sym_nums;
    Pp.print_timestamps := not no_timestamps;
    Solver.set_slow_smt_settings slow_smt_threshold slow_smt_dir;
    Solver.random_seed := random_seed;
    Solver.log_to_temp := solver_logging;
    Check.skip_and_only := (opt_comma_split skip, opt_comma_split only);
    IndexTerms.use_vip := use_vip;
    Check.batch := batch;
    Diagnostics.diag_string := diag;
    WellTyped.use_ity := not no_use_ity
  end;
  check_input_file filename;
  let (prog4, (markers_env, ail_prog), statement_locs) =
    handle_frontend_error
      (frontend ~macros ~incl_dirs ~incl_files astprints ~do_peval:use_peval ~filename ~magic_comment_char_dollar)
  in
  Cerb_debug.maybe_open_csv_timing_file ();
  Pp.maybe_open_times_channel
    (match (csv_times, log_times) with
     | (Some times, _) -> Some (times, "csv")
     | (_, Some times) -> Some (times, "log")
     | _ -> None);
  try
    let handle_error e =
      if json then TypeErrors.report_json ?state_file e
      else TypeErrors.report ?state_file e;
      match e.msg with
      | TypeErrors.Unsupported _ -> exit 2
      | _ -> exit 1 in
    let result =
      let open Resultat in
      let@ prog5 = Core_to_mucore.normalise_file ~inherit_loc:(not(no_inherit_loc)) (markers_env, snd ail_prog) prog4 in
      print_log_file ("mucore", MUCORE prog5);
      begin match output_decorated with
      | None -> 
          let paused = Typing.run_to_pause Context.empty (Check.check_decls_lemmata_fun_specs prog5) in
          Result.iter_error handle_error (Typing.pause_to_result paused);
          Typing.run_from_pause (fun paused -> Check.check paused lemmata) paused
      | Some output_filename ->
          Cerb_colour.without_colour begin fun () ->
            Executable_spec.main ~with_ownership_checking filename ail_prog output_decorated_dir output_filename prog5 statement_locs;
            return ()
          end ()
      end in
      Pp.maybe_close_times_channel ();
    Result.fold ~ok:(fun () -> exit 0) ~error:handle_error result
  with
  | exc ->
      Pp.maybe_close_times_channel ();
      Cerb_debug.maybe_close_csv_timing_file_no_err ();
      Printexc.raise_with_backtrace exc (Printexc.get_raw_backtrace ())


open Cmdliner


(* some of these stolen from backend/driver *)
let file =
  let doc = "Source C file" in
  Arg.(required & pos ~rev:true 0 (some string) None & info [] ~docv:"FILE" ~doc)


let incl_dirs =
  let doc = "Add the specified directory to the search path for the\
             C preprocessor." in
  Arg.(value & opt_all string [] & info ["I"; "include-directory"]
         ~docv:"DIR" ~doc)

let incl_files =
  let doc = "Adds  an  implicit  #include into the predefines buffer which is \
             read before the source file is preprocessed." in
  Arg.(value & opt_all string [] & info ["include"] ~doc)

let loc_pp =
  let doc = "Print pointer values as hexadecimal or as decimal values (hex | dec)" in
  Arg.(value & opt (enum ["hex", Pp.Hex; "dec", Pp.Dec]) !Pp.loc_pp &
       info ["locs"] ~docv:"HEX" ~doc)

let debug_level =
  let doc = "Set the debug message level for cerberus to $(docv) (should range over [0-3])." in
  Arg.(value & opt int 0 & info ["d"; "debug"] ~docv:"N" ~doc)

let print_level =
  let doc = "Set the debug message level for the type system to $(docv) (should range over [0-15])." in
  Arg.(value & opt int 0 & info ["p"; "print-level"] ~docv:"N" ~doc)

let print_sym_nums =
  let doc = "Print numeric IDs of Cerberus symbols (variable names)." in
  Arg.(value & flag & info ["n"; "print-sym-nums"] ~doc)

let batch =
  let doc = "Type check functions in batch/do not stop on first type error (unless `only` is used)" in
  Arg.(value & flag & info ["batch"] ~doc)


let slow_smt_threshold =
  let doc = "Set the time threshold (in seconds) for logging slow smt queries." in
  Arg.(value & opt (some float) None & info ["slow-smt"] ~docv:"TIMEOUT" ~doc)

let slow_smt_dir =
  let doc = "Set the destination dir for logging slow smt queries (default is in system temp-dir)." in
  Arg.(value & opt (some string) None & info ["slow-smt-dir"] ~docv:"FILE" ~doc)


let no_timestamps =
  let doc = "Disable timestamps in print-level debug messages"
 in
  Arg.(value & flag & info ["no_timestamps"] ~doc)


let json =
  let doc = "output in json format" in
  Arg.(value & flag & info["json"] ~doc)


let state_file =
  let doc = "file in which to output the state" in
  Arg.(value & opt (some string) None & info ["state-file"] ~docv:"FILE" ~doc)

let diag =
  let doc = "explore branching diagnostics with key string" in
  Arg.(value & opt (some string) None & info ["diag"] ~doc)

let lemmata =
  let doc = "lemmata generation mode (target filename)" in
  Arg.(value & opt (some string) None & info ["lemmata"] ~docv:"FILE" ~doc)

let csv_times =
  let doc = "file in which to output csv timing information" in
  Arg.(value & opt (some string) None & info ["times"] ~docv:"FILE" ~doc)

let log_times =
  let doc = "file in which to output hierarchical timing information" in
  Arg.(value & opt (some string) None & info ["log_times"] ~docv:"FILE" ~doc)

let random_seed =
  let doc = "Set the SMT solver random seed (default 1)." in
  Arg.(value & opt int 0 & info ["r"; "random-seed"] ~docv:"I" ~doc)

let solver_logging =
  let doc = "Have Z3 log in SMT2 format to a file in a temporary directory." in
  Arg.(value & flag & info ["solver-logging"] ~doc)

let only =
  let doc = "only type-check this function (or comma-separated names)" in
  Arg.(value & opt (some string) None & info ["only"] ~doc)

let skip =
  let doc = "skip type-checking of this function (or comma-separated names)" in
  Arg.(value & opt (some string) None & info ["skip"] ~doc)


let output_decorated_dir =
  let doc = "output a version of the translation unit decorated with C runtime
  translations of the CN annotations to the provided directory" in
  Arg.(value & opt (some string) None & info ["output_decorated_dir"] ~docv:"FILE" ~doc)

let output_decorated =
  let doc = "output a version of the translation unit decorated with C runtime
  translations of the CN annotations." in
  Arg.(value & opt (some string) None & info ["output_decorated"] ~docv:"FILE" ~doc)

let with_ownership_checking =
  let doc = "Enable ownership checking within CN runtime testing" in
  Arg.(value & flag & info ["with_ownership_checking"] ~doc)

(* copy-pasting from backend/driver/main.ml *)
let astprints =
  let doc = "Pretty print the intermediate syntax tree for the listed languages \
             (ranging over {cabs, ail, core, types})." in
  Arg.(value & opt (list (enum [("cabs", Cabs); ("ail", Ail); ("core", Core); ("types", Types)])) [] &
       info ["ast"] ~docv:"LANG1,..." ~doc)

(* TODO remove this when VIP impl complete *)
let use_vip =
  let doc = "use experimental VIP rules" in
  Arg.(value & flag & info["vip"] ~doc)

let no_use_ity =
  let doc = "(this switch should go away) in WellTyped.BaseTyping, do not use
  integer type annotations placed by the Core elaboration" in
  Arg.(value & flag & info["no-use-ity"] ~doc)

let use_peval =
  let doc = "(this switch should go away) run the Core partial evaluation phase" in
  Arg.(value & flag & info["use-peval"] ~doc)

let no_inherit_loc =
  let doc = "debugging: stop mucore terms inheriting location information from parents" in
  Arg.(value & flag & info["no-inherit-loc"] ~doc)

let magic_comment_char_dollar =
  let doc = "Override CN's default magic comment syntax to be \"/*\\$ ... \\$*/\"" in
  Arg.(value & flag & info ["magic-comment-char-dollar"] ~doc)

(* copied from cerberus' executable (backend/driver/main.ml) *)
let macros =
    let macro_pair =
      let parser str =
	match String.index_opt str '=' with
	  | None ->
	      Result.Ok (str, None)
	  | Some i ->
	      let macro = String.sub str 0 i in
	      let value = String.sub str (i+1) (String.length str - i - 1) in
	      let is_digit n = 48 <= n && n <= 57 in
	      if i = 0 || is_digit (Char.code (String.get macro 0)) then
		Result.Error (`Msg "macro name must be a C identifier")
	      else
		Result.Ok (macro, Some value) in
      let printer ppf = function
	| (m, None)   -> Format.pp_print_string ppf m
	| (m, Some v) -> Format.fprintf ppf "%s=%s" m v in
      Arg.(conv (parser, printer)) in
  let doc = "Adds  an  implicit  #define  into the predefines buffer which is \
             read before the source file is preprocessed." in
  Arg.(value & opt_all macro_pair [] & info ["D"; "define-macro"]
         ~docv:"NAME[=VALUE]" ~doc)

let () =
  let open Term in
  let check_t =
    const main $
      file $
      macros $
      incl_dirs $
      incl_files $
      loc_pp $
      debug_level $
      print_level $
      print_sym_nums $
      slow_smt_threshold $
      slow_smt_dir $
      no_timestamps $
      json $
      state_file $
      diag $
      lemmata $
      only $
      skip $
      csv_times $
      log_times $
      random_seed $
      solver_logging $
      output_decorated_dir $
      output_decorated $
      with_ownership_checking $
      astprints $
      use_vip $
      no_use_ity $
      use_peval $
      batch $
      no_inherit_loc $
      magic_comment_char_dollar
  in
  Stdlib.exit @@ Cmd.(eval (v (info "cn") check_t))

