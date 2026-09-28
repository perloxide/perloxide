# FZ: finalization and temporary lifetime

`FZ.pm` transcribes the lifetime machinery over a scenario IR: `SvREFCNT_dec` -> `sv_clear` -> `curse` (S_curse, with
resurrection epochs and rebless), `sv_kill_backrefs`, `sv_setsv_flags` / `sv_set_undef` / `sv_del_backref` /
`sv_rvweaken` / `sv_force_normal_flags`, the tmps stack (`free_tmps`, `cx_pushblock`, `cx_popblock`, `leave_scope`,
`leave_adjust_stacks`), `pp_entersub`, `pp_nextstate`, and `sv_clean_objs`. Harness glue (the IR walker, trace emitter)
is `FZ::Harness::*`, CamelCase, in the same file pending the split into `FZ/Harness.pm`.

`generators/fz_gen.pl` emits 114 scenarios as perl programs and as IR: five destructor variants (plain, `$_[0]` copied
to a global, weak copy, rebless, dies) x death triggers (scope exit with and without a trailing statement, `undef`,
assignment, `.=`, `delete`, `@a = ()`, `die` inside `eval`, global destruction) x constructs (plain statement, one- and
two-statement `if` bodies, `while`, postfix `while`, `do`-`while`, C-style `for` with and without a step, call argument,
void/list/scalar returns, `grep` block, `local`, `eval`), plus tied weak holders and global-destruction rows compared as
sets.

    ORACLE=/path/to/perl TAG=<tag> perl generators/fz_gen.pl   # scenarios=114 ok=... bad=...

Recorded: 114/114 on 5.38.2 and 5.44.0, traces identical (`reports/`). Section text: `section.md`.  Coverage is the
generator's scenario set; the program-level oracle is `suites/finalization`.  Open: the key has not been audited against
the context and tmps stacks (`status.md`).
