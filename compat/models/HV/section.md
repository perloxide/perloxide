# The hash engine

`keys`, `values`, `each`, and the destruction order of a hash's values are all functions of where Perl's `hv.c` puts
entries and how it walks them. This section defines that engine so the bit-exact verification lane can reproduce it. The
reference implementation is `HV.pm`, a transcription of the functions named below for the profile: 64-bit,
`PERL_HASH_FUNC_SIPHASH13` with `SBOX32` for keys of at most `SBOX32_MAX_LEN` = 24 bytes, `PERL_HASH_RANDOMIZE_KEYS`,
`PERL_HASH_DEFAULT_HvMAX` = 7. Its harness `hv_gen.pl` compares it with `Hash::Util::bucket_array`,
`hash_traversal_mask`, and `hash_value` below program level and with `keys`/`each`/`DESTROY` traces at program level, on
Perl 5.38.2 and 5.44.0, which are built with the same profile and produce identical results.

## 1. The hash function and the seed

`Perl_get_hash_seed` (util.c) fills a 32-byte seed buffer: from the hex digits of `PERL_HASH_SEED` when set (a value of
`0` is thirty-two zero bytes), otherwise from the system RNG. `PVT_PERL_HASH_SEED_STATE` (hv_func.h) expands it into two
states: `S_perl_siphash_seed_state` (perl_siphash.h) XORs the first sixteen bytes, as two little-endian 64-bit words,
into the four SipHash constants; `sbox32_seed_state128` (sbox32_hash.h) seeds four 32-bit words from the last sixteen
bytes XORed with `sbox`/`hash`/`good`/`fast`, forces each nonzero, churns them through 128 `SBOX32_MIX4` rounds, XORs
the complemented seed words back in, churns 128 rounds again, and then fills a table of 24 × 256 words plus one initial
word from `XORSHIFT128_set`.

`PVT_PERL_HASH_WITH_STATE` picks the function by length: at most 24 bytes, `sbox32_hash_with_state` — the initial word
XORed with one table word per position, indexed by position and byte value, no mixing; longer,
`S_perl_hash_siphash_1_3_with_state` — one `SIPROUND` per 8-byte block, the tail packed under `len << 56`, one round,
`v2 ^= 0xff`, three final rounds, and the two 32-bit halves of the 64-bit result XORed together.
`Hash::Util::hash_value` exposes the result per key and the harness checks every key of every lane against it.

Key normalization precedes hashing (`Perl_hv_common`): a `UTF8`-flagged key whose code points all fit Latin-1 is
downgraded (`bytes_from_utf8`) and stored with `HVhek_WASUTF8`; one that does not fit keeps its bytes with `HVhek_UTF8`.
Two keys are the same entry when the normalized bytes and the `HVhek_UTF8` bit agree.

## 2. Perturbation modes

`PL_hash_rand_bits` is initialized from the seed (util.c, `Perl_get_hash_seed`): in RANDOM mode (`PERL_PERTURB_KEYS=1`)
from the RNG, otherwise the constant `0xbe49d17f` with the leading seed bytes folded in byte by byte through `ROTL_UV(…,
8)`. `PERL_PERTURB_KEYS=0` disables perturbation: `PL_HASH_RAND_BITS_ENABLED` is false, the value never changes, and
both chain placement and traversal are functions of the seed alone. `PERL_HASH_SEED=0` implies `PERL_PERTURB_KEYS=0`
unless overridden. `PERL_PERTURB_KEYS=2` (DETERMINISTIC) enables the `PERL_XORSHIFT64_A` step (`x ^= x<<13; x ^= x>>7; x
^= x<<17`) with a seed-derived start: every colliding insert and every split advances it (`UPDATE_HASH_RAND_BITS_KEY`,
`MAYBE_UPDATE_HASH_RAND_BITS`), so the layout of any hash depends on every hash operation the process performed before
it — including the interpreter's own startup — and cannot match across interpreters or builds. The harness confirms
this: under that mode the per-key hash values agree with `HV.pm` and the bucket contents do not, and the lane is
excluded as an oracle.

## 3. Storage and the split rule

A hash is an array of `HvMAX + 1` buckets, initially 8, each a singly linked chain. `Perl_hv_common` inserts a new entry
at the head of its bucket (`HeNEXT(entry) = *oentry; *oentry = entry`); under perturbation, when the bucket is occupied
and the low bit of the advanced `PL_hash_rand_bits` is set, after the head instead. The insert then tests `DO_HSPLIT`:
`keys + keys/2 > max`, and only when the insert collided (`in_collision`), so a hash whose keys all land in distinct
buckets is not split by count alone. `S_hsplit` doubles the array, walks the old buckets in index order, and for each
chain walks its entries from the head: an entry whose hash has the new bit set is unlinked and pushed onto the head of
its new bucket (after the head under perturbation with the bit set), so moved entries end up in reverse of their
previous order; entries that stay keep theirs.

## 4. Traversal

The iterator lives in `HvAUX`, allocated by `S_hv_auxinit` on first use with `xhv_riter = -1`, `xhv_eiter = NULL`,
`xhv_rand = PL_hash_rand_bits` (as a 32-bit value), and `xhv_last_rand = xhv_rand`. `Perl_hv_iternext_flags` continues
from `HeNEXT(eiter)` or advances `riter` until it finds a non-empty bucket at `PERL_HASH_ITER_BUCKET(iter) & max` =
`(riter ^ xhv_rand) & max`; past `max` it resets `riter` to −1 and returns nothing. So the visible order is bucket order
permuted by XOR with the mask, each chain head to tail. `Hash::Util::hash_traversal_mask` returns `xhv_rand`; under seed
0 it is `0xbe49d17f`'s low 32 bits and constant.  `keys` and `values` reset the iterator before and after their walk.

## 5. `each` under mutation

Deleting the entry `each` just returned value flags it `HvLAZYDEL`: `Perl_hv_delete_common` unlinks it from the chain
but keeps it alive so the next `iternext` can continue from its `HeNEXT`, then frees it. Deleting another entry unlinks
it immediately and the walk is unaffected except that it will not be visited. Inserting during the walk may split the
array and change `xhv_rand` under perturbation, so keys can be visited twice or skipped; the warning "Use of each() on
hash after insertion without resetting hash iterator results in undefined behavior" is emitted by `hv_iternext_flags`
when `xhv_last_rand != xhv_rand` while `riter != -1` — which requires perturbation, so under `PERL_PERTURB_KEYS=0`
inserts during `each` are silent and the walk is deterministic.

## 6. Clear versus undef, and destruction

`Perl_hv_clear` frees the entries and keeps the bucket array at its current size; `Perl_hv_undef_flags` also releases
the array, so a refill starts again at 8 buckets and splits as it grows. The two therefore produce different orders for
the same refilled key set (the harness's `clearfill`/`undeffill` rows). Entries are freed by `Perl_hfree_next_entry` in
raw bucket order, index 0 upward, each chain head to tail, and `DESTROY` on the values follows that order — not the
traversal permutation, and unchanged by a prior `keys` or `each`.

## 7. Compatibility profile

Iteration order, chain order, split points, traversal mask, and destruction order are reproduced exactly under
`PERL_HASH_SEED=0`, and under any explicit seed with `PERL_PERTURB_KEYS=0`, for the profile above; the harness verifies
5, 40, 700 and 5,000-key hashes at the bucket level and the program-level rows on both Perls, 28 of 28 each. Under
RANDOM and DETERMINISTIC perturbation the order is unspecified, as it is in Perl, and only the guarantees hold: `keys`,
`values` and `each` agree with one another, order is stable until the hash is modified, and the warning fires when a
perturbing insert interleaves an `each` walk.
