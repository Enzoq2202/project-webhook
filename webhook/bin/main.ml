(* bin/main.ml *)

let () =
  (* read PORT from env or default to 5000 *)
  let port =
    match Sys.getenv_opt "PORT" with
    | Some p -> int_of_string p
    | None   -> 5000
  in

  (* print a startup banner and flush immediately *)
  Printf.printf "🚀 Webhook server starting on port %d\n%!" port;
  Printf.printf "📡 Listening for POST /webhook at http://localhost:%d/webhook\n%!" port;

  (* now actually run the Dream/Cohttp server from your library *)
  Lwt_main.run (Webhook.start_server ~port ())
