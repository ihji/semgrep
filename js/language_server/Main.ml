(* Austin Theriault
 *
 * Copyright (C) 2019-2023 Semgrep, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * LICENSE for more details.
 *)

(* Commentary *)
(* This is strongly coupled to [src/osemgrep/language_server] *)
(* This file serves as an interface for the above, that is easily *)
(* consumable by the javascript/node. *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)

open Js_of_ocaml
open Semgrep_js_shared

(*****************************************************************************)
(* Code *)
(*****************************************************************************)

let server = ref (LS.LanguageServer.create ())
let write_ref = ref (fun _ -> failwith "write_ref not set")

(* JS specific IO for the RPC server *)
module Io : RPC_server.LSIO = struct
  let read () = failwith "LSP.js is trying to read from IO, something is wrong"

  let write packet =
    let packet_json =
      packet |> Jsonrpc.Packet.yojson_of_t |> Yojson.Safe.to_string
    in
    !write_ref packet_json;
    Lwt.return_unit

  let flush () = Lwt.return_unit
end

let _ =
  RPC_server.io_ref := (module Io);
  Logs.set_level (Some Logs.Debug);
  Logs.set_reporter { Logs.report = Semgrep_js_shared.console_report };
  Http_helpers.client_ref := Some (module Cohttp_lwt_jsoo.Client);
  Js.export_all
    (object%js
       method init yaml_wasm_module =
         init_jsoo yaml_wasm_module;
         Parse_pattern.parse_pattern_ref := Parse_pattern2.parse_pattern;
         Parse_target.just_parse_with_lang_ref :=
           Parse_target2.just_parse_with_lang

       method setWriteRef f = write_ref := f

       method handleClientMessage json =
         let yojson = Yojson.Safe.from_string json in
         let packet = Jsonrpc.Packet.t_of_yojson yojson in
         Semgrep_js_shared.promise_of_lwt (fun () ->
             let%lwt new_server, response_opt =
               LS.LanguageServer.handle_client_message packet !server
             in
             server := new_server;
             let response_json =
               Option.map Jsonrpc.Packet.yojson_of_t response_opt
               |> Option.map Yojson.Safe.to_string
             in
             Lwt.return (Js.Opt.option response_json))
    end)
