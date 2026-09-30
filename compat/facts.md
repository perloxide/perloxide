# Facts

The prose index of the reference: every established fact about Perl's behavior, grouped by area, each entry naming the
rule, the Perl function that fixes it, and the probe or model row that demonstrates it on the pinned Perl
(`profile.md`).  A fact appears here only with that demonstration; a rule without one is not admitted.  Dense areas
point at their model's section text instead of restating the transition function.

Nothing here is about any implementation of Perl.  What an implementation does where Perl's behavior is undefined
(`undefined.md`) is that implementation's own record.

## Value flags

The string and numeric forms of a scalar, the per-value flags recording which forms have been derived (public or
private, `IsUV`, derived-from-integer, private-only, stringified), the copy-on-write state and buffer length that decide
later transitions, and the `Dual` case.

Section: `models/VF/section.md`.  Model: `models/VF/VF.pm`.  Verification: `models/VF/reports/coverage.txt`.  Probes:
`probes/research/value-flags/`, `probes/research/value-model/` (01, 07-11, 15, 17, 18, 22, 23).  Suites:
`suites/reentry-matrix`, `suites/reentry-matrix-864`, `suites/reentry-6840`, `suites/transitions`.

Entries: to be filled from the section text.

## `local` and the save stack

Section: `models/SS/section.md`.  Model: `models/SS/SS.pm` (312 cells, both Perls).  Probes:
`probes/research/value-model/` (01-03), `probes/corpus/local_*`, `probes/corpus/tie_*`.

Entries:

- The save record for an element holds the element's SV, not its value: a reference taken before the `local` names that
  SV, reads the pre-`local` value throughout the scope, and a write through it is what the restore brings back.
  `Perl_save_aelem_flags`, `Perl_leave_scope` (`SAVEt_AELEM`).  Probe: `probes/corpus/local_elem_sv_identity.pl`.
- The SV that `local` installs is an ordinary element: a structural operation (`shift`, `unshift`, `splice`) moves it
  and may return it to the program, and it lives on afterward with the localized value; nothing reclaims it at scope
  exit. Undocumented; the same probe.
- The restore is by the original index into whatever the array has become (`av_fetch(av, idx, 1)` in
  `Perl_leave_scope`): the saved SV goes back at that index whatever now occupies it, and an emptied array is extended
  to reach it. perlsub documents the extension; the same probe.
- The extension leaves the skipped slots as holes (`exists` false), not undef elements (`av_store` fills intermediate
  entries with NULL). perlsub says "filling in the skipped elements with `undef`", which is not what happens. The same
  probe.

## Finalization and temporary lifetime

Section: `models/FZ/section.md`.  Model: `models/FZ/FZ.pm` (114 scenarios, both Perls).  Probes:
`probes/research/value-model/` (04-06, 16, 19, 21), `probes/corpus/destroy_*`, `probes/corpus/gd_*`.

## The hash engine

Section: `models/HV/section.md`.  Model: `models/HV/HV.pm` (bucket-level and program-level lanes, both Perls).  Probes:
`probes/research/value-model/` (12, 13), `probes/corpus/each_*`, `probes/corpus/order_*`.

## The UTF-8 flag and taint

Section: `models/PV/section.md`.  Model: `models/PV/PV.pm` (in progress; `status.md`).

## Element aliasing

Suite: `suites/aliasing` (27 cases, 25 identical on both Perls, 2 undefined in Perl).

## Arrays

Entries:

- `shift` and `pop` return the element's SV itself, not a copy: a reference taken to the returned value has the address
  the element had in the array. `Perl_av_shift`, `Perl_av_pop`.  Probe: `probes/corpus/local_elem_sv_identity.pl`.
- An array's storage is an array of `SV*` and a NULL entry is a hole: `delete` on a middle element, `$#a =` growth, and
  a store past the end all leave holes, which `exists` reports as absent while `scalar(@a)` counts them. Lvalue-context
  access -- `\$a[i]`, `\(@a)`, `foreach` aliasing, passing `$a[i]` to a sub -- vivifies a hole into a fresh SV
  (`Perl_av_fetch` with `lval`). The same probe.

## Address identity, literal cells, and global destruction

Probes: `probes/corpus/addr_*`, `probes/corpus/consts_*`, `probes/corpus/gd_*`, `probes/research/value-model/` (14),
each cited in `harness/sources.md`.
