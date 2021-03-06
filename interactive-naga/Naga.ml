open Sys
open Printf
open Lexing
open Parsing
open Common
open Datalog
open DatalogParse
open DatalogLex
open List
open Fact
open Query
open Dot

type parse_result = Empty | NoData | ParseError | Parsed of Datalog.classified;;

let print_help () = 
    print_string @@ 
"Commands:
fact(a, b, c).      Add a fact to the database.
facts.              Display facts in the fact base.
facts(name).        Write a list of the facts in the fact base to a file
                    named 'name', any files with the same name are
                    overwritten.
finish. end. done.  
    exit.           Exits the program
graph.              Print out the DOT representation of this graph.
graph(name).        Write out a PDF of the knowledge graph to a file named
                    'name'. Overwrites any file with that name in this
                    directory.
source(name).       Read and run all commands in the file named 'name' with
                    the current fact database. This can be used to load
                    fact databases saved previously with the 'facts' command,
                    or to automate queries in an interactive session.
help. commands.     Print this message.
";;

let fact_for_statement s = 
    let rec value_list = function
        | [] -> [];
        | Value(x) :: xs -> x :: value_list xs;
        | _ -> raise (Failure "fact_for_statement: Not a statement.");
    in
    Fact.fact_for_list @@ value_list s.body;;

let show_results (s : Datalog.statement) results =
    let rec textual index results = 
        match results with 
        | [] -> "End of results.\n"
        | q :: qs ->
              (sprintf "Result %i:\n" index)
            ^ (Fact.string_for_facts q)
            ^ (textual (index + 1) qs)
    in
    let node_for_node index e n =
        try 
            List.find ((=) n) e |> ignore; 
            ("", e); (* Will only be returned if List.find doesn't throw
                        an exception to the lookup *)
        with
        | Not_found -> 
            ((quoted (n ^ index)) ^ " [label=" ^ (quoted n) ^ "];\n", n :: e)
    in
    let rec nodes_for_fdb index e fdb = 
        match fdb with 
        | [] -> ""
        | f :: fs ->
            let (result1, db1) = node_for_node index e f.head in
            let (result2, db2) = node_for_node index db1 f.tail in
            result1 ^ result2 ^ (nodes_for_fdb index db2 fs)
    in
    let edge_for_fact index f =
        sprintf "\"%s%s\" -- \"%s%s\" [label=%s];\n" 
            f.head index f.tail index (quoted f.rel)
    in
    let rec subgraph index facts =
        match facts with
        | [] -> ""
        | f :: fs ->
            (edge_for_fact index f) ^ (subgraph index fs)
    in
    let rec _graph index results = 
        match results with
        | [] -> ""
        | r :: rs ->
            let rnum = (string_of_int index) in
            (sprintf "subgraph cluster%s {\n" rnum) ^
            (nodes_for_fdb rnum [] r) ^
            (subgraph rnum r) ^
            "}\n" ^ (_graph (succ index) rs)
    in
    let graph results = 
        "graph {\n" ^ (_graph 0 results) ^ "}\n"
    in
    match s.head with 
    | "text" ->
        begin
        match s.body with 
        | [] -> textual 0 results |> print_string;
        | Value (name) :: [] -> 
            let f = open_out name in
            textual 0 results |> output_string f;
            close_out f
        | _ -> raise (Failure "Case not Handled.")
        end
    | "graph" ->
        begin
        match s.body with
        | [] -> graph results |> print_string
        | Value(name) :: [] ->
            let f = open_out name in
            let (status, pdf) = graph results |> Dot.pdf_for_dot in
            output_string f pdf;
            close_out f;
        | _ -> raise (Failure "Case not handled.")
        end
    | _ -> raise (Failure "Unknown query output.");;

let parse_source ch =
    Lexing.from_channel ch |> 
    DatalogParse.program (DatalogLex.token DatalogLex.gen_eof) |>
    Datalog.classify_program

let eval_operation query_handler statement_handler operation fdb = 
    match operation with
    | Implication (i) ->
        query_handler fdb (show_results i.implied) i.by; 
        Some fdb;
    | Query (q) ->
        query_handler fdb (show_results {head="text"; body=[]}) q;
        Some fdb;
    | Statement (s) ->
        statement_handler fdb s;;

let rec eval_program qh sh program fdb = 
    match program with 
    | [] -> fdb
    | o :: os ->
        begin
        match eval_operation qh sh o fdb with
        | Some fdb -> eval_program qh sh os fdb
        | None -> fdb
        end;;

let handle_query fdb handler q = 
    let item_for_value = function 
        | Value v -> Query.Value v
        | Variable v -> Query.Variable v in
    let triple_for_body = function
        | a :: b :: c :: [] -> (a, b, c)
        | _ -> raise (Failure "triple_for_body: To many items.") in
    let triple_for_statement s =
        List.map item_for_value s.body |> triple_for_body in
    let query = List.map triple_for_statement q in
    Query.query_graph query fdb |> handler;;

let rec handle_statement fdb (s : Datalog.statement) = 
    match s.head with
    | "source" ->
        begin match s.body with
        | [] -> 
            print_endline "Source statement doesn't have enough parameters.";
            Some fdb;
        | Value(name) :: [] ->
            Some (eval_program handle_query handle_statement 
                    (open_in name |> parse_source) fdb)
        |_ -> 
            print_endline "Source statement has too many parameters.";
            Some fdb;
        end;
    | "facts" ->
        begin
        match s.body with
        | [] when is_empty fdb ->
            print_string "(empty)\n";
        | [] -> Fact.display_facts fdb;
        | Value(name) :: [] -> 
            let f = name ^ ".facts" |> open_out in
            Fact.string_for_facts fdb |> output_string f;
            close_out f;
        | _ ->
            print_endline "Facts statement has too many parameters.";
        end;
        Some fdb;
    | "graph" ->
        begin
        match s.body with
        | [] -> 
            print_string @@ (Fact.fact_graph fdb) ^ "\n";
        | Value(name) :: [] ->
            let f = open_out @@ name in
            let (status, pdf) = Fact.fact_graph fdb |> Dot.pdf_for_dot in
            output_string f pdf;
            close_out f;
        | _ ->
            print_endline "Graph statement has too many parameters."
        end;
        Some fdb;
    | "fact" ->
        let fact = fact_for_statement s in
        (match fact with
         | None ->
             print_string "That is not a valid fact.\n";
             Some fdb;
         | Some f ->
             Some (f :: fdb));
    | "help" | "commands" ->
        print_help (); Some fdb;
    | "finish" | "end" | "exit" | "done" -> None;
    | _ ->
        print_string @@ "That is not a valid command.\n";
        Some fdb;;

let try_parse s =
    try 
    let parsed = Lexing.from_string s |> 
                 DatalogParse.operation 
                    (DatalogLex.token DatalogLex.throw_eof) |>
                 Datalog.classify in Parsed parsed
    with 
    | Parse_error -> 
        print_string "Got a parse error exception.\n";
        ParseError;
    | DatalogLex.Eof -> NoData;;

let rec frepl buf fdb =
    let eval_repl = eval_operation handle_query handle_statement in
    if buf = "" then
        print_string "> "
    else
        print_string "... ";
    let line = (read_line ()) ^ "\n" in
    let cbuf = buf ^ line in
    match try_parse cbuf with
    | ParseError -> 
        print_string "Invalid statement.\n";
        frepl "" fdb;
    | NoData ->
        frepl cbuf fdb;
    | Empty ->
        assert (buf = "");
        frepl "" fdb;
    | Parsed p ->
        begin
        match eval_repl p fdb with
        | Some fdb -> frepl "" fdb
        | None -> fdb
        end;;

let repl () = 
    frepl "" [];;

open Array
let main () =
    let eval_prog = eval_program handle_query handle_statement in
    match Sys.argv with
    | [| _ |] -> repl () |> ignore
    | [| _; "-f"; n |] -> eval_prog (open_in n |> parse_source) [] |> ignore
    | _ -> print_endline "Unrecognized flags.";;

main ();;
