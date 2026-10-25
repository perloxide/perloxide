# FZ: finalization and temporary lifetime

**Source.**  Transcribed from the perl5 repository at tag `v5.44.0`: sv.c (`sv_clear`, `S_curse`, `sv_kill_backrefs`,
`sv_del_backref`, `sv_rvweaken`, `sv_setsv_flags`), scope.c and the tmps-stack and context routines of pp_ctl.c and
pp_hot.c.  Validated by replay against the supported 5.44.0 builds; results in `reports/`, with the identical 5.38.2
traces beside them from the unsupported 5.38.2 (`../../unsupported-perls.md`).	Source-validated with
`harness/tools/source-validate.pl` against v5.38.2, v5.40.2, v5.42.0, v5.44.0 (`source-validation.txt`): of the routines
with a C definition, 1 are identical across all four tags and so transcribed equally validly for each, 2 differ only by
moved declarations or added assertions, and 13 differ in code at one or more of the tags and must be read before any of
those versions can be supported by this model — each such reading ends either in a `source-equivalences.tsv` line
(functionally neutral) or in a version check inside the model; 0 names are the model's own labels, arms and helpers.  A
replay mismatch on a supported version is therefore either a model gap or a change in perl's own implementation since
the transcribed tag, and the validation record says which routines could carry the second kind.

`Finalization.pm` transcribes the lifetime machinery over a scenario IR: `SvREFCNT_dec` -> `sv_clear` -> `curse`
(S_curse, with resurrection epochs and rebless), `sv_kill_backrefs`, `sv_setsv_flags` / `sv_set_undef` /
`sv_del_backref` / `sv_rvweaken` / `sv_force_normal_flags`, the tmps stack (`free_tmps`, `cx_pushblock`, `cx_popblock`,
`leave_scope`, `leave_adjust_stacks`), `pp_entersub`, `pp_nextstate`, and `sv_clean_objs`. Harness glue (the IR walker,
trace emitter) is `Perl::Conformance::Model::Finalization::Harness::*`, CamelCase, in the same file pending the split
into `FZ/Harness.pm`.

`generators/fz_gen.pl` emits 115 scenarios as perl programs and as IR: five destructor variants (plain, `$_[0]` copied
to a global, weak copy, rebless, dies) x death triggers (scope exit with and without a trailing statement, `undef`,
assignment, `.=`, `delete`, `@a = ()`, `die` inside `eval`, global destruction) x constructs (plain statement, one- and
two-statement `if` bodies, `while`, postfix `while`, `do`-`while`, C-style `for` with and without a step, call argument,
void/list/scalar returns, `grep` block, `local`, `eval`), plus tied weak holders (two, two with a dying `STORE`, five
with one removed before the kill) and global-destruction rows compared as sets.

    PERL_CONFORMANCE_PERL=/path/to/perl TAG=<tag> perl generators/fz_gen.pl   # scenarios=115 ok=... bad=...

Recorded: 115/115 on 5.38.2 and 5.44.0, traces identical (`reports/`). Section text: `section.md`.  Coverage is the
generator's scenario set; the program-level reference is `suites/finalization`.  Open: the key has not been audited
against the context and tmps stacks (`status.md`).
