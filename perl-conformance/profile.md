# Profile

Every fact in this reference is relative to the following.  A fact that depends on a parameter not listed here says so
where it is stated.

## Supported versions

A version of Perl is *supported* by this reference when it has the full build set — the stock build, the `noreuse` and
`descending` allocator-instrumented variants, and the same three built with `-Dusethreads` — and every corpus probe and
suite case that exists on the day it is added is blessed on it.  Nothing less counts: without the instrumented variants
a program's allocator sensitivity cannot be classified, and without the blessing a version cannot be a target.  Probes
added later may be blessed on the newest version only, so an older supported version can lag; `status.md` states each
version's gap, and closing it is the documented procedure of running and blessing the unblessed probes on that version's
builds — legwork a user who needs an older target fully current may have to do, but never redesign.  A version never
becomes less useful than on the day it was added.  The newest supported version is the default target for the harness's
lane-A comparison; a user selects another supported version as their target where the harness and the suites take one.
A Perl that is not supported — a system's stock `perl`, say — is an *implementation to check* against the blessed
outputs with `harness/bin/oracle check`, not an oracle, whatever its version.

- **5.44.0**, built from the `v5.44.0` tag of https://github.com/Perl/perl5 with `perls/build-perls.sh`, is the only
  supported version at this writing, and so the default target.  Unthreaded unless a probe states otherwise (`#
  oracle-requires: threads`), in which case the oracle is the same tag built with `-Dusethreads`.  Every lane-A probe of
  the corpus produces identical normalized output on both; the builds differ in the `Perl interpreter: 0x...` suffix of
  some diagnostics, which normalization removes.
- **Instrumented variants:** `noreuse` (`plant_SV` never returns freed SV heads to `PL_sv_root`) and `descending`
  (arenas threaded from the highest slot down).  A program whose output is not identical across stock, `noreuse`, and
  `descending` after address bijection is `allocator-sensitive` and is not an exact-comparison oracle.
- **5.38.2** (the Ubuntu 24.04 system Perl, threaded) is not a supported version: it has no instrumented variants and
  was never blessed as a target.  Its observations appear in the reference only where they were recorded during the
  research as a cross-check beside 5.44.0's; they demonstrate nothing on their own, and no fact rests on them.

## Widths and numeric configuration

- x86-64: `ivsize=8`, `uvsize=8`, `nvsize=8` (double), `longdblsize=16`, `use64bitint=define`.
- `NV_PRESERVES_UV` is **undefined**; `NV_PRESERVES_UV_BITS=53`.  The models transcribe the `#else` branches of
  `S_sv_2iuv_common`, `sv_2iv_flags`, and `sv_2nv_flags`.  A 32-bit Perl (`ivsize=4`) defines `NV_PRESERVES_UV` and runs
  the other branches; it is outside this profile.
- `d_double_has_nan=define`.  NaN payload spellings and long-double or quadmath builds are not covered.

## Structure sizes

Measured with `perls/sizes.sh` against the supported builds (`perls/sizes.c` compiled against each build's `CORE`),
identical for the unthreaded and threaded 5.44.0 builds on x86-64:

```text
SV head 24
XPV 32  XPVIV 40  XPVNV 48  XPVMG 48  XPVLV 80  XPVGV 48  XPVCV 104
XPVAV 40  XPVHV 32  HE 24  HEK header 12
```

So a bodyless scalar is 24 bytes, a `PVIV` scalar 64, a `PVNV` or `PVMG` scalar 72, an array 64 plus its `SV*` table (8
per element), and a hash 56 plus its bucket table and 24 bytes per entry plus the shared key.  String buffers are
separate allocations in every case.

## Allocator

- `usemymalloc='n'`, `d_malloc_good_size='undef'`, `d_malloc_size='undef'`: `Perl_sv_grow` never consults the allocator,
  so `SvLEN` is a pure function of the source (creation-site sizes, `PERL_STRLEN_ROUNDUP` at the default 8-byte quantum,
  `PERL_STRLEN_NEW_MIN`, and in 5.44 `expected_size` on a first allocation).  A build with `malloc_good_size` would make
  buffer lengths, and therefore copy-on-write decisions, allocator-dependent.
- Address reuse is excluded from every comparison by the address bijection; probes whose behavior depends on a freed
  SV's memory are `undefined-in-perl`.

## Hash function and seeds

- `PERL_HASH_FUNC_SIPHASH13` with `SBOX32` for keys of at most `SBOX32_MAX_LEN=24` bytes; `PERL_HASH_RANDOMIZE_KEYS`;
  `PERL_HASH_DEFAULT_HvMAX=7`.
- Iteration order, chain order, split points, traversal mask, and destruction order are reproduced exactly under
  `PERL_HASH_SEED=0` (which implies `PERL_PERTURB_KEYS=0`) and under any explicit seed with `PERL_PERTURB_KEYS=0`.
  Under RANDOM and DETERMINISTIC perturbation the order is unspecified, as in Perl; the DETERMINISTIC layout depends on
  every hash operation the process performed and cannot match across interpreters.

## Locale

- Numeric-radix probes and lanes use a locale the harness compiles from its own source (`radix_comma`: `LC_NUMERIC` with
  `decimal_point ","`, every other category POSIX); ctype probes use `ctype_utf8` (`LC_CTYPE` from the glibc `i18n`
  classification, every other category POSIX).  The sources are `harness/locales/`; `harness/lib/Oracle/Locales.pm`
  compiles them with the system's `localedef` against the system's own `i18n` sources at startup, so no probe depends on
  which locales the system has generated.  The compiled form is keyed by the sources and the `localedef` version, so a
  changed glibc recompiles.
- Cross-version fact: after `setlocale(LC_NUMERIC, <comma locale>)` at file scope with no `use locale`, 5.38.2
  stringifies `3.5` as `3,5` and 5.44.0 as `3.5`.

## Environment

- Linux x86-64, glibc with exact floating-point formatting (`%g`, `%.17g` go through libc).
- Verified: Ubuntu 24.04 (glibc 2.39, gcc 13) on a 4.19 kernel.  Ubuntu 26.04's userland requires a kernel with
  `openat2` (5.6+) and does not run on 4.19.
- Core modules only: `B`, `Devel::Peek`, `Scalar::Util`, `Data::Dumper`, `JSON::PP`, `Storable`, `Hash::Util`,
  `builtin`.

## Scope statements

- Body type (`SvTYPE`), stale buffer `CUR`/`LEN`, and `COW_REFCNT` are consumer-invisible under this profile
  (`B`/`Devel::Peek` only); they are carried in model keys because they decide later transitions, and differences
  confined to them are reported `body-only`.
- Within-pass order in global destruction is arena order and is out of scope; those rows are compared as sets.
