(* lib/http_client.ml *)
open Lwt.Infix

let confirm_url = Uri.of_string "http://127.0.0.1:5001/confirmar"
let cancel_url  = Uri.of_string "http://127.0.0.1:5001/cancelar"

let json_of_txn_id id =
  Yojson.Safe.to_string (`Assoc [ "transaction_id", `String id ])

let post_json uri body =
  let headers = Cohttp.Header.init_with "Content-Type" "application/json" in
  Cohttp_lwt_unix.Client.post ~headers ~body:(`String body) uri >>= fun (resp, body_stream) ->
  Cohttp_lwt.Body.drain_body body_stream >>= fun () ->
  let code = Cohttp.Response.status resp |> Cohttp.Code.code_of_status in
  Lwt.return code

let confirm id =
  let body = json_of_txn_id id in
  post_json confirm_url body >>= fun status ->
  Logs.info (fun f -> f "✅ Confirmation for %s returned %d" id status);
  Lwt.return_unit

let cancel id =
  let body = json_of_txn_id id in
  post_json cancel_url body >>= fun status ->
  Logs.info (fun f -> f "❌ Cancellation for %s returned %d" id status);
  Lwt.return_unit
