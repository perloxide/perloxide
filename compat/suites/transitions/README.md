# Transition tables from the value-flags enumerations (pre-consolidation key generation)

These are the oracle records of the enumerations that produced and validated the value-flags model before its key was
audited against sv.h: Perl's observed `(start, state, op) -> state` transitions, recorded on 5.38.2 and 5.44.0. They are
kept as blessed outputs of that generation; the current verification of the model is `models/VF/reports/coverage.txt`,
under a key that carries more state, and counts across the two generations are not comparable.

- `transitions/`: the 13-op core, depth 3 from 18 starts and depth 4 from the 13 string starts (7,628 and 21,518 raw
  transitions), raw and abstract tables per Perl; byte-identical across Perls.
- `extended/`: the 56-op set at depth 3 (295,858 transitions), abstract table only; the raw table's hash is recorded for
  regeneration checks.
- `locale/`: the locale axis (radix acceptance and caching under a comma-radix locale), 1,152 transitions per Perl,
  identical across Perls.

Every table here replayed with zero mismatches against the model of its generation on both Perls.
