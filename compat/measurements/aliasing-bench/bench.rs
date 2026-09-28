// Micro-benchmarks for two reimplementation design questions (measurements, not facts about perl).
//
// Section 1 (ask 2): what does a per-task tmps stack with block floors cost,
// per iteration of `for (1..1e7) { my $t = f() }`, on top of the slot layout?
// The loop body models: f() creates a temporary, the temporary is registered
// on the tmps stack (sv_2mortal), its value is copied into the pad slot, and
// the loop body's statement boundary drains the tmps stack to the floor
// (FREETMPS at pp_nextstate), with the block's floor save/restore
// (cx_pushblock / cx_popblock) around it.
//
// Section 2 (ask 3): the refcount tier rule. Cost of non-atomic inc/dec pairs
// (task-local tier) vs atomic Relaxed-inc / Release-dec pairs (published
// tier), and the common-case cost of the publication barrier: a predictable
// branch on the destination's SHARED header bit at every pointer store into
// an aggregate.
//
// Single-core container; absolute numbers are rough, deltas are the point.

use std::hint::black_box;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Instant;

// A heap temporary comparable to a Cell body or FatBody: header word + payload.
struct TmpBody {
    rc: u32,
    val: u64,
}

const LOOP_ITERS: u64 = 10_000_000;
const OP_ITERS: u64 = 100_000_000;

fn ns_per(iters: u64, secs: f64) -> f64 {
    secs / iters as f64 * 1e9
}

// Heap temp, freed directly at last use: no tmps machinery at all.
fn tmps_baseline_heap() -> f64 {
    let mut slot: u64 = 0;
    let t = Instant::now();
    for i in 0..LOOP_ITERS {
        let b = Box::new(TmpBody { rc: 1, val: i });
        slot = black_box(b.val);
        drop(black_box(b));
    }
    black_box(slot);
    ns_per(LOOP_ITERS, t.elapsed().as_secs_f64())
}

// Heap temp routed through the tmps stack with a per-iteration floor.
fn tmps_floor_heap() -> f64 {
    let mut tmps: Vec<Box<TmpBody>> = Vec::with_capacity(64);
    let mut slot: u64 = 0;
    let t = Instant::now();
    for i in 0..LOOP_ITERS {

        // cx_pushblock: save the floor, raise it to the current top.
        let floor = black_box(tmps.len());
        let b = Box::new(TmpBody { rc: 1, val: i });
        slot = black_box(b.val);

        // sv_2mortal: the temporary is registered for deferred release.
        tmps.push(b);

        // pp_nextstate FREETMPS: drain to the floor; cx_popblock restores it.
        tmps.truncate(black_box(floor));
    }
    black_box(slot);
    black_box(&tmps);
    ns_per(LOOP_ITERS, t.elapsed().as_secs_f64())
}

// Inline 16-byte Value temp, no heap: isolates the pure floor machinery.
#[derive(Clone, Copy)]
struct Value {
    tag: u8,
    flags: u8,
    marks: u8,
    _pad: [u8; 5],
    payload: u64,
}

fn tmps_baseline_inline() -> f64 {
    let mut slot: u64 = 0;
    let t = Instant::now();
    for i in 0..LOOP_ITERS {
        let v = Value { tag: 1, flags: 0, marks: 0, _pad: [0; 5], payload: i };
        slot = black_box(v.payload);
    }
    black_box(slot);
    ns_per(LOOP_ITERS, t.elapsed().as_secs_f64())
}

fn tmps_floor_inline() -> f64 {
    let mut tmps: Vec<Value> = Vec::with_capacity(64);
    let mut slot: u64 = 0;
    let t = Instant::now();
    for i in 0..LOOP_ITERS {
        let floor = black_box(tmps.len());
        let v = Value { tag: 1, flags: 0, marks: 0, _pad: [0; 5], payload: i };
        slot = black_box(v.payload);
        tmps.push(v);
        tmps.truncate(black_box(floor));
    }
    black_box(slot);
    black_box(&tmps);
    ns_per(LOOP_ITERS, t.elapsed().as_secs_f64())
}

fn rc_plain() -> f64 {
    let mut rc: u32 = 1;
    let t = Instant::now();
    for _ in 0..OP_ITERS {
        rc = rc.wrapping_add(1);
        black_box(&mut rc);
        rc = rc.wrapping_sub(1);
        black_box(&mut rc);
    }
    black_box(rc);
    ns_per(OP_ITERS, t.elapsed().as_secs_f64())
}

fn rc_atomic() -> f64 {
    let rc = AtomicU32::new(1);
    let t = Instant::now();
    for _ in 0..OP_ITERS {
        rc.fetch_add(1, Ordering::Relaxed);
        black_box(&rc);
        rc.fetch_sub(1, Ordering::Release);
        black_box(&rc);
    }
    black_box(rc.load(Ordering::Relaxed));
    ns_per(OP_ITERS, t.elapsed().as_secs_f64())
}

struct Aggregate {
    header: u64,
    field: u64,
}

const SHARED_BIT: u64 = 1 << 0;

// Plain pointer-sized store into an aggregate's field.
fn store_plain() -> f64 {
    let mut agg = Aggregate { header: 0, field: 0 };
    let t = Instant::now();
    for i in 0..OP_ITERS {
        agg.field = black_box(i);
        black_box(&mut agg);
    }
    ns_per(OP_ITERS, t.elapsed().as_secs_f64())
}

// The same store behind the publication check: if the destination is shared
// and the stored value is task-local, the publish walk would run. The bit is
// never set here, so this measures the common-case tax of the check itself.
#[inline(never)]
fn publish_walk(agg: &mut Aggregate) {
    agg.header |= SHARED_BIT << 1;
}

fn store_checked() -> f64 {
    let mut agg = Aggregate { header: 0, field: 0 };
    let t = Instant::now();
    for i in 0..OP_ITERS {
        if black_box(agg.header) & SHARED_BIT != 0 {
            publish_walk(&mut agg);
        }
        agg.field = black_box(i);
        black_box(&mut agg);
    }
    ns_per(OP_ITERS, t.elapsed().as_secs_f64())
}

fn main() {
    println!("iters: loop={} op={}", LOOP_ITERS, OP_ITERS);
    let bh = tmps_baseline_heap();
    let fh = tmps_floor_heap();
    println!("tmps heap-temp:   baseline={:.2} ns/iter  floored={:.2} ns/iter  delta={:.2}", bh, fh, fh - bh);
    let bi = tmps_baseline_inline();
    let fi = tmps_floor_inline();
    println!("tmps inline-temp: baseline={:.2} ns/iter  floored={:.2} ns/iter  delta={:.2}", bi, fi, fi - bi);
    let rp = rc_plain();
    let ra = rc_atomic();
    println!("rc pair:          plain={:.2} ns  atomic={:.2} ns  ratio={:.1}x", rp, ra, ra / rp);
    let sp = store_plain();
    let sc = store_checked();
    println!("ptr store:        plain={:.2} ns  shared-checked={:.2} ns  delta={:.2}", sp, sc, sc - sp);
}
