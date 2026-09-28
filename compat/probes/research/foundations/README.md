# Research probes: foundations (set 1)

> Research record from the design sessions that produced this reference, kept verbatim except for its title.
> Where it describes what an implementation chooses to do in a window where perl has no defined behavior, that
> is not a fact about perl; the facts are in `undefined.md` and the choices belong to the implementation.

Probes backing the harness, `each`/`delete`, and XS-shim analysis.

- Oracle A: perl 5.44.0 built from the v5.44.0 tag (useithreads=undef).
- Oracle B: Ubuntu system perl 5.38.2 (useithreads=define).
- Source citations refer to the v5.44.0 tag.

`run_all.sh` runs every `*.pl` under both interpreters in three hash modes
(default/RANDOM, `PERL_HASH_SEED=0`, `PERL_HASH_SEED=12345678`) and writes
`out/<probe>.pl.<544|538>.txt`, then reports which probes differ across versions
after stripping hex addresses. Edit the two interpreter paths at the top of the
`run` calls if your layout differs.

Families: `each_*` iterator semantics, `order_*` traversal model and seed modes,
`local_*` local/tie sequences, `num_*` conversion under warning handlers,
`destroy_*` destruction timing and order, `flags_*` observability of flag state.
