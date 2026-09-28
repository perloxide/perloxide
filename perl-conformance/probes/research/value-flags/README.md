# Research probes: value flags

Single-fact probes from the value-flags research, with their outputs per Perl where recorded:

- `consumers.pl` (+ `.out` per Perl): for each (start kind, op), which stdout consumers change -- `isdual`, Data::Dumper
  XS and pure-Perl, JSON::PP, `created_as_*`, `Storable::freeze`.  The result: of every flag a packed integer or float
  can acquire, only `Int`+`pPOK` (via `isdual`) and integral-`Float`+public `IOK` (via Dumper) reach stdout.
- `locale.pl` (+ `.out`): the radix probes -- the numeric cache freezes whichever locale parsed first, copies carry it
  across locales, stringification is locale-sensitive at output time only.
- `p1_flags.pl`, `p1b.pl`-`p1e.pl`: flag observations (`fl.pm` is the shared printer).
- `p2.pl`: pad reuse and the `same distinct AAB` address pattern.
- `p3.pl`: the alias suite's precursor.
- `p4.pl`: `threads::shared` and `local` (see `undefined.md`).
- `aliasing_bench.c`: per-iteration cost of registry-plus-proxy versus promote-on-bind (a measurement, not a fact about
  Perl; kept with the probes it accompanied).

These run under the oracle harness like any probe (`harness/bin/oracle run ../probes`), though their blessed outputs
here were recorded directly.
