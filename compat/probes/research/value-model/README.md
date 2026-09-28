# Research probes: the value model (sets 2-4)

Numbered probes (`01`-`23`) from the value-model research, each demonstrating one fact, with
outputs per perl under `out/perl-<version>/` and the research records `results-1.md`,
`results-2.md`, `results-3.md`. Topics: `local` on scalars, elements, and tied variables;
`DESTROY` timing in conditions, void context, and two-statement bodies; numification through a
`__WARN__` handler and the two-slot reentry rule; Dumper and JSON::PP as flag consumers; `-0`;
compiled constants as mutable flag cells; `each` semantics and hash clear; pad reuse; flag
projections through `Devel::Peek`; the locale radix; `DESTROY` inside an op observing the new
state; closure re-arming; the 864-cell reentry matrix (`suites/reentry-matrix-864`); flags
synthesis; the stash-reachable graph walk (`measurements/`); `isdual` reading the private flags.

The 864-cell matrix driver (`18_warnmut_matrix.pl`) and its model live in
`suites/reentry-matrix-864`; `walk_stash.pl` and `bench_walk.rs` in `measurements`.
