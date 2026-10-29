# Bugs in perl

Defects in `perl` itself that the reference records: what goes wrong, the source that causes it, the versions it
affects, and what shows it.  A window in `undefined.md` that a bug opens names the bug here.

Each bug is a level-two heading, `` ## `id`: title ``, followed by a `- versions:` line and the description.  The
versions are a comma-separated list of items, each a version (`5.44.0`), a range (`5.32.4 - 5.39.7`), or an open range
(`* - 5.39.7` for every version through 5.39.7, `5.32.4 - *` for every version from 5.32.4 on), or `*` for every
version; a build (`5.44.0-threads`) is affected when its version is.  `Perl::Conformance::PerlBugs` reads this file.

The harness assumes a bug is present in every version its entry lists.  A run on such a version whose results show the
bug absent -- a fix, or an entry whose versions are wrong -- stops and reports it, so the versions are corrected from
the source before anything is recorded.  On a version the entry does not list, the bug's marks are dropped and the
results are recorded as ordinary observations.

## `warn-handler-continuation`: a conversion continues on a scalar its `__WARN__` handler replaced

- versions: `*`

The numeric conversions warn about a string that is not a number (`S_not_a_number`) in the middle of converting it, and
the warning runs any `__WARN__` handler, which may assign to the very scalar being converted.  When the handler returns,
the conversion carries on with what it read before the warning and writes the scalar's slots and flags without looking
at the scalar again.  What happens next depends on what the handler stored, and gives the three windows of
`undefined.md`:

- W1, a number or `undef`: the assignment freed the string buffer, and `Perl_sv_2nv_flags` parses it anyway
  (`S_sv_setnv`, `Atof` on `SvPVX`): `SIGSEGV`.
- W2, a reference: `SvPVX` and `SvRV` share the `sv_u` union, so `Atof` parses the referent's SV head as a string.  The
  result is whatever digits that memory happens to start with, which moves with the memory layout from run to run
  (usually 0, sometimes 8 or 82); the result is recorded as `?`.
- W3, a reference, when the string's NV is infinite (`'Infx'`): `S_sv_2iuv_common` parses the string, warns, and then
  fills the IV slot from that NV; an infinite NV goes through `S_sv_2iuv_non_preserve`, which sets `SVf_IVisUV`.
  `SVf_IVisUV` and `SVprv_WEAKREF` are the same bit (`0x80000000`, `sv.h`, since weak references arrived in 5.6.0), so
  the reference is now weak (`Scalar::Util::isweak` is true), and freeing or reassigning it croaks `panic: del_backref,
  svp=0` (`Perl_sv_del_backref` finds no back-reference list on the referent).  Deterministic: the conversion's values
  are right; the panic comes when the scalar goes.

The warn-then-continue code has the same shape from 5.6.0 (`Perl_sv_2nv`: `not_a_number`, then `Atof(SvPVX(sv))`)
through 5.44.0; the bug is observed on 5.38.2 and on every 5.44.0 build.  Shown by the `__WARN__`-handler matrix,
`models/ValueFlags/generators/gen_vf.pl`: 108 W1 rows end in CRASH, 36 W2 rows in `?`, and 6 W3 rows record the panic
(`models/ValueFlags/reports/matrix.tsv`).
