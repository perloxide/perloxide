# Measurements

Benchmarks and graph walks from the design research. They measure costs on a particular machine
and are not facts about perl; they are kept beside the probes they accompanied.

- `aliasing_bench.c`: per-iteration cost of a registry-plus-proxy aliasing scheme versus
  promote-on-bind (gcc -O2).
- `aliasing-bench/bench.rs` (+ results): packed-page traversal versus proxy versus side-table
  promotion, and perl 5.44's own loop, per element.
- `walk_stash.pl`: the stash-reachable object graph of a Moose + Mojolicious + DateTime image
  (188,338 SVs / 232,346 edges), and `bench_walk.rs`: a flip-walk over that graph (13 ms).
