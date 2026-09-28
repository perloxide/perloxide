# Probes

Single-fact programs, in two tiers.

`corpus/` is the harness-run corpus: every program runs under `harness/bin/oracle` on the pinned Perl and its two
allocator-instrumented variants in three hash modes, and `corpus/expected/<test>/` holds its blessed verdict and
normalized outputs.  This is the tier `bin/oracle check` runs an implementation against.  Each program's rule is cited
in `harness/sources.md`.

`research/` holds probe sets recorded during the design research that produced the reference, with their outputs per
Perl as recorded and their research notes.  They are facts with demonstrations, but they were recorded directly rather
than through the harness; a probe promoted into `corpus/` gets a harness run and a blessed verdict.
