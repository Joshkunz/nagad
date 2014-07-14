open Sys
open Printf
open Unix 
open List
open KG 
open Query
open HTTP
open Thread
open Mutex
open Jsonm
open JsonExt
open Buffer

let graph = ref (KG.empty ());;
let g = Mutex.create ();;

let is_titlecase s = 
    String.length s > 0 
    && 'A' <= s.[0] && s.[0] <= 'Z';;

(* Yield some cannonical json for the given graph *)
let cjson_for_graph g = 
    let json_for_edge e =
        Object [
             ("label", String e.label)
            ;("to", String e.out)] in
    let json_for_adj_list k v l = 
        (k, Array (List.map json_for_edge v)) :: l in
    Object (KG.Graph.fold json_for_adj_list g []);;

let json_for_graph g = 
    let buf = Buffer.create 100 in
    let enc = Jsonm.encoder (`Buffer buf) in
    cjson_for_graph g
        |> JsonExt.decannonize enc |> ignore;
    Buffer.contents buf;;

let graph_for_json j =
    let parse_edge g k = function 
        | Object [
             ("label", String l)
            ;("to", String t) ] ->
                {KG.head = k; KG.rel = l; KG.tail = t} |> KG.madd_fact g
        | _ -> raise JsonExt.Json_decode_error in
    let parse_adj g = function
        | (k, Array adj) -> List.iter (parse_edge g k) adj
        | _ -> raise JsonExt.Json_decode_error in
    let parse_graph g = function
        | Object adj_lists -> List.iter (parse_adj g) adj_lists
        | _ -> raise JsonExt.Json_decode_error in
    let dec = Jsonm.decoder (`String j) in
    let graph = KG.empty () in
    JsonExt.cannonize dec |> parse_graph graph; graph;;

let query_for_graph g = 
    let item_for_string s = 
        if is_titlecase s then Variable s else Value s in
    let triple_for_edge k l edge = 
        {head = item_for_string k; 
          rel = item_for_string edge.label; 
         tail = item_for_string edge.out} 
        :: l in
    KG.Graph.fold (fun k es l -> List.fold_left (triple_for_edge k) l es) g [];;

(* Cannonical json for a query context *)
let cjson_for_context c = 
    Object (List.map (fun (k, v) -> (k, String v)) c);;

(* Json string for a list of query result pairs *)
let json_for_query_results qr =
    let render_pair (graph, cntxt) = 
        Object [  ("graph", cjson_for_graph graph)
                 ;("context", cjson_for_context cntxt) ] in
    let buf = Buffer.create 100 in
    let enc = Jsonm.encoder (`Buffer buf) in
    Array (List.map render_pair qr)
        |> JsonExt.decannonize enc |> ignore;
    Buffer.contents buf;;

(* Close the connection that backs the given streams *)
let terminate (ic, oc) =
    Unix.shutdown (descr_of_out_channel oc) SHUTDOWN_ALL;
    close_in_noerr ic;
    close_out_noerr oc;;

(* Run the function 'f' over the data-structure 'a' under the lock 'l'.
 * It ensures that the code is always run under with a locked data-structure
 * and that the structure is always unlocked after the function exits. *)
let sync l f a = 
    Mutex.lock l;
    try 
        let out = f a in
        Mutex.unlock l; out;
    with
    | x -> Mutex.unlock l; raise x;;

(* Handle a connection from a client *)
let handle_client (ic, oc, addr) = 
    let open Request in 
    let handle_request request = 
        match request.uri with
        | "/graph" -> 
            begin match request.meth with
            | "GET" -> 
                sync g (fun _ -> json_for_graph !graph) () 
                    |> Response.make 200;
            | "POST" ->
                graph_for_json request.body
                    |> sync g (fun ug -> mjoin_graph_left !graph ug);
                Response.make 200 "";
            | _ -> Response.make 405 ""
            end;
        | "/query" ->
            begin match request.meth with
            | "POST" -> 
                graph_for_json request.body
                    |> query_for_graph
                    |> sync g (fun q -> Query.query_graph !graph q) 
                    |> json_for_query_results
                    |> Response.make 200
            | _ -> Response.make 405 "";
            end;
        | _ -> Response.make 404 "";
    in 
    begin try
        let request = Request.read ic in
        let response = handle_request request in
        printf "%5s %s -> %d (bytes %d)\n" 
            request.meth request.uri
            response.Response.code (String.length response.Response.body);
        flush Pervasives.stdout;
        Response.write oc response;
        terminate (ic, oc);
    with
        | e -> 
            Response.make 500 "" |> Response.write oc;
            terminate (ic, oc);
    end;;

let main port =
    let tcp = (getprotobyname "tcp").p_proto in
    let sock = socket PF_INET SOCK_STREAM tcp in
    setsockopt sock SO_REUSEADDR true;
    ADDR_INET (inet_addr_any, port) |> bind sock;
    listen sock 10;

    printf "Listening for connections on port %d.\n" port; 
    flush Pervasives.stdout;
    let rec accept_loop () = 
        let (csock, addr) = accept sock in
        let (ic, oc) = (in_channel_of_descr csock, out_channel_of_descr csock) in
        Thread.create handle_client (ic, oc, addr) |> ignore;
        accept_loop () in
    accept_loop ();;

main 8080;;
