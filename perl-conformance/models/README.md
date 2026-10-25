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
