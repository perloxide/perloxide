# HV: the hash engine

`HV.pm` transcribes hv.c and hv_func.h for the profile in `profile.md`: the seed expansion (`perl_siphash_seed_state`,
`sbox32_seed_state128`), the two hash functions (`perl_hash_siphash_1_3_with_state`, `sbox32_hash_with_state`),
`hv_common` (head insertion, `DO_HSPLIT` gated on collision), `hsplit`, `hv_auxinit`, `PERL_HASH_ITER_BUCKET`,
`hv_iternext_flags` (including `HvLAZYDEL` and the each-after-insert warning's `xhv_last_rand != xhv_rand` guard),
`hv_delete_common`, `hv_clear`, `hv_undef_flags`, `hfree_next_entry`'s raw-bucket destruction order, and key
normalization.

`generators/hv_gen.pl` validates below program level against `Hash::Util::bucket_array`, `hash_traversal_mask`, and
`hash_value` for 5, 40, 700, and 5000 keys under seed 0, a nonzero seed with `PERL_PERTURB_KEYS=0`, and (excluded by
construction) `PERL_PERTURB_KEYS=2`; and at program level for `keys`/`each` order, delete-current, delete-other, insert
during `each`, iterator reset, clear-and-refill versus undef-and-refill, and `DESTROY` order.

    ORACLE=/path/to/perl TAG=<tag> perl generators/hv_gen.pl   # ok=28 bad=0 plus EXCLUDED lines

Recorded: 28/28 on 5.38.2 and 5.44.0 (`reports/`). Section text: `section.md`. Open: the key has not been audited
against `HE`/`HV`/`xpvhv_aux` (`status.md`).
