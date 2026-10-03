# oracle: a differential oracle harness for Perl

`oracle` runs Perl programs through Perl 5.44.0 and two allocator-instrumented builds of it, in three hash modes, and
classifies each program by what kind of comparison against Perl is meaningful.  The three builds come in two families,
unthreaded and `-Dusethreads`; a program runs in the unthreaded family unless it requires ithreads, and the other
family's stock build is its configuration cross-check.  It then checks an implementation under
test against the stored expected outputs, lane by lane.

The seed corpus is every probe from the value/type design research that produced this reference, with expected outputs.
`sources.md` lists the Perl source behind each probe's rule.

## Layout

| Path                                         | Contents                                                                                                                                       |
|----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| `bin/oracle`                                 | driver: `list`, `run`, `verdict`, `bless`, `selftest`, `check`                                                                                 |
| `lib/Oracle/Run.pm`                          | runs one program: pinned environment, stdout, stderr, fd 3, exit record, timeout                                                               |
| `lib/Oracle/Normalize.pm`                    | address bijection (`exact`) and line-order canonicalization (`canonical`)                                                                      |
| `lib/Oracle/Verdict.pm`                      | the classification rules below                                                                                                                 |
| `probe-lib/Probe.pm`                         | `__PROBE__($scalar, $label)`: flag projection written to fd 3                                                                                  |
| `lib/Oracle/Locales.pm`, `locales/`           | compiles the harness's own locales (`radix_comma`: comma radix, else POSIX; `ctype_utf8`: i18n ctype, else POSIX) |
| `../perls/build-perls.sh`                    | builds the six Perls (two families of three) from the GitHub tag; `--prepare-only` stops before compiling                                      |
| `../perls/noreuse.patch`                     | `plant_SV` never returns freed SV heads to `PL_sv_root`                                                                                        |
| `../perls/descending.patch`                  | `S_sv_add_arena` threads each new arena's free list from the highest slot down                                                                 |
| `../probes/corpus/*.pl`                      | seed corpus                                                                                                                                    |
| `../probes/corpus/expected/<test>/`          | blessed verdict and normalized outputs per test                                                                                                |
| `tools/gd_predict.pl`                        | arena-walk predictor for global destruction order (`gd_01_order.pl`)                                                                           |
| `tools/impl-wrong-seed.sh`                   | a deliberately wrong implementation, for exercising `check`                                                                                    |
| `tools/sources.tsv`, `tools/make-sources.pl` | citation table and the generator for `sources.md`                                                                                              |
| `oracle.conf`                                | interpreter paths; each overridable by `ORACLE_` plus its key in upper case (`ORACLE_STOCK`, `ORACLE_THREADS_STOCK`, ...)                      |

## Requirements

- The six builds from `../perls/build-perls.sh`: `perl-5.44.0`, `perl-5.44.0-noreuse`, `perl-5.44.0-descending`, and the
  same three with `-Dusethreads` as `perl-5.44.0-threads`, `perl-5.44.0-threads-noreuse` and
  `perl-5.44.0-threads-descending`.  A missing family only loses the tests that need it and the cross-check on the rest.
- Optional cross-check interpreter (`xcheck`, default `/usr/bin/perl`).  Its result is recorded as `agrees_with_xcheck`
  and never affects a verdict; the other family's stock build is recorded the same way as `agrees_with_xconfig`.
- Linux, core Perl modules only.
- `localedef` with the glibc i18n sources (the `locales` package on Debian and Ubuntu; part of glibc on most other
  distributions) for the locale probes: at startup the harness compiles its own locales from `locales/` into
  `RESULTS/locales` and passes that directory as `LOCPATH` to every run, so no probe depends on which locales the
  system has generated.  Tests whose requirements a build lacks are not run on that build.

## Quick start

    ../perls/build-perls.sh                                  # once; 15-30 minutes per build on one core
    bin/oracle run ../probes/corpus --results results        # run the corpus on the builds
    bin/oracle verdict ../probes/corpus --results results    # print per-test verdicts
    bin/oracle selftest ../probes/corpus --results results   # confirm this machine reproduces ../probes/corpus/expected
    bin/oracle check ../probes/corpus --results results --impl /path/to/implementation

## What happens to each test

Every test id (`file.pl`, or `file.pl@variant`) is run with this plan, in its family -- the threaded one if the test
requires threads, otherwise the unthreaded one.  The family's runs are recorded under the generic names whichever
family it is, and `RESULTS/<test>/family` says which:

| Build      | seed0  | seed1 | seed2 | seed3 | random |
|------------|--------|-------|-------|-------|--------|
| stock      | 2 runs | 1 run | 1 run | 1 run | 2 runs |
| noreuse    | 1 run  | 1 run | -     | -     | -      |
| descending | 1 run  | 1 run | -     | -     | -      |
| xcheck     | 1 run  | -     | -     | -     | -      |
| xconfig    | 1 run  | -     | -     | -     | -      |

`xcheck` is the other version (5.38.2); `xconfig` is the other family's stock build.  Neither affects a verdict.

- **Modes.** `seedN` sets `PERL_HASH_SEED=N`.  Seed 0 is Perl's NO perturbation mode, stable across versions and
  unaffected by unrelated hash activity; with any other fixed seed Perl perturbs keys deterministically from it, so each
  `seedN` run reproduces one hash order exactly.  The seed0 runs are *the seed0 group*; the seed1-seed3 runs are *the
  seed ladder*, three further hash orders with the allocator variants under one of them.  `random` leaves the seed unset
  (Perl's default, a fresh order each run); its two runs serve one rule only, stock Perl disagreeing with itself.
- **Environment.** Every run starts from `PATH`, `HOME=/tmp`, `LC_ALL=C`, `TZ=UTC`, plus the mode and the variant's
  variables.  Nothing else is inherited.  The program runs with its own directory as the working directory and its base
  name as the script name, so warnings read `at file.pl line N`.  stdin is `/dev/null`.
- **Channels.** stdout, stderr, fd 3, and an exit record (`exit N`, `signal N`, or `timeout`).
- **fd 3.** Programs that mention `__PROBE__` run with `-I probe-lib -MProbe`.  Each call writes `PROBE line=N label=L
  flags=CODE created_as=n|s|-`, where CODE uses I/N/P for public flags (always with the private one), i/n/p for
  private-only flags, then U (IVisUV), 8 (UTF8), R (ROK), RO (READONLY).  The implementation under test must accept `-I`
  and `-M` and produce the same projection.
- **Exact normalization.** Hex tokens of six or more digits after `0x` become `ADDR1`, `ADDR2`, ... in order of first
  appearance across stdout, stderr, fd 3.  Equal addresses stay equal.  The threaded-build warning suffix `, Perl
  interpreter: 0x...` is removed.
- **Canonical normalization.** The same tokens become a plain `ADDR`, and each channel's lines are sorted.

## Verdicts

Checked in this order:

| Verdict                 | Rule                                                                                                                             | Meaning                                                                                           |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `lane-A-eligible`       | exact-normalized outputs identical across stock seed0 run 1, stock seed0 run 2, noreuse seed0, and descending seed0              | output is a function of the program and the pinned hash seed alone                                |
| `lane-B-only`           | not lane-A-eligible, but canonical outputs are identical across the seed0 group and, separately, across the seed ladder          | the content is stable; only line order depends on the allocator, address values, or the hash seed |
| `perl-nondeterministic` | stock Perl disagrees with itself canonically, in seed0 or in random mode                                                         | output varies between identical runs (for example, it depends on address bits fed into a hash)    |
| `allocator-sensitive`   | stock Perl agrees with itself, but a patched allocator changes the canonical output                                              | output depends on SV head reuse or address order                                                  |
| `skipped`               | a required run is missing (requirements unmet on a build)                                                                        | no verdict                                                                                        |

**The gate.** A program is lane-A-eligible if and only if its output is identical across all three builds and across two
stock runs.  The two patched builds cover the two ways a program can observe the allocator without printing an address:
- *reuse:* noreuse removes it;
- *address order among fresh allocations:* descending reverses it.

Two tests in the seed corpus pass stock-versus-noreuse but fail descending: `addr_04_order_nofree.pl` (sorting fresh
references by address) and `destroy_01_weak.pl` (two package globals swap in `DESTRUCT`).

Each lane-A-eligible test also records `also_lane_b`: 1 when the seed0 group and the seed ladder all agree exactly,
meaning the output does not depend on hash order under four distinct orders either.  Every input to a verdict except the
random pair is a pinned-seed run, so a verdict and `also_lane_b` are properties of the program, and blessing the same
program twice writes the same files.

## What an implementer does with a result

`bin/oracle check ... --impl` runs the implementation at seed 0 and seed 1 and reports per test.  Mismatched
channels are written to `results/check-diffs/<test>.<comparison>.<channel>.{expected,actual}`.

| Verdict                 | Comparison                                                                                                  | A failure means                                                                                                                                                                  |
|-------------------------|-------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `lane-A-eligible`       | seed0, exact-normalized, every channel and the exit record; if `also_lane_b`, seed1 canonical as well       | a real divergence.  It includes hash iteration order, which requires an hv.c-faithful engine at seed 0.  Read the fd 3 trace first: the first differing PROBE line localizes it. |
| `lane-B-only`           | seed0 and seed1, canonical                                                                                  | content differs regardless of order: a missing, extra, or changed line.  Order-only differences are not reported.                                                                |
| `allocator-sensitive`   | none; the run must finish without `timeout` or `signal`                                                     | only crashes and hangs are failures.  The output is not specified by Perl and must not be used as an expected result.                                                            |
| `perl-nondeterministic` | same as allocator-sensitive                                                                                 | as above; fix the program if it was meant as a test.                                                                                                                             |
| `skipped`               | none                                                                                                        | -                                                                                                                                                                                |

The unthreaded stock Perl passes `check` with 35 PASS, 5 SMOKE and 2 SKIP (the two tests that require threads, which
an implementation without them is not asked to run); the threaded stock passes all 37 and smokes the same 5.
`tools/impl-wrong-seed.sh`, which forces `PERL_HASH_SEED=1`, fails exactly the eight lane-A tests whose seed-1 output
differs from their seed-0 output.

## Corpus directives

Comment lines anywhere in a test file:

    # oracle-requires: threads
    # oracle-requires: locale radix_comma.UTF-8   one of the harness's compiled locales (locales/)
    # oracle-variant: NAME VAR=VALUE ...     one test per variant; a file with variants has no default run
    # oracle-timeout: SECONDS

After adding or changing tests: `bin/oracle bless ../probes/corpus --results results`, review `git diff
../probes/corpus/expected`, commit.  `expected/<test>/` holds the verdict, the family, `also_lane_b`, and only the
channels a comparison uses: the exact seed0 channels (with the `xcheck` and `xconfig` ones beside them) for a lane-A
test, and the canonical seed0 and seed1 channels for a lane-B test or a lane-A test with `also_lane_b`.  An
allocator-sensitive or nondeterministic test records only its verdict.

## Seed corpus verdicts (Perl 5.44.0)

| Test                                   | Verdict               |
|----------------------------------------|-----------------------|
| `addr_01_reuse.pl`                     | allocator-sensitive   |
| `addr_03_insideout_warm.pl`            | allocator-sensitive   |
| `addr_04_order_nofree.pl`              | allocator-sensitive   |
| `gd_01_order.pl@resurrect`             | allocator-sensitive   |
| `consts_01_literal_mark.pl`            | lane-A-eligible       |
| `consumers_01.pl@default`              | lane-A-eligible       |
| `consumers_01.pl@use_b`                | lane-A-eligible       |
| `consumers_02_numeric_starts.pl`       | lane-A-eligible       |
| `destroy_02_order.pl`                  | lane-A-eligible       |
| `each_01_delete_current.pl`            | lane-A-eligible       |
| `each_02_delete_other.pl`              | lane-A-eligible       |
| `each_03_insert.pl`                    | lane-A-eligible       |
| `each_04_reset.pl`                     | lane-A-eligible       |
| `each_05_clear.pl`                     | lane-A-eligible       |
| `each_06_tied.pl`                      | lane-A-eligible       |
| `each_07_tied_keys_void.pl`            | lane-A-eligible       |
| `flags_01_observable.pl`               | lane-A-eligible       |
| `flags_matrix.pl`                      | lane-A-eligible       |
| `local_01_tied_elem.pl`                | lane-A-eligible       |
| `local_02_fresh_sv.pl`                 | lane-A-eligible       |
| `local_03_shared_elem_move.pl`         | lane-A-eligible       |
| `locale_01_setlocale_after_cache.pl`   | lane-A-eligible       |
| `locale_02_copy_across.pl`             | lane-A-eligible       |
| `locale_03_sub_boundary.pl`            | lane-A-eligible       |
| `locale_04_handler_setlocale.pl`       | lane-A-eligible       |
| `num_01_warn_handler.pl`               | lane-A-eligible       |
| `num_02_stale_cache.pl`                | lane-A-eligible       |
| `order_01_model.pl`                    | lane-A-eligible       |
| `order_02_modes.pl@noise0`             | lane-A-eligible       |
| `order_02_modes.pl@noise3`             | lane-A-eligible       |
| `order_02_modes.pl@noise50`            | lane-A-eligible       |
| `order_03_insert_warn_modes.pl`        | lane-A-eligible       |
| `probe_01_face_trace.pl`               | lane-A-eligible       |
| `threads_01_const_marks.pl`            | lane-A-eligible       |
| `value_01_stale_search.pl`             | lane-A-eligible       |
| `value_02_locale_radix.pl`             | lane-A-eligible       |
| `value_03_handler_reassign_by_path.pl` | lane-A-eligible       |
| `destroy_01_weak.pl`                   | lane-B-only           |
| `gd_01_order.pl@plain`                 | lane-B-only           |
| `gd_01_order.pl@prime`                 | lane-B-only           |
| `addr_02_observable.pl`                | perl-nondeterministic |

`local_03_shared_elem_move.pl` and `threads_01_const_marks.pl` require ithreads and were blessed in the threaded family
(`expected/<test>/family`).  Every lane-A test of the unthreaded family agrees exactly with the threaded stock build
(`agrees_with_xconfig=1`); the only disagreements are `gd_01_order.pl@prime` (lane B) and `addr_02_observable.pl`
(nondeterministic), whose outputs are not functions of the program to begin with.

## Provisional choices

These are harness decisions made while building it.  Each lives in one place and is easy to change.

- **`lane-B-only` means "stable after sorting lines."** It is the one verdict whose rule was not specified in advance.
  It is implemented in `Verdict.pm` as line-multiset equality within the seed0 group and within the seed ladder.  An
  alternative reading is "hash-order-independent," which is what `also_lane_b` records instead.
- **Address normalization** matches only `0x` plus six or more hex digits.  Decimal `refaddr` values are not normalized,
  so a program that prints them is classified `perl-nondeterministic`.  Hash traversal masks printed in hex are
  normalized as if they were addresses.
- **Run counts** are two stock runs at seed 0, one per further rung, one per patched build per rung it joins, and two
  random runs.  The ladder's seeds (1, 2, 3) are arbitrary; any fixed seeds would do, and more rungs are cheap.
- **Cross-checks** (5.38.2, and the other family's stock build) are informational only.
- **Lane B comparisons** erase address identity, since tokens can't be numbered consistently across reordered lines.

## Known limitations

- No program generator and no minimizer yet.  The research specification for both is in the design thread.
- The allocator gate uses two perturbations, reuse and fresh-address order.  A program sensitive only to some other
  allocator property would pass it.
- `../perls/build-perls.sh` has been run end to end on Ubuntu 24.04 (two cores, about three minutes per build); the
  patches apply to a fresh v5.44.0 checkout in both families.
