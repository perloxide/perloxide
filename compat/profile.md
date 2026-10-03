# Profile

Every fact in this reference is relative to the following.  A fact that depends on a parameter not listed here says so
where it is stated.

## Pinned Perl

- **Target:** Perl 5.44.0, built from the `v5.44.0` tag of https://github.com/Perl/perl5 with `perls/build-perls.sh`.
  Unthreaded unless a probe states otherwise; the threaded and unthreaded builds differ only in the `Perl interpreter:
  0x...` suffix of some diagnostics.
- **Second oracle:** Perl 5.38.2 (the Ubuntu 24.04 system Perl, threaded).  Its observations are recorded beside the
  target's; where they differ, the model follows 5.44.0 and the row is `version-divergent`.
- **Instrumented variants of 5.44.0:** `noreuse` (`plant_SV` never returns freed SV heads to `PL_sv_root`) and
  `descending` (arenas threaded from the highest slot down).  A program whose output is not identical across stock,
  `noreuse`, and `descending` after address bijection is `allocator-sensitive` and is not an exact-comparison oracle.

## Widths and numeric configuration

- x86-64: `ivsize=8`, `uvsize=8`, `nvsize=8` (double), `longdblsize=16`, `use64bitint=define`.
- `NV_PRESERVES_UV` is **undefined**; `NV_PRESERVES_UV_BITS=53`.  The models transcribe the `#else` branches of
  `S_sv_2iuv_common`, `sv_2iv_flags`, and `sv_2nv_flags`.  A 32-bit Perl (`ivsize=4`) defines `NV_PRESERVES_UV` and runs
  the other branches; it is outside this profile.
- `d_double_has_nan=define`.  NaN payload spellings and long-double or quadmath builds are not covered.

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

- Numeric-radix probes and lanes use a locale the harness compiles from its own source (`radix_comma`: `LC_NUMERIC`
  with `decimal_point ","`, every other category POSIX); ctype probes use `ctype_utf8` (`LC_CTYPE` from the glibc
  `i18n` classification, every other category POSIX).  The sources are `harness/locales/`;
  `harness/lib/Oracle/Locales.pm` compiles them with the system's `localedef` against the system's own `i18n` sources
  at startup, so no probe depends on which locales the system has generated.  The compiled form is keyed by the
  sources and the `localedef` version, so a changed glibc recompiles.
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
