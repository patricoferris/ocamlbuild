(***********************************************************************)
(*                                                                     *)
(*                             ocamlbuild                              *)
(*                                                                     *)
(*  Nicolas Pouillard, Berke Durak, projet Gallium, INRIA Rocquencourt *)
(*                                                                     *)
(*  Copyright 2007 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)


(* Original author: Nicolas Pouillard *)
open My_std

let is_simple_filename s =
  let ls = String.length s in
  ls <> 0 &&
  let rec loop pos =
    if pos >= ls then true else
    match s.[pos] with
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '.' | '-' | '/' | '_' | ':' | '@' | '+' | ',' -> loop (pos + 1)
    | _ -> false in
  loop 0
let quote_filename_if_needed s =
  if is_simple_filename s then s
  (* We should probably be using [Filename.unix_quote] except that function
   * isn't exported. Users on Windows will have to live with not being able to
   * install OCaml into c:\o'caml. Too bad. *)
  else if Sys.os_type = "Win32" then Printf.sprintf "'%s'" s
  else Filename.quote s
let chdir dir =
  reset_filesys_cache ();
  Sys.chdir dir
let run args target =
  reset_readdir_cache ();
  let cmd = String.concat " " (List.map quote_filename_if_needed args) in
  if !*My_unix.is_degraded || Sys.os_type = "Win32" then
    begin
      Log.event cmd target Tags.empty;
      let st = sys_command cmd in
      if st <> 0 then
        failwith (Printf.sprintf "Error during command `%s'.\nExit code %d.\n" cmd st)
      else
        ()
    end
  else
    match My_unix.execute_many ~ticker:Log.update ~display:Log.display [[(fun () -> cmd)]] with
    | None -> ()
    | Some(_, x) ->
      failwith (Printf.sprintf "Error during command %S: %s" cmd (Printexc.to_string x))
let rm = sys_remove
let rm_f x =
  if sys_file_exists x then ()
  else
    (* We checked that the file does not exist, but we still ignore
       failures due to the possibility of race conditions --
       another thread having removed the file at the same time.

       See issue #300 and PR #302 for a race-condition in the wild,
       and a reproduction script.

       We could reproduce such races due to the Shell.rm_f call on the log file
       at the start of ocamlbuild's invocation. *)
    try sys_remove x with _ -> ()

let mkdir dir =
  reset_filesys_cache_for_file dir;
  (*Sys.mkdir dir (* MISSING in ocaml *) *)
  run ["mkdir"; dir] dir

let try_mkdir dir =
  if not (sys_file_exists dir)
  then
    (* We checked that the file does not exist, but we still
       ignore failures due to the possibility of race conditions --
       same as rm_f above.

       Note: contrarily to the rm_f implementation which uses sys_remove directly,
       the 'mkdir' implementation uses 'run', which will create noise in the log
       and on display, especially in case of (ignored) failure: an error message
       will be shown, but the call will still be considered a success.
       Error messages only occur in racy scenarios that we don't support,
       so this is probably okay. *)
    try mkdir dir with _ -> ()

let rec mkdir_p dir =
  if sys_file_exists dir then ()
  else begin
      mkdir_p (Filename.dirname dir);
      try_mkdir dir
    end

let cp_pf src dest =
  reset_filesys_cache_for_file dest;
  run["cp";"-pf";src;dest] dest

(* Archive files are handled specially during copy *)
let cp src dst =
  if Filename.check_suffix src ".a"
  && Filename.check_suffix dst ".a"
  then cp_pf src dst
  (* try to make a hard link *)
  else copy_file src dst

let readlink = My_unix.readlink
let is_link = My_unix.is_link
let rm_rf x =
  reset_filesys_cache ();
  run["rm";"-Rf";x] x
let mv src dest =
  reset_filesys_cache_for_file src;
  reset_filesys_cache_for_file dest;
  run["mv"; src; dest] dest
  (*Sys.rename src dest*)
