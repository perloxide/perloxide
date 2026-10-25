# SS: `local` and the save stack

**Source.**  Transcribed from the perl5 repository at tag `v5.44.0`: scope.c, mg.c (`mg_localize`) and the localizing
arms of pp_hot.c and pp.c.  Validated by replay against the supported 5.44.0 builds; results in `reports/`; the matching
5.38.2 observation lines beside them are from the unsupported 5.38.2 (`../../unsupported-perls.md`).  A transcription is
of one version's C, so a replay mismatch on a supported version is either a model gap or a change in perl's own
implementation between the transcribed tag and that version; `version-divergent` rows name the second kind, and the tag
above is what a reader diffs against when one appears.

`SS.pm` transcribes scope.c's `local` machinery -- `save_scalar_at`, `save_scalar`, `save_aelem_flags`,
`save_helem_flags`, `save_adelete`/`save_hdelete`, `save_gp`, `save_clearsv`, `mg_localize`, `restore_sv`, `leave_scope`
and its record types -- plus the `pp_gvsv`/`pp_aelem`/`pp_helem` localizing arms that decide the entry `mg_set`, and the
structural operations the restore can land on (`av_shift`, `av_pop`, `av_fill`, `pp_unshift`, `pp_push`, `pp_splice`,
`pp_aassign` to an array), each routing a tied array to its method.

`generators/ss_gen.pl` enumerates 488 cells in two blocks.  The first is 312 cells: {plain, tied, magical (`$/`, `$0`),
glob-aliased} x {package scalar, element present, element absent, whole glob} x {bare, assignment, self-assignment} x
{no mutation, pre-`local`-ref mutation, container clear, delete} x {normal exit, die in body, die in a restoration
STORE, die in the displaced value's DESTROY} x nesting depth 1-2, observing the callback trace,
first-appearance-normalized addresses, final values, `exists`, and `$@`.  Address triples on tied-container element
mirrors are masked (reuse of a freed mirror's memory; see `undefined.md`).

The second is 176 structural cells: {plain array, tied array} x {element present (index 1 of three), element absent
(index 5, vivified by the `local`)} x {bare, assignment} x {no change, `shift`, `shift` twice, `unshift`, `pop`, `push`,
`splice` removing, `splice` inserting, `$#a = -1`, `$#a = 0`, clear-and-refill} x {normal exit, die in body}, observing
per-index (identity, `exists`, value) over indices 0-6 after the scope, the final `$#a`, and two references captured
inside the scope: one to the SV the `local` installed and one to the SV a removing operation handed back.  On the tied
array the methods a structural operation calls (`SHIFT`, `UNSHIFT`, `PUSH`, `POP`, `STORESIZE`, `EXTEND`, `SPLICE`) join
the trace, and the tie class's own semantics for them -- a store keyed by index that `SHIFT`, `UNSHIFT` and `SPLICE`
renumber -- are part of the test, transcribed into the model beside perl's.

    ORACLE=/path/to/perl perl generators/ss_gen.pl        # prints cells=488 ok=... mismatch=... crash=...
    ORACLE=... TABLE=reports/table.<ver>.tsv perl generators/ss_gen.pl

Recorded: 488/488 on 5.38.2 and 5.44.0, byte-identical observation lines (`reports/`).  The section text is
`section.md`.  A snake_case routine in `SS.pm` mirrors the perl function or macro of that name (`Perl_`/`S_` removed:
`SvREFCNT_inc`, `sv_2mortal`, `av_fetch`, `mg_find`, `pp_nextstate`, `pp_aelem`); what has no C counterpart is harness
glue in `SS::Harness` (`Read`, `Store`, `StoreRef`, `RetainPayload`, `ReleasePayload`, `Trace`, `Show`, `Reset`).  The
key is audited below.

## Key

The model's state is derived from the structs it covers, field by field, as the reference requires (`README.md`, Keys).
Source citations are perl 5.44.0.  "Modeled" names the `SS.pm` field; an exclusion gives the reason a field cannot
decide a future observable within the lane, or the lane assertion that keeps it constant.

**Save-stack records** (`scope_types.h`, `scope.c`).  Every record the lane can push, with the slots `SS_ADD` writes:

| Record          | Slots (scope.c)                                                     | Modeled                                                         |
|-----------------|---------------------------------------------------------------------|-----------------------------------------------------------------|
| `SAVEt_SV`      | `gv`, old `sv` (`save_scalar`, 364)                                 | `['SV', gvname, cell]`                                          |
| `SAVEt_AELEM`   | `av`, `idx`, old `sv` (`save_aelem_flags`)                          | `['AELEM', avid, idx, cell]`                                    |
| `SAVEt_HELEM`   | `hv`, key copy (`newSVsv`), old `sv` (`save_helem_flags`)           | `['HELEM', hvid, key, cell]`                                    |
| `SAVEt_ADELETE` | `av`, `idx` (`save_adelete`)                                        | `['ADELETE', avid, idx]`                                        |
| `SAVEt_DELETE`  | `hv`, key bytes (`savepvn`), `klen` (`save_hdelete`)                | `['HDELETE', hvid, key]`                                        |
| `SAVEt_GP`      | `gv`, old `gp` (`save_gp`, 526)                                     | `['GP', gvname, gpid]`                                          |
| `SAVEt_CLEARSV` | pad offset (`save_clearsv`)                                         | `['CLEARSV', \$padslot]`                                        |
| `SAVEt_FREESV`  | `sv` (pushed by `restore_sv` before a fallible `mg_set`, 1245-1249) | `['FREESV', cell]`                                              |
| `SAVEt_FREEPV`  | key bytes (pushed by the `SAVEt_DELETE` arm before `hv_delete`)     | not modeled: the copied key has no observable; freed either way |

The `SAVEt_ADELETE` and `SAVEt_DELETE` arms rewrite their own frame into `SAVEt_FREESV` for the container before the
delete (scope.c 1640-1650); the container refcount it releases is excluded below, so the rewrite has no model.

**`SV`** (`sv.h`), for a cell:

| Field                              | Modeled / excluded                                                                                                                                                                                                                                                                                                         |
|------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `sv_refcnt`                        | `rc`; every `SvREFCNT_inc`/`dec` the lane performs is transcribed, and reaching zero runs `DESTROY` (`obj`)                                                                                                                                                                                                                |
| `SVs_GMG`, `SVs_SMG`               | `gmag`, `smag`; the gates of `mg_get` (`save_scalar`, 359) and `mg_set` (`restore_sv`, 1243)                                                                                                                                                                                                                               |
| `SVs_RMAGICAL`                     | excluded: read by `av_fetch` (av.c 271) and `av_delete` (av.c 1071) only to route a tied container, which the model routes by `tie`                                                                                                                                                                                        |
| `SVs_OBJECT`                       | `obj`; read by the `SAVEt_CLEARSV` arm (scope.c 1505) and by `S_curse` on the last release                                                                                                                                                                                                                                 |
| `SVs_TEMP`                         | excluded: set by `sv_2mortal`, which the model tracks as membership of `@TMPS`; nothing in the lane reads the flag                                                                                                                                                                                                         |
| `SVs_PADTMP`, `SVs_PADSTALE`       | excluded: `SvPADSTALE_on` in the clear arm (scope.c 1581) is read only by pad.c for closure capture, outside the lane                                                                                                                                                                                                      |
| `SvANY` (the body, value flags)    | opaque payload; the value side is `models/VF`                                                                                                                                                                                                                                                                              |
| `SvMAGIC` chain, order             | `mag`, in list order; `mg_get`/`mg_set` walk it in order as mg.c 283 does                                                                                                                                                                                                                                                  |
| `MAGIC.mg_type`                    | `t`, as `tied`, `tiedelem`, `sv`                                                                                                                                                                                                                                                                                           |
| `MAGIC.mg_obj`, `mg_ptr`, `mg_len` | `o` (tie object), `cont`/`key`/`kind` (tied element's container and key)                                                                                                                                                                                                                                                   |
| `MAGIC.mg_flags`                   | excluded: `MGf_LOCAL` selects `svt_local` in `mg_localize` (mg.c 498), which no lane magic defines; `MGf_GSKIP`, set by every tied-element `FETCH` (mg.c 2240) and cleared by the next set (mg.c 287), decides only whether a second get on one proxy re-`FETCH`es, and every lane proxy is read once before it is written |
| `MAGIC.mg_private`, `mg_virtual`   | excluded: the vtable is a function of `mg_type`                                                                                                                                                                                                                                                                            |
| `SvREADONLY`                       | excluded: copied onto the fresh cell by `mg_localize` (mg.c 505) and never read in the lane (no constant holders)                                                                                                                                                                                                          |

**`GP`** (`gv.h` 11):

| Field                                         | Modeled / excluded                                                                                                                                         |
|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `gp_sv`                                       | `sv`                                                                                                                                                       |
| `gp_refcnt`                                   | `rc`; `*x = *x` and `save_gp(gv, 0)` take a reference, `gp_free` releases                                                                                  |
| `gp_io`, `gp_cv`, `gp_hv`, `gp_av`, `gp_form` | excluded by lane: only the scalar slot is written (`*x = \$y`, `gv_setref`) or read                                                                        |
| `gp_cvgen`, `gp_egv`                          | excluded: method cache and effective GV, read by sub and method dispatch only                                                                              |
| `gp_line`, `gp_file_hek`, `gp_flags`          | excluded: diagnostics ("used only once"), never a value                                                                                                    |
| `GvINTRO`                                     | excluded: set by `save_gp(gv, 0)` (scope.c 549) and read by `gv_fetchpvn_flags` for the `local *x = ...` form, which the lane renders as a slot assignment |

**`AV`** (`av.h` 14-16), plain arrays:

| Field                   | Modeled / excluded                                                                                                       |
|-------------------------|--------------------------------------------------------------------------------------------------------------------------|
| `AvARRAY[0..FILLp]`     | `elems`; `undef` entries are NULL slots                                                                                  |
| `xav_fill`              | `$#{elems}`                                                                                                              |
| `xav_max`, `xav_alloc`  | excluded: capacity and the slide room `av_unshift` uses (av.c 888); they decide where slots live, never what they hold   |
| `AvREAL`, `AvREIFY`     | asserted: lane arrays are package arrays, always real; `av_reify` never runs                                             |
| `SVs_SMG` on the array  | excluded: `mg_set(av)` after a structural op (av.c 960) serves `@ISA` and tied arrays; the lane's plain arrays have none |
| tied: `PERL_MAGIC_tied` | `tie`, with the tie's own store (`store`, `top`) standing in for the tie object's state                                  |

**Interpreter state.**  `PL_tmps_stack` is `@TMPS`, freed at `pp_nextstate`.  `PL_localizing` is excluded: it is set to
1 around the entry `mg_get` and to 2 around the exit `mg_set` (scope.c 360, 1252), and read to skip `$_` (mg.c 177, 279)
and value magic (mg.c 290, `PERL_MAGIC_VALUE_MAGIC` in `mg_raw.h`), neither of which the lane localizes: tied scalars
(`q`), tied elements (`p`) and `$/`/`$0` (`\0`) are not value magic.  `PL_savestack_ix` is `@SS`'s length.

**Not modeled**: `SAVEf_KEEPOLDELEM` (scope.c 330, the `local $x[0] = $x[0]` fast path is not taken by the lane's
self-assignment form, which goes through the normal save); hashes' structural change (none exists beyond clear and
delete, both covered).
