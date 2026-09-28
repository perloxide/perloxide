# Probes

Single-fact programs, in two tiers.

`corpus/` is the harness-run corpus: every program runs under `harness/bin/oracle` on the pinned Perl and its two
allocator-instrumented variants in three hash modes, and `corpus/expected/<test>/` holds its blessed verdict and
normalized outputs.  This is the tier `bin/oracle check` runs an implementation against.  Each program's rule is cited
in `harness/sources.md`.

`research/` holds probe sets recorded during the design research that produced the reference, with their outputs per
Perl as recorded and their research notes.  They are facts with demonstrations, but they were recorded directly rather
than through the harness; a probe promoted into `corpus/` gets a harness run and a blessed verdict.

- `research/foundations/`: the first set -- address identity and reuse, `local` on scalars and elements, `each` under
  mutation, hash ordering modes, `DESTROY` order, the warn-handler numification window.
- `research/value-model/`: probes 01-23 with notes `results-1.md` to `results-3.md` -- `local` on tied variables,
  `DESTROY` timing, the two-slot reentry rule, Dumper and JSON::PP as flag consumers, `-0`, constants as mutable flag
  cells, pad reuse, the locale radix, closure re-arming, flags synthesis, `isdual` reading private flags.
- `research/value-flags/`: the consumer matrix, the locale radix probes, the flag, pad-reuse, and `threads::shared`
  probes.
