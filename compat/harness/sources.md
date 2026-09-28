# Source citations

Line numbers refer to the `perl5` repository at tag `v5.44.0` and were resolved mechanically by `tools/make-sources.pl`
from `tools/sources.tsv`.  "Probe only" marks rules established by running the probe without reading the corresponding
source.

## each_01_delete_current.pl

- `hv.c:1475` S_hv_delete_common: deleting the entry xhv_eiter points at sets HvLAZYDEL instead of freeing it
- `hv.c:2981` Perl_hv_iternext_flags: advances from HeNEXT(oldentry), then frees a lazily deleted entry

## each_02_delete_other.pl

- `hv.c:1480` S_hv_delete_common: deleting the lazy entry's successor patches HeNEXT(xhv_eiter)

## each_03_insert.pl

- `hv.c:1060` Perl_hv_common: an insert into a hash with an aux struct updates xhv_rand
- `hv.c:3110` Perl_hv_iternext_flags: the warning fires when xhv_last_rand != xhv_rand and riter != -1
- `hv.c:1657` S_hsplit: doubling relinks entries, which produces duplicates and skips mid-iteration
- `hv.c:46` DO_HSPLIT: split only on a colliding insert when keys + keys/2 > max

## each_04_reset.pl

- `hv.c:2524` Perl_hv_iterinit: resets riter and eiter, freeing a lazily deleted entry

## each_05_clear.pl

- `hv.c:2053` Perl_hv_clear: frees entries and clears HvEITER without resizing HvARRAY
- `hv.c:2210` Perl_hfree_next_entry: frees entries walking HvARRAY[0..max] in raw bucket order

## each_06_tied.pl

- `hv.c:3058` Perl_hv_iternext_flags: tied iteration uses one synthetic HE per magical hash, freed via HvLAZYDEL

## each_07_tied_keys_void.pl

- `hv.c:2524` Perl_hv_iterinit: resetting a tied hash's iterator calls no methods

## order_01_model.pl

- `hv.h:28` PERL_HASH_ITER_BUCKET: traversal visits bucket (riter ^ xhv_rand) & max
- `ext/Hash-Util/Util.xs:108` hash_traversal_mask: no prototype, so it needs a hash reference

## order_02_modes.pl

- `util.c:4762` Perl_get_hash_seed: PERL_HASH_SEED=0 selects NO mode, any other seed DETERMINISTIC
- `util.c:4835` Perl_get_hash_seed: in NO and DETERMINISTIC modes the rand bits start from a constant mixed with the
  seed
- `hv.c:65` UPDATE_HASH_RAND_BITS_KEY: a global xorshift step; the key is used only for -D debug output
- `hv.c:2474` S_hv_auxinit: aux allocation steps the global rand bits and seeds xhv_rand

## order_03_insert_warn_modes.pl

- `hv.c:3107` Perl_hv_iternext_flags: in NO mode xhv_rand never changes, so the warning cannot fire

## local_01_tied_elem.pl

- (probe only) probe only; scope.c was not read for this rule

## local_02_fresh_sv.pl

- (probe only) probe only; scope.c was not read for this rule

## num_01_warn_handler.pl

- `sv.c:2123` S_sv_2iuv_common: grok_number runs before not_a_number; flags are installed after it returns

## num_02_stale_cache.pl

- `sv.c:2123` S_sv_2iuv_common: the IV-path value comes from the pre-warning parse

## value_03_handler_reassign_by_path.pl

- `sv.c:2123` S_sv_2iuv_common: IV path parses (S_sv_setnv, Atof) before the warning
- `sv.c:2580` Perl_sv_2nv_flags: NV path warns first, then calls Atof on the post-handler string
- `sv.c:2085` S_sv_setnv: Atof(SvPVX) on the current string

## destroy_01_weak.pl

- `sv.c:547` Perl_sv_clean_objs: DESTRUCT-phase order of the two globals follows arena position

## destroy_02_order.pl

- `hv.c:2210` Perl_hfree_next_entry: hash values are destroyed in raw bucket order

## flags_01_observable.pl

- `cpan/JSON-PP/lib/JSON/PP.pm:485` `_looks_like_number`: default path tests length("" & $value), a flag-dependent
  bitwise op

## flags_matrix.pl

- `builtin.c:417` created_as_string: SvPOK && !SvIsBOOL
- `builtin.c:432` created_as_number: SvNIOK && !SvPOK && !SvIsBOOL
- `sv_inline.h:828` Perl_SvIV: returns SvIVX directly when SvIOK_nog (XS sees the cached value)

## value_01_stale_search.pl

- `sv.c:10134` Perl_sv_inc_nomg: numeric increment when SVp_IOK or SVp_NOK is set, magic string increment otherwise

## value_02_locale_radix.pl

- `numeric.c:912` Perl_grok_numeric_radix: under IN_LC(LC_NUMERIC) matches PL_numeric_radix_sv

## locale_01_setlocale_after_cache.pl

- `locale.c:3466` S_new_numeric: setlocale(LC_NUMERIC) updates the radix used by later parses; existing caches are
  untouched
- `numeric.c:1661` Perl_my_atof: consults IN_LC(LC_NUMERIC) and PL_numeric_radix_sv at call time
- `numeric.c:32` S_strtod: STORE_LC_NUMERIC_SET_TO_NEEDED around libc strtod (the Atof path in d_strtod builds)

## locale_02_copy_across.pl

- `numeric.c:1661` Perl_my_atof: the radix is chosen when parsing, never recorded on the scalar

## locale_03_sub_boundary.pl

- `perl.h:7589` IN_LC_RUNTIME: lexical hints of the currently executing statement (PL_curcop)

## locale_04_handler_setlocale.pl

- `sv.c:2123` S_sv_2iuv_common: IV path parses before the handler, so it uses the pre-handler radix
- `sv.c:2580` Perl_sv_2nv_flags: NV path parses after the handler, so it uses the post-handler radix
- `numeric.c:1731` S_my_atof_infnan: calls grok_infnan only; no radix is consulted there
- `numeric.c:2001` my_atof3 USE_PERL_ATOF branch: manual radix match; not compiled in d_strtod builds such as these

## consts_01_literal_mark.pl

- `pp_ctl.c:1452` RANGE_IS_NUMERIC: SvNIOKp on either operand, including a literal constant, makes the range numeric

## consumers_01.pl

- `pp.c:2740` pp_complement: numeric when SvNIOKp
- `pp.c:2420` pp_bit_and: numeric when either operand is SvNIOKp
- `pp_ctl.c:6438` do_smartmatch: numeric comparison rule tests public NIOK
- `dist/Data-Dumper/Dumper.xs:79` DD_is_integer: SvIOK decides unquoted output
- `cpan/Scalar-List-Utils/ListUtil.xs:1718` isdual: any POK plus any NIOK
- `cpan/Scalar-List-Utils/ListUtil.xs:1861` looks_like_number: reparses when POK, otherwise tests numeric flags
- `pp_pack.c:2929` pack "w": numeric-string handling (independent of the mark in the probe)

## consumers_02_numeric_starts.pl

- `dist/Storable/Storable.xs:2472` store_scalar: public POK is serialized as a string

## gd_01_order.pl

- `sv.c:547` Perl_sv_clean_objs: four visit passes (RVs, glob slots, IO slots, curse)
- `sv.c:382` S_visit: walks PL_sv_arenaroot, ascending within each arena
- `sv.c:343` S_sv_add_arena: prepends new arenas, so the newest is walked first
- `sv.c:442` do_clean_objs: weak refs cleared without a decrement; strong refs decremented
- `sv.c:530` do_curse: curse(sv, 0), DESTROY without a refcount check
- `sv.c:7317` sv_clear: curse(sv, 1), resurrection check
- `sv.c:7802` S_curse: resurrection during PL_in_clean_objs croaks
- `sv_inline.h:28` PERL_ARENA_SIZE: 4080-byte arenas

## addr_01_reuse.pl

- `sv.c:254` plant_SV: freed heads are pushed onto PL_sv_root (LIFO), except SVf_BREAK heads
- `sv_inline.h:59` uproot_SV: heads are popped from PL_sv_root

## addr_02_observable.pl

- `sv.c:254` plant_SV: one free list for heads of every SV type

## addr_03_insideout_warm.pl

- `sv.c:254` plant_SV: a freed object's head is the next head allocated

## addr_04_order_nofree.pl

- `sv.c:343` S_sv_add_arena: stock builds thread each arena's free list in ascending order

## threads_01_const_marks.pl

- `op.c:2920` Perl_op_relocate_sv: under ithreads a constant's SV is moved into the pad because it is written to
- `peep.c:1297` peephole optimizer: relocates every OP_CONST's SV under USE_ITHREADS
- `op.h:549` cSVOPx_sv: under ithreads a constant is read from PAD_SVl(op_targ)
- `sv.c:15776` sv_dup: a cloned CV shares the parent's op tree by refcount
- `sv.c:16959` perl_clone: the main op tree is shared, not copied

## probe_01_face_trace.pl

- `builtin.c:432` created_as_number as reported on fd 3
