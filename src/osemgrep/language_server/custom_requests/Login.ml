open Lsp.Types
module SN = Lsp.Server_notification
module Conv = Convert_utils
module OutJ = Semgrep_output_v1_t

let meth = "semgrep/login"

let on_request (_server : RPC_server.t) __params : Yojson.Safe.t option =
  if Semgrep_login.is_logged_in () then (
    RPC_server.notify_show_message ~kind:MessageType.Info
      "Already logged in to Semgrep Code";
    None)
  else
    let id, uri = Semgrep_login.make_login_url () in
    Some
      (`Assoc
        [
          ("url", `String (Uri.to_string uri));
          ("sessionId", `String (Uuidm.to_string id));
        ])
