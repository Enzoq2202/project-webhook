(* lib/transaction_store.ml *)
let table : (string, unit) Hashtbl.t = Hashtbl.create 1024

let is_duplicate id =
  Hashtbl.mem table id

let mark_processed id =
  Hashtbl.replace table id ()
