# Perl compatibility reference

An executable record of how Perl 5 actually behaves, with `perl` itself as the ground truth.  It exists because prose
about Perl's semantics drifts, and a rule stated as a probe with a blessed output, or as a transcription of the C code
validated by enumeration, does not.  Perl 5.44.0 is the current pinned target version.

Everything under this directory is about **Perl**, not about any particular reimplementation of Perl.  This is meant to
be used as a reference and guide for the actual behavior of the traditional `perl` implementation, to be used as a
compatibility aid for any reimplementation effort.  Nothing here names, depends on, or records a decision of any other
implementation; what a given implementation chooses to do where Perl's behavior is undefined belongs in that
implementation's own documentation.

## Layout

| Path             | Contents                                                                                                          |
|------------------|-------------------------------------------------------------------------------------------------------------------|
| `profile.md`     | the build and environment the facts are relative to: Perl version, widths, allocator, hash function, locale, libc |
| `status.md`      | one row per model and suite: what is verified, on which Perls, under which key generation, and what is open       |
| `undefined.md`   | windows where `perl` itself crashes, reads freed memory, or otherwise has no defined behavior; facts only         |
| `facts.md`       | the prose index of every fact, by area, each linked to the probe or model row that demonstrates it                |
| `harness/`       | the differential oracle: runner, normalizer, verdict rules, probe projector, citation index                       |
| `perls/`         | the build script for the pinned Perl and its two allocator-instrumented variants, with the patches                |
| `probes/`        | one program per fact: `corpus/` (harness-run, blessed per build and hash mode) and `research/` (as recorded)      |
| `models/<NAME>/` | executable transcriptions of one area of the C, with their generators, tables, reports, and section text          |
| `suites/`        | scenario suites from the design research, with blessed outputs                                                    |
| `measurements/`  | benchmarks and graph walks from the design research: costs on a particular machine, not facts about Perl          |

## Rules

**Admission.** A fact enters the reference only with a probe or a model row that demonstrates it on the pinned Perl.  A
fact without one is not a fact yet.

**Models.** A model is a transcription of one area of Perl's C source into Perl, validated by replaying Perl's own
observed behavior through it.  Every snake_case routine in a model package mirrors the Perl function of the same name
with its `Perl_`/`S_` prefix removed, one-to-one with the C call graph; macros and inline helpers keep their exact
spelling; a suffixed name (`got_nv`, `sv_inc_nomg_integer`) is a label or arm inside the named function.  Everything
that does not mirror C lives in the model's harness package and is CamelCase.  Where a routine deliberately diverges
from the C, it keeps the C name and marks the divergence at the branch.

**Keys.** A model's state fingerprint (the key) is derived from the C struct definitions the model covers, field by
field, before its first enumeration.  A field is excluded only with a source citation showing it cannot decide a future
observable, or with a lane-construction assertion that the observer enforces.  The key carries every field that decides
a future observable, for every holder kind, whether or not the field is itself visible to any consumer.

**Harness rules** (each found by measuring the harness instead of Perl):
1. never wrap an operation in `eval { }` -- the eval scope frees temporaries and changes COW state; wrap a block once
   for croak containment;
2. the holder must be fresh -- a reused variable keeps its body and buffer and takes no COW on reassignment; holder
   freshness is a dimension, holder kind is not;
3. the observer's own state must be fresh per block -- a lexical inside the observer is a reused pad slot and its stale
   buffer masquerades as a transition;
4. a fresh op tree per cell -- compiled constants and an op's `TARG` keep state across executions, so a shared op tree
   makes "fresh" not fresh;
5. never copy the holder between operations -- the copy's COW arm marks the holder for the next op; observe through `B`
   and `Devel::Peek` per step, and run consumers once, destructively, at the end.

**Verdicts.** `match`; `open` (a model or blessed-output mismatch on rows where the oracle Perls agree, listed with its
recipe and the governing source line); `version-divergent` (the oracle Perls differ on this path; the model follows the
pinned version); `body-only` (differs only in a field the profile declares consumer-invisible); `allocator-sensitive`;
`perl-nondeterministic`; `undefined-in-perl`.  Counts are stated per key generation and never compared across
generations.

**Tooling.** One driver with subcommands per harness; no Makefiles.  Lane staleness is decided by a content hash of the
model, observer, generator, start set, and oracle recorded in each report header, not by timestamps or a rerun flag.

**Versions.** The models transcribe the pinned Perl only.  Older and newer Perls are run as difference detectors: the
path-based version-divergence rule dates each behavior, and a behavior that changed recently is flagged as likely to
change again.  No model of another version is kept.
