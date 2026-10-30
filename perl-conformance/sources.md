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

## local_elem_sv_identity.pl

- `scope.c:1037` Perl_save_aelem_flags: the SAVEt_AELEM record holds the array, the index and the element's SV, not its
  value
- `scope.c:1679` Perl_leave_scope, SAVEt_AELEM: the restore re-fetches by the original index with lval set, vivifying
  the slot in whatever the array has become
- `av.c:217` Perl_av_extend_guts: the slots a store past the end skips are NULL, which exists reports as absent
- `av.c:934` Perl_av_shift: returns the first element's SV itself, which pp_shift mortalizes; the SV local installed
  leaves the array alive
- `pod/perlsub.pod:1109` perlsub says the skipped elements are filled with undef; they are holes

## local_03_shared_elem_move.pl

- `dist/threads-shared/shared.xs:101` a shared element's proxy carries tied-element magic addressing the aggregate by
  index and shared-scalar magic pointing at the shared SV
- `dist/threads-shared/shared.xs:946` sharedsv_scalar_mg_set: stores the proxy's value into the shared SV its mg_ptr
  names, wherever a shift or unshift has moved it
- `dist/threads-shared/shared.xs:1076` sharedsv_elem_mg_STORE's comment: the magic chain is ordered so the scalar
  magic's store runs first
- `dist/threads-shared/shared.xs:1069` sharedsv_elem_mg_STORE: stores the value again at mg_len, the original index

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

## threads_02_shared_local.pl

- `mg.c:484` Perl_mg_localize: the shared-scalar magic is copied onto the fresh proxy, so the localized value is stored
  into the same shared cell every thread reads
- `dist/threads-shared/shared.xs:946` sharedsv_scalar_mg_set: the restore's first write, into the shared SV the saved
  proxy points at, whichever thread moved it
- `dist/threads-shared/shared.xs:1069` sharedsv_elem_mg_STORE: the restore's second write, at the original index
- `inline.h:1227` Perl_sv_can_existdelete: a tie class must have both EXISTS and DELETE for an absent element to be
  recorded as absent
- `dist/threads-shared/shared.xs:1509` threads::shared::tie has EXISTS but no DELETE method, so a localized absent
  element is treated as present and restored by STORE
- `pp_hot.c:4627` pp_multideref, and pp_aelem below it with the same block: without SvCANEXISTDELETE the element is
  preeminent and save_aelem records the fresh proxy's undef

## tied_01_iteration_and_args.pl

- `pp_hot.c:5103` pp_iter: a magical array is read by index each iteration through av_fetch, which hands out a
  tied-element proxy without FETCHing it
- `av.c:285` Perl_av_fetch on a tied array: the element is a fresh PVLV proxy carrying tiedelem magic, one per fetch

## tied_02_proxy_acquires_magic.pl

- `mg.c:188` Perl_mg_get: the get-skip flag is tested per magic entry, so one magic on a proxy can be skipped while
  another runs
- `mg.c:287` Perl_mg_set: a set through the proxy clears the skip flag on each entry, re-arming the element FETCH

## tied_03_unprimed_proxy_getmagic.pl

- `sv.c:6649` Perl_sv_rvweaken: weakening an undef (an unprimed proxy's slot) is a silent no-op
- `pp.c:8374` pp_is_weak runs SvGETMAGIC on its argument, so builtin::is_weak (Scalar::Util's isweak since 5.40) FETCHes
  a tied-element proxy
- `pp.c:8384` pp_weaken calls sv_rvweaken on the stack SV with no get-magic

## weak_01_death_window_reads.pl

- `sv.c:7813` S_curse: the object is unblessed after DESTROY and before the weak references are cleared

## weak_02_backref_order.pl

- `sv.c:6901` Perl_sv_del_backref: a removed first holder advances the array start
- `sv.c:6929` Perl_sv_del_backref: the array is shortened by one whether the removed holder was last or was replaced by
  the last

## weak_03_copy_is_strong.pl

- `sv.c:4593` Perl_sv_setsv_flags: a copied reference takes a new strong count and no weak flag

## local_04_tied_absent_preref.pl

- `pp_hot.c:4415` pp_helem: a key absent when local runs is recorded for deletion on unwind, whatever is stored under it
  later
- `pp_hot.c:4663` pp_aelem: the same for an array index past the end

## parse_01_unidor_keywords.pl

- `toke.c:297` UNIDOR: the operator lexes the next token with PL_expect set to XTERMORDORDOR
- `toke.c:9009` yyl_word_or_keyword: shift is UNIDOR, as are getc, pop, pos, readline, readlink, readpipe, umask and
  undef
- `toke.c:261` FTST: every file test sets XTERMORDORDOR
- `toke.c:7060` yyl_slash: under XTERMORDORDOR, // and //= are defined-or
- `toke.c:7129` yyl_tilde: under XTERMORDORDOR, ~~ is smartmatch

## parse_02_unidor_parens.pl

- `toke.c:294` UNI3: a ( after the operator, after any whitespace, makes it FUNC1
- `perly.y:1693` term: FUNC1 ( ) and FUNC1 ( expr )
- `toke.c:7146` yyl_leftparen: directly after an operator, the ( leaves PL_expect as the operator set it

## parse_03_stat_is_uni.pl

- `toke.c:9061` yyl_word_or_keyword: stat is UNI
- `toke.c:8749` yyl_word_or_keyword: lstat is UNI

## parse_04_filetest_letters.pl

- `toke.c:6219` yyl_hyphen: the 27 file-test letters
- `toke.c:6264` yyl_hyphen: any other letter is a minus followed by the word

## parse_05_core_prefix.pl

- `toke.c:9325` yyl_keylookup: CORE:: goes to yyl_key_core before the => check
- `toke.c:9230` yyl_key_core: NAME is looked up as a keyword and its case taken directly; NAME:: makes an ordinary word
- `toke.c:9246` yyl_key_core: CORE::%s is not a keyword
- `toke.c:6669` yyl_leftcurly: a subscript is autoquoted only when a word scanned without :: is followed by }
- `toke.c:6123` yyl_secondclass_keyword: bare dump croaks

## parse_06_weak_override_import.pl

- `toke.c:9399` yyl_keylookup: a lexical sub is found before any keyword
- `toke.c:6076` yyl_secondclass_keyword: a weak keyword yields to an imported sub or an imported CORE::GLOBAL sub, lock
  to any sub; otherwise the ambiguous warning, except for x
- `sv.c:4114` Perl_gv_setref: a glob assignment marks the slot imported when the current package differs from the glob's
- `regen/keywords.pl:168` regen/keywords.pl: + marks a strong keyword, - a weak one

## parse_07_statement_terminator.pl

- `perly.y:333` barestmt: an expression statement ends at ;
- `toke.c:6890` yyl_rightcurly: the lexer returns a ; before the } that closes a block
- `toke.c:7670` yyl_fake_eof: and a ; at the end of the input
- `toke.c:690` S_warn_expect_operator: the "found where operator expected" warning
- `toke.c:11503` scan_subst: an s///e replacement is compiled as do { ... }

## parse_08_unary_argument_start.pl

- `toke.c:296` UNI: the operator lexes the next token with PL_expect set to XTERM
- `perly.y:1672` term: UNIOP, UNIOP block, UNIOP term
- `perly.y:169` %nonassoc UNIOP: the argument's precedence
- `toke.c:2124` S_check_unary: the ambiguous warning, naming the operator up to the first character not a word character
  or -
- `toke.c:9388` yyl_keylookup: a word followed by a single : at statement start is a label

## parse_09_keyword_classes.pl

- `toke.c:8703` yyl_word_or_keyword: keys is UNI
- `toke.c:9173` yyl_word_or_keyword: values is UNI
- `toke.c:8514` yyl_word_or_keyword: each is UNI
- `toke.c:9105` yyl_word_or_keyword: tell is UNI
- `toke.c:9136` yyl_word_or_keyword: untie is UNI
- `toke.c:9207` yyl_word_or_keyword: write is UNI
- `toke.c:8450` yyl_word_or_keyword: die is LOP
- `toke.c:9192` yyl_word_or_keyword: warn is LOP
- `toke.c:8609` yyl_word_or_keyword: getprotobynumber is LOP

## parse_10_shift_array_argument.pl

- `perly.y:1697` term: FUNC1 ( expr ) accepts any expression
- `op.c:13781` Perl_ck_fun: an array operand must be an rv2av or padav op; a hash, glob or constant is a bad type,
  anything else "Experimental %s on scalar is now forbidden"

## parse_11_unary_operand_extent.pl

- `perly.y:169` %nonassoc UNIOP: the operand extends over the operators declared after it and ends before those declared
  before it
- `toke.c:294` UNI3: a ( after the operator and any whitespace or comments makes it FUNC1, whose operand ends at the )
- `toke.c:2081` skipspace: the space skipped before that check includes comments and newlines
- `toke.c:261` FTST: a file test always returns UNIOP, never FUNC1
- `op.c:13695` Perl_ck_ftst: a file test whose operand is a file test is stacked

## parse_12_empty_condition.pl

- `perly.y:998` texpr: an empty condition is the constant 1, used by the block while and the middle test of a C-style
  for
- `perly.y:943` sideff: a statement modifier takes an ordinary expression, with no empty form
- `perly.y:1011` mexpr: the condition of if, unless and elsif is a required expression
- `perly.y:1006` iexpr: the condition of until is a required expression
