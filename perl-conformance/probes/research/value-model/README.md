# Research probes: the value model (sets 2-4)

Numbered probes (`01`-`26`) from the value-model research, each demonstrating one fact, with outputs per perl under
`out/perl-<version>/` and the research records `results-1.md`, `results-2.md`, `results-3.md`. Topics: `local` on
scalars, elements, and tied variables; `DESTROY` timing in conditions, void context, and two-statement bodies;
numification through a `__WARN__` handler and the two-slot reentry rule; Dumper and JSON::PP as flag consumers; `-0`;
compiled constants as mutable flag cells; `each` semantics and hash clear; pad reuse; flag projections through
`Devel::Peek`; the locale radix; `DESTROY` inside an op observing the new state; closure re-arming; the 864-cell reentry
matrix (`suites/reentry-matrix-864`); flags synthesis; the stash-reachable graph walk (`measurements/`); `isdual`
reading the private flags; `local` on a `threads::shared` element under a structural move (`24`, which needs a perl
built with ithreads -- the recorded 5.44.0 output is from a `-Dusethreads` build of the same tag); a tied weak holder's
`STORE(undef)` observing the later holders still uncleared (`25`; every `MODE` but `observe` is the undefined window in
`undefined.md` and is not recorded); `weaken` on a tied element, where the holder is the element proxy and its set magic
is the tie's `STORE` (`26`).

The 864-cell matrix driver (`18_warnmut_matrix.pl`) and its model live in `suites/reentry-matrix-864`; `walk_stash.pl`
and `bench_walk.rs` in `measurements`.
