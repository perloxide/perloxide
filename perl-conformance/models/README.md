# Models

Executable transcriptions of one area each of perl's C, validated by replaying perl's own observed behavior through them
(`../README.md`, Models).  Each lives in its own directory with the model, its section text, its generators, its reports
and its source-validation record; the package is `Perl::Conformance::Model::<Name>`, loaded by path from the model's
directory.

| Directory       | Package                                  | Area                                                        | Former code |
|-----------------|------------------------------------------|-------------------------------------------------------------|-------------|
| `ValueFlags/`   | `Perl::Conformance::Model::ValueFlags`   | value flags: numification, stringification, the caches      | VF          |
| `SaveStack/`    | `Perl::Conformance::Model::SaveStack`    | `local` and the save stack                                  | SS          |
| `Finalization/` | `Perl::Conformance::Model::Finalization` | finalization and temporary lifetime                         | FZ          |
| `HashEngine/`   | `Perl::Conformance::Model::HashEngine`   | the hash engine: hashing, splitting, iteration, destruction | HV          |
| `StringFlags/`  | `Perl::Conformance::Model::StringFlags`  | the UTF-8 flag and taint                                    | PV          |

The former two-letter codes survive in the research logs (`ValueFlags/README.md` especially), in report file names and
in report headers, where they are the names those records were made under.

## Uses beyond the harness

The harness replays the models to classify what perl does; the models answer the same questions for anyone else.  The
value-flags model predicts the flag state a value will have after a sequence of operations, which is what decides
whether a serializer emits a number or a string; the save-stack model says what `local` on a tied, shared or absent
element will do at unwind; the finalization model predicts `DESTROY` order and timing for a scenario; the hash engine
reproduces perl's key order for a seed and an insertion sequence without running perl, and is the specification for
implementing perl-compatible hashing elsewhere; the string-flags model predicts UTF-8 flag and taint propagation through
string operations.  Across all of them, a replay that disagrees with a new perl is a change in perl's implementation
since the transcribed tag, found without a test that happened to cover it (`source-validation.txt` in each directory).

## Tables and replay

Each model's generator records what perl did -- never what the model said -- in a factored table under `reports/`
(`lib/Perl/Conformance/Table.pm`): one column per axis of the enumeration, one line per distinct result with the set of
values of one folded axis and the set of versions it holds for, so the full product is never stored and a new version
adds only the lines it changed.  A version is a Perl named as its perlbrew build is (`5.44.0`, `5.44.0-threads`,
`5.44.0-noreuse`); `5.44.0-*` is every build of 5.44.0 the table holds and `*` every version, and a row that an
enumeration does not produce on some build (one that needs ithreads, on an unthreaded build) is simply absent there.  A
model with one enumeration keeps it in `reports/table.tsv`; one with several names each (`reports/NAME.tsv`).

    perl-conformance table MODEL[/NAME] expand [--target V]        the product at one version
    perl-conformance table MODEL[/NAME] lookup ROW... [--target V] one row's record
    perl-conformance table MODEL[/NAME] diff V1 V2                 the rows whose records differ
    perl-conformance table MODEL[/NAME] versions                   the versions the table holds
    perl-conformance replay MODEL[/NAME] [--target V]              the model against the table, no perl involved

A generator run whose `TAG` is a version merges that run into the table and prints a report line with the run's row
counts and the SHA-256 of its raw table; `reports/<code>.<version>.txt` is that report with the mismatches.  `replay`
runs the same generator with `REPLAY=1`, which looks every row up in the table instead of running perl: its mismatches
are the model's open gaps at that version as the repository records them, and a row the enumeration would produce that
the table lacks is counted as absent.  A gap is therefore a fact about the repository, computable at any time, not only
a line in the report of the run that found it.
