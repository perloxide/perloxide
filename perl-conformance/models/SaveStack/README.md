# SS: `local` and the save stack

`SS.pm` transcribes scope.c's `local` machinery -- `save_scalar_at`, `save_scalar`, `save_aelem_flags`,
`save_helem_flags`, `save_adelete`/`save_hdelete`, `save_gp`, `save_clearsv`, `mg_localize`, `restore_sv`, `leave_scope`
and its record types -- plus the `pp_gvsv`/`pp_aelem`/`pp_helem` localizing arms that decide the entry `mg_set`.

`generators/ss_gen.pl` enumerates 312 cells: {plain, tied, magical (`$/`, `$0`), glob-aliased} x {package scalar,
element present, element absent, whole glob} x {bare, assignment, self-assignment} x {no mutation, pre-`local`-ref
mutation, container clear, delete} x {normal exit, die in body, die in a restoration STORE, die in the displaced value's
DESTROY} x nesting depth 1-2, observing the callback trace, first-appearance-normalized addresses, final values,
`exists`, and `$@`. Address triples on tied-container element mirrors are masked (reuse of a freed mirror's memory; see
`undefined.md`).

    ORACLE=/path/to/perl perl generators/ss_gen.pl        # prints cells=312 ok=... mismatch=... crash=...
    ORACLE=... TABLE=reports/table.<ver>.tsv perl generators/ss_gen.pl

Recorded: 312/312 on 5.38.2 and 5.44.0, byte-identical observation lines (`reports/`). The section text is `section.md`.
Open: the key has not been audited against the save-record and `GP` structs, and the routine names predate the C-name
convention (`rc_inc`/`rc_dec`, `mortal`, `boundary`, `cell_get`/`cell_set`); see `status.md`.
