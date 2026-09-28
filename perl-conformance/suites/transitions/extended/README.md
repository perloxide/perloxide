# 56-op transition tables (13-op core plus 43 string and numeric operators), depth 3, 24 starts

Produced by the pre-consolidation generator (`gen3.pl`, flags-plus-slots key) on Perl 5.38.2 and 5.44.0: 295,858 raw
transitions and 11,988 states per Perl, byte-identical between the two Perls; the abstract table (values abstracted,
keyed by start, flags, and op; CONFLICT marks rows decided by content class) has 26,390 rows.  The model replayed all of
them with zero mismatches on both Perls under that key generation.

The raw table (15.3 MB per Perl, identical) is not stored: it is regenerated in about fifteen minutes per Perl on one
core, and its sha256 is recorded here so a regeneration can be checked:

    raw_transitions.tsv  sha256 67232099dce498895241b7c3bb0483e71b45557f854ac94dcd4af6496bb37722

`abstract_table.tsv.gz` is the abstracted table (identical for both Perls).  Counts under the struct-audited key are in
`models/VF/reports/coverage.txt`; the two key generations are not comparable.
