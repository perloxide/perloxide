use super::*;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant};

#[test]
fn detection_and_heavy_agree() {
    assert_eq!(is_available(), backend() != Backend::Unavailable);
    assert_eq!(heavy().is_ok(), is_available(), "heavy succeeds exactly where a backend exists");
    assert_eq!(backend(), backend(), "detection is memoized");
}

#[cfg(all(target_os = "linux", any(target_arch = "x86", target_arch = "x86_64")))]
#[test]
fn linux_x86_always_has_a_backend() {
    assert!(matches!(backend(), Backend::Membarrier | Backend::Mprotect), "{:?}", backend());
}

#[cfg(all(target_os = "linux", any(target_arch = "x86", target_arch = "x86_64")))]
#[test]
fn mprotect_trick_runs_and_serializes() {
    assert!(platform::mprotect::supported());
    for _ in 0..8 {
        platform::mprotect::barrier().unwrap();
    }
    let threads: Vec<_> = (0..4).map(|_| thread::spawn(|| (0..32).all(|_| platform::mprotect::barrier().is_ok()))).collect();
    for t in threads {
        assert!(t.join().unwrap());
    }
}

#[test]
fn light_is_free_to_call() {
    for _ in 0..1_000 {
        light();
    }
}

/// The owner/foreigner handshake the sharing tier uses (design.md §2.4), as a mutual-exclusion check.  An owner
/// brackets a plain increment with `inside` and light barriers, and withdraws — stores `inside` clear and waits — when
/// its entry finds `converting` set.  A foreigner sets `converting`, issues one heavy barrier, waits until it sees
/// `inside` clear, and then holds the cell: the barrier made the owner's executed stores visible, and an owner that
/// enters afterward sees `converting` and withdraws.  While the foreigner holds the cell the owner must be excluded, so
/// two reads of the counter must agree.  Any violation is a lost or interleaved update, which is exactly what the heavy
/// barrier exists to rule out.
///
/// The roles are asymmetric on purpose: only the owner ever backs off.  A foreigner that backed off whenever it saw the
/// owner inside would phase-lock with an owner that waits inside, each yielding to the other, and the test would then
/// pass or fail on scheduling noise.
#[test]
fn asymmetric_handshake_excludes_the_owner() {
    if !is_available() {
        return;
    }
    handshake(heavy);
}

#[cfg(all(target_os = "linux", any(target_arch = "x86", target_arch = "x86_64")))]
#[test]
fn asymmetric_handshake_holds_under_the_mprotect_trick() {
    handshake(platform::mprotect::barrier);
}

fn handshake(heavy: fn() -> Result<(), BarrierError>) {
    let inside = Arc::new(AtomicBool::new(false));
    let converting = Arc::new(AtomicBool::new(false));
    let counter = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(AtomicBool::new(false));

    let ops_seen = Arc::new(AtomicU64::new(0));
    let owner = {
        let (inside, converting, counter, stop) = (inside.clone(), converting.clone(), counter.clone(), stop.clone());
        let ops_seen = ops_seen.clone();
        thread::spawn(move || {
            let mut ops = 0u64;
            let mut withdrawals = 0u64;
            while !stop.load(Ordering::Relaxed) {
                // Entry: announce, then look for a converter; on finding one, withdraw and wait outside.
                inside.store(true, Ordering::Relaxed);
                light();
                if converting.load(Ordering::SeqCst) {
                    inside.store(false, Ordering::Release);
                    withdrawals += 1;
                    while converting.load(Ordering::Acquire) {
                        std::hint::spin_loop();
                    }

                    continue;
                }

                // The operation: plain, non-atomic in spirit (a load and a store rather than a locked increment).
                let v = counter.load(Ordering::Relaxed);
                counter.store(v + 1, Ordering::Relaxed);

                // Exit.
                light();
                inside.store(false, Ordering::Release);
                ops += 1;
                ops_seen.store(ops, Ordering::Relaxed);
            }
            (ops, withdrawals)
        })
    };

    // Each round converts once and then lets the owner complete at least one operation before the next round, so that
    // the rounds interleave with the owner rather than starving it.  The run lasts at least 200 ms; every wait in it is
    // bounded so that a protocol that stops making progress fails rather than hangs.
    let floor = Instant::now() + Duration::from_millis(200);
    let bound = Instant::now() + Duration::from_secs(10);
    let mut observed = 0u64;
    let mut found_inside = 0u64;
    while Instant::now() < floor {
        converting.store(true, Ordering::SeqCst);
        heavy().unwrap();

        // The owner may be mid-operation; it finishes that one, and its next entry withdraws.
        if inside.load(Ordering::Acquire) {
            found_inside += 1;
            while inside.load(Ordering::Acquire) {
                assert!(Instant::now() < bound, "the owner never left: observed={observed} found_inside={found_inside}");
                std::hint::spin_loop();
            }
        }

        let first = counter.load(Ordering::Relaxed);
        for _ in 0..64 {
            std::hint::spin_loop();
        }

        let second = counter.load(Ordering::Relaxed);
        converting.store(false, Ordering::Release);

        assert_eq!(first, second, "the owner ran while the foreigner held the cell");
        observed += 1;

        let seen = ops_seen.load(Ordering::Relaxed);
        while ops_seen.load(Ordering::Relaxed) == seen {
            assert!(Instant::now() < bound, "the owner made no progress after a conversion: ops={seen} observed={observed}");
            std::hint::spin_loop();
        }
    }

    stop.store(true, Ordering::Relaxed);
    let (ops, withdrawals) = owner.join().unwrap();
    eprintln!("handshake: ops={ops} observed={observed} withdrawals={withdrawals} found_inside={found_inside}");
    assert!(ops > 0 && observed > 0, "ops={ops} observed={observed} withdrawals={withdrawals} found_inside={found_inside}");
}

#[test]
#[ignore = "timing, for the record: run with --ignored --nocapture"]
fn heavy_cost() {
    if !is_available() {
        return;
    }

    let n = 2_000;
    let start = Instant::now();
    for _ in 0..n {
        heavy().unwrap();
    }

    let per = start.elapsed() / n;
    eprintln!("{:?}: heavy barrier {per:?} each", backend());
    if platform_has_mprotect() {
        let start = Instant::now();
        for _ in 0..n {
            platform::mprotect::barrier().unwrap();
        }
        eprintln!("Mprotect: heavy barrier {:?} each", start.elapsed() / n);
    }
}

fn platform_has_mprotect() -> bool {
    cfg!(all(target_os = "linux", any(target_arch = "x86", target_arch = "x86_64")))
}

/// The owner's fast path of the sharing tier against the atomic path and the plain arithmetic alone, per clone/release
/// pair.  Timing, for the record: run with --release --ignored --nocapture.
#[test]
#[ignore = "timing, for the record: run with --release --ignored --nocapture"]
fn owner_path_cost() {
    const PAIRS: u64 = 50_000_000;
    let state = AtomicU8::new(0);
    let converting = AtomicU8::new(0);
    let count = AtomicU32::new(1);

    let start = Instant::now();
    for _ in 0..PAIRS {
        count.fetch_add(1, Ordering::Relaxed);
        count.fetch_sub(1, Ordering::Release);
    }
    let atomic = start.elapsed().as_nanos() as f64 / PAIRS as f64;

    let start = Instant::now();
    for _ in 0..PAIRS {
        for _ in 0..2 {
            if state.load(Ordering::Relaxed) == 2 {
                state.store(1, Ordering::SeqCst);
            } else {
                state.store(1, Ordering::Relaxed);
            }
            light();

            while std::hint::black_box(converting.load(Ordering::SeqCst)) != 0 {
                std::hint::spin_loop();
            }
            let c = count.load(Ordering::Relaxed);
            count.store(std::hint::black_box(c).wrapping_add(1), Ordering::Relaxed);
            light();

            state.store(0, Ordering::Release);
        }
    }
    let owner = start.elapsed().as_nanos() as f64 / PAIRS as f64;

    let start = Instant::now();
    for _ in 0..PAIRS {
        for _ in 0..2 {
            let c = count.load(Ordering::Relaxed);
            count.store(std::hint::black_box(c).wrapping_add(1), Ordering::Relaxed);
        }
    }

    let plain = start.elapsed().as_nanos() as f64 / PAIRS as f64;
    eprintln!("per clone+release pair: atomic {atomic:.2} ns, owner path {owner:.2} ns, plain floor {plain:.2} ns");
}
