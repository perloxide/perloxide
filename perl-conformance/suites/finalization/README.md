# Finalization suite

28 programs pinning when objects die and what their destructors see, at program level: the reference for an
implementation's object lifetime, as `models/Finalization` is the reference for the machinery behind it.  Each case
states its claim in a comment at the top and prints what decides it; expected stdout and stderr per Perl, with the exit
status appended.

| Group | Cases    | Claims                                                                                                                                                                                                                |
|-------|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| R     | R01-R06  | release: scope exit in reverse declaration order, array clear from the top index down, a holder before what it holds, only the last of several holders, the new value installed before `DESTROY`, cycles outliving their scope |
| W     | W01-W06  | weak references: cleared by the last strong release, a copy of a weak reference is strong, weakening the only reference, still defined inside `DESTROY`, `unweaken`, weak elements cleared in place                    |
| U     | U01-U07  | the destructor protocol: resurrection, a dying `DESTROY` as an `(in cleanup)` warning, `$@` surviving a destructor's `eval`, rebless running the new class's `DESTROY`, `AUTOLOAD` called for `DESTROY`, arguments and phase, `.=` deferring death |
| G     | G01-G05  | global destruction: file lexicals before `END` in phase `RUN`, package variables after `END` in `DESTRUCT`, a leaked cycle reaped, `exit` and an uncaught `die` unwinding frames before `END`                          |
| T     | T01-T04  | temporaries: a void temporary at its statement's end, condition temporaries after an `if` body and before a `while` body, `foreach` list temporaries until the loop is left, a sub's return value                    |

    ./run.sh /path/to/interpreter [VERSION]

Blessed on 5.44.0 (`expected/5.44.0/`).  Every case prints the same on all six 5.44.0 builds and on the unsupported
5.38.2, each run three times under different hash seeds: no case depends on an address, on the order of a hash with more
than one key, or on the arena walk of global destruction, where every case keeps one object (the order among several
follows allocation history: `../../facts.md`, `identity.global-destruction-order`).  Blessed outputs never end a line in
whitespace (`tools/lint-blessed.sh`).
