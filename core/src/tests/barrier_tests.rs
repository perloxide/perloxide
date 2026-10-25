use super::*;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
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

/// The owner/foreigner handshake the sharing tier uses, as a mutual-exclusion check: an owner brackets a plain
/// increment with `inside` and light barriers; a foreigner sets `converting`, issues a heavy barrier, and proceeds only
/// when it sees `inside` clear.  While the foreigner holds `converting` the owner must be excluded, so two reads of the
/// counter must agree.  Any violation is a lost or interleaved update, which is exactly what the heavy barrier exists
/// to rule out.
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

    let owner = {
        let (inside, converting, counter, stop) = (inside.clone(), converting.clone(), counter.clone(), stop.clone());
        thread::spawn(move || {
            let mut ops = 0u64;
            while !stop.load(Ordering::Relaxed) {
                inside.store(true, Ordering::Relaxed);
                light();

                while converting.load(Ordering::Acquire) {
                    std::hint::spin_loop();
                }

                let v = counter.load(Ordering::Relaxed);
                counter.store(v + 1, Ordering::Relaxed);
                light();

                inside.store(false, Ordering::Release);
                ops += 1;
            }
            ops
        })
    };

    let deadline = Instant::now() + Duration::from_millis(200);
    let mut observed = 0u64;
    let mut backed_off = 0u64;
    while Instant::now() < deadline {
        converting.store(true, Ordering::SeqCst);
        heavy().unwrap();

        if inside.load(Ordering::Acquire) {
            converting.store(false, Ordering::Release);
            backed_off += 1;
            std::hint::spin_loop();
            continue;
        }

        let first = counter.load(Ordering::Relaxed);
        for _ in 0..64 {
            std::hint::spin_loop();
        }

        let second = counter.load(Ordering::Relaxed);
        converting.store(false, Ordering::Release);

        assert_eq!(first, second, "the owner ran while the foreigner held the cell");
        observed += 1;
    }

    stop.store(true, Ordering::Relaxed);
    let ops = owner.join().unwrap();
    assert!(ops > 0 && observed > 0, "ops={ops} observed={observed} backed_off={backed_off}");
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
