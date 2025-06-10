(* lib/webhook.ml *)
open Lwt.Infix
open Cohttp
open Cohttp_lwt_unix
open Sqlite3

(* Shared secret for token validation *)
let valid_token =
  Sys.getenv_opt "WEBHOOK_TOKEN"
  |> Option.value ~default:"meu-token-secreto"

(* HMAC secret for payload integrity (optional) *)
let hmac_secret =
  Sys.getenv_opt "WEBHOOK_HMAC_SECRET"
  |> Option.value ~default:""

(* Initialize SQLite DB and table *)
let db =
  let d = db_open "webhooks.db" in
  let sql = {|
    CREATE TABLE IF NOT EXISTS transactions (
      transaction_id TEXT PRIMARY KEY,
      amount REAL,
      currency TEXT,
      timestamp TEXT,
      status TEXT
    );|} in
  (match exec d sql with
   | Rc.OK -> ()
   | rc -> prerr_endline ("SQLite init error: " ^ Rc.to_string rc));
  d

let persist_transaction ~txn_id ~amount ~currency ~timestamp ~status =
  let stmt = prepare db {|
    INSERT OR REPLACE INTO transactions
      (transaction_id, amount, currency, timestamp, status)
    VALUES (?, ?, ?, ?, ?);
  |} in
  bind stmt 1 (Data.TEXT txn_id) |> ignore;
  bind stmt 2 (Data.FLOAT amount) |> ignore;
  bind stmt 3 (Data.TEXT currency) |> ignore;
  bind stmt 4 (Data.TEXT timestamp) |> ignore;
  bind stmt 5 (Data.TEXT status) |> ignore;
  match step stmt with
  | Rc.DONE -> finalize stmt |> ignore
  | rc -> prerr_endline ("SQLite persist error: " ^ Rc.to_string rc); finalize stmt |> ignore

(* Compute HMAC-SHA256 signature *)
let compute_signature body =
  let h = Digestif.SHA256.hmac_string ~key:hmac_secret body in
  Digestif.SHA256.to_hex h

(* Parse + validate incoming JSON in one shot *)
let parse_and_validate body_str =
  try
    let open Yojson.Safe.Util in
    let json = Yojson.Safe.from_string body_str in
    let get field =
      match member field json with
      | `String s when s <> "" -> Some s
      | `Int i                 -> Some (string_of_int i)
      | `Float f               -> Some (string_of_float f)
      | _                      -> None
    in
    let event      = get "event"
    and txn_id     = get "transaction_id"
    and amount_str = get "amount"
    and currency   = get "currency"
    and timestamp  = get "timestamp" in
    match event, txn_id, amount_str, currency, timestamp with
    | Some ev, Some id, Some amt_s, Some cur, Some ts -> (
        match float_of_string_opt amt_s with
        | Some amt when amt > 0.0 -> Ok (ev, id, amt, cur, ts)
        | _ -> Error `Bad_amount
      )
    | _ -> Error `Missing_fields
  with Yojson.Json_error _ -> Error `Invalid_json

let server_callback _conn (req : Request.t) body =
  let uri  = Request.uri req in
  let meth = Request.meth req in
  match meth, Uri.path uri with
  | `POST, "/webhook" ->
    (* 1) Read body *)
    Cohttp_lwt.Body.to_string body >>= fun body_str ->

    (* 2) Token validation *)
    let token_ok =
      match Header.get (Request.headers req) "x-webhook-token" with
      | Some t when t = valid_token -> true
      | _ -> false
    in
    if not token_ok then
      Server.respond_string ~status:`Unauthorized ~body:"Invalid token" ()
    else
      (* 3) Optional HMAC check *)
      (match (hmac_secret, Header.get (Request.headers req) "x-webhook-signature") with
       | (key, Some received) when key <> "" ->
           if received = compute_signature body_str then Lwt.return_unit
           else Lwt.fail_with "Invalid signature"
       | _ -> Lwt.return_unit
      ) >>= fun () ->

      (* 4) Parse + validate *)
      (match parse_and_validate body_str with
       | Error `Invalid_json ->
         persist_transaction ~txn_id:"" ~amount:0.0 ~currency:"" ~timestamp:"" ~status:"invalid_json";
         Http_client.cancel "" >>= fun () ->
         Server.respond_string ~status:`Bad_request ~body:"Invalid JSON" ()

       | Error (`Missing_fields | `Bad_amount) ->
         let txn_id =
           try Yojson.Safe.from_string body_str
               |> Yojson.Safe.Util.member "transaction_id"
               |> Yojson.Safe.Util.to_string
           with _ -> ""
         in
         persist_transaction ~txn_id ~amount:0.0 ~currency:"" ~timestamp:"" ~status:"bad_payload";
         (if txn_id <> "" then Http_client.cancel txn_id else Lwt.return_unit) >>= fun () ->
         Server.respond_string ~status:`Bad_request ~body:"Bad payload" ()

       | Ok (_ev, id, amt, cur, ts) ->
         if Transaction_store.is_duplicate id then (
           persist_transaction ~txn_id:id ~amount:amt ~currency:cur ~timestamp:ts ~status:"duplicate";
           Server.respond_string ~status:`Conflict ~body:"Duplicate" ()
         ) else (
           Transaction_store.mark_processed id;
           persist_transaction ~txn_id:id ~amount:amt ~currency:cur ~timestamp:ts ~status:"confirmed";
           Http_client.confirm id >>= fun () ->
           Server.respond_string ~status:`OK ~body:"Confirmed" ()
         )
      )
  | _ -> Server.respond_not_found ~uri ()

let start_server ~port () =
  Printf.printf "🚀 Server listening on port %d (POST /webhook)\n%!" port;
  let callback = server_callback in
  let config   = Server.make ~callback () in
  Server.create ~mode:(`TCP (`Port port)) config
