Naive implementation of the naga query language and graph representation based
heavily on the algorithms given in the naga paper.

# Status:

* Parsing fact statements given on standard in into a fact table.
* Generating textual DOT graphs of the fact table.
* Parsing Queries (but not executing them yet).

# Building and Running:

First things first you're going to need is an OCaml compiler/interpreter. You
can usually obtain this using your OS's package manager. For example, on OSX
you can run `brew install ocaml`, or on Debian based Linux distros you can run
`apt-get install ocaml`.

To make naga, simply run the 'make' command, and then invoke the generated
'naga' binary.

    $ make
        ...
    $ ./naga

When invoked, the NAGA binary will start a command oriented REPL, you can
see the list of commands from within the REPL by running `help.` from
within the REPL. The Full Documentation is given in the following section.

# Documentation

> *Note:* this documentation can be generated by running `help_full.` in the
> naga REPL.

The Naga REPL language is a simple Line-oriented Datalog-like language.
The system is manipulated by putting a command on each input line. A command
is of the form: 

    NAME.

or of the form:

    NAME(a [, b]*).

where the period is significant. A listing of the commands understood 
by the system is given below.

Additionally, data in the system can be retrieved through queries. A query is of
the form:

    :- command [, command]*.

These commands can be split across multiple physical lines by ending the line
with a backslash (\\). For example:

    :- foo, bar(a, b, c) \
       baz(z, e, q).

Whitespace is not significant in the language. Queries are not currently
implemented.

Commands:

|   |   |
|---|---|
| `fact(a, b, c).` | Add a fact to the database.|
|`facts.` | Display facts in the fact base. |
| `facts(name).` | Write a list of the facts in the fact base to a file named 'name.facts', any files with the same name are overwritten. |
| `graph.` | Print out the DOT representation of this graph. |
| `graph(name).` | Write out a PDF of the knowledge graph to a file named 'name.pdf'. Overwrites any file with that name in this directory. |
| `finish.`, `end.`, `done.` | Exit the program. |
| `help.` | Print this message. |
| `help_full.` | Print a much longer help message. |
