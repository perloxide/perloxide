//! A process-wide asymmetric memory barrier.
//!
//! Two parties synchronize at unequal cost.  The *light* side issues only a compiler fence, so its path contains no
//! fence instruction and no locked operation; the *heavy* side pays a system call that makes every thread of the
//! process execute a full fence.  The guarantee is the one an asymmetric barrier always gives: once [`heavy`] returns,
//! every store any thread had executed before the call is visible to the caller, and every load any thread executes
//! after the call sees every store the caller made before it.  A thread off-CPU at the time is covered too — its stores
//! drained when it was switched out, and it resumes behind the barrier.
//!
//! The per-object sharing tier (design.md §2.4) rests on this.  The owner of an unshared cell brackets each access with
//! ordinary stores to an `inside` flag and a [`light`] barrier on either side; a foreign task/thread that wants the
//! cell sets `converting`, issues [`heavy`], and only then trusts what it reads of `inside`.  Without the heavy barrier
//! the owner's flag store could still sit in its store buffer while the foreigner read the old value — the
//! store-then-load reordering that no combination of release and acquire prevents — and the only alternatives are a
//! full fence on the owner's every access, which is the cost the tier exists to avoid, or an interrupt to the owner's
//! core, which is what the system call delivers.
//!
//! Backends, chosen once at first use:
//!
//! - Linux `membarrier(2)`, `MEMBARRIER_CMD_PRIVATE_EXPEDITED` (kernel 4.14 and later): an inter-processor interrupt to
//!   every core currently running a thread of this process.  The command needs a one-time registration, which is per
//!   address space; a `fork`ed child re-registers on its first barrier if the kernel asks it to.
//! - Linux on x86 without that command: an `mprotect(2)` trick.  Revoking write access to a dirty page forces a TLB
//!   shootdown on every core that has the page mapped, and the shootdown's interrupt is a full fence on each.  The
//!   kernel does not document the shootdown as a barrier, and other architectures may flush TLBs without an interrupt,
//!   so the trick is enabled only where it is known to hold.
//! - Windows `FlushProcessWriteBuffers`.
//!
//! Elsewhere the barrier is [`Backend::Unavailable`]: [`heavy`] reports it rather than pretending, and the sharing tier
//! stays off, so the light side never runs on a hot path there.  A caller gates on [`is_available`] before building a
//! protocol on the pair.

use std::fmt;
use std::sync::LazyLock;
use std::sync::atomic::{Ordering, compiler_fence};

/// Which mechanism [`heavy`] uses on this machine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    /// Linux `membarrier(2)` with the private expedited command.
    Membarrier,

    /// The `mprotect(2)` TLB-shootdown trick, x86 Linux only.
    Mprotect,

    /// Windows `FlushProcessWriteBuffers`.
    FlushProcessWriteBuffers,

    /// No process-wide barrier exists here; [`heavy`] fails and the asymmetric protocol must not be used.
    Unavailable,
}

/// Why a heavy barrier did not happen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BarrierError {
    /// This platform has no process-wide barrier.
    Unavailable,

    /// The system call failed; the value is the OS error number.
    Os(i32),
}

impl fmt::Display for BarrierError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BarrierError::Unavailable => f.write_str("no process-wide memory barrier is available on this platform"),
            BarrierError::Os(code) => write!(f, "process-wide memory barrier failed with OS error {code}"),
        }
    }
}

impl std::error::Error for BarrierError {}

static BACKEND: LazyLock<Backend> = LazyLock::new(platform::detect);

/// The mechanism in use, detected on first call.
#[inline]
pub fn backend() -> Backend {
    *BACKEND
}

/// Whether [`heavy`] can succeed here, and so whether a protocol may rely on the light/heavy pair.
#[inline]
pub fn is_available() -> bool {
    backend() != Backend::Unavailable
}

/// The light side: a compiler fence and nothing else.
///
/// It keeps the compiler from moving the caller's surrounding memory operations across this point; the hardware
/// ordering comes from the other party's [`heavy`] barrier.  An owner brackets every access to an unshared cell with
/// one of these on each side of its `inside` stores.
#[inline(always)]
pub fn light() {
    compiler_fence(Ordering::SeqCst);
}

/// The heavy side: every thread of the process executes a full fence before this returns.
///
/// Fails with [`BarrierError::Unavailable`] where no backend exists, which [`is_available`] reports in advance, and
/// with [`BarrierError::Os`] if the system call is refused — a container's seccomp filter can do that after the
/// detection succeeded.  Either way nothing has been synchronized, and the caller must not proceed as if it had.
pub fn heavy() -> Result<(), BarrierError> {
    platform::heavy(backend())
}

#[cfg(target_os = "linux")]
mod platform {
    use super::{Backend, BarrierError};
    use std::ffi::{c_int, c_long};
    use std::io;

    /// The `membarrier(2)` commands this module uses.  They are the kernel's ABI values (`uapi/linux/membarrier.h`),
    /// defined here rather than taken from the `libc` crate so that the floor on that crate's version stays where the
    /// rest of the workspace needs it.
    const CMD_QUERY: c_int = 0;
    const CMD_PRIVATE_EXPEDITED: c_int = 1 << 3;
    const CMD_REGISTER_PRIVATE_EXPEDITED: c_int = 1 << 4;

    /// Issue one `membarrier` command.  The kernel takes `(cmd, flags, cpu_id)`; the latter two are zero for every
    /// command used here, and kernels older than the third argument ignore it.
    fn membarrier(cmd: c_int) -> Result<c_long, i32> {
        // SAFETY: a raw system call with scalar arguments; the kernel validates the command and touches no caller
        // memory.
        let ret = unsafe { libc::syscall(libc::SYS_membarrier, cmd, 0 as c_int, 0 as c_int) };

        if ret < 0 { Err(errno()) } else { Ok(ret) }
    }

    fn errno() -> i32 {
        io::Error::last_os_error().raw_os_error().unwrap_or(0)
    }

    /// Whether the private expedited command exists and can be registered for.
    fn membarrier_supported() -> bool {
        let Ok(commands) = membarrier(CMD_QUERY) else {
            return false;
        };
        let needed = c_long::from(CMD_PRIVATE_EXPEDITED | CMD_REGISTER_PRIVATE_EXPEDITED);

        commands & needed == needed && membarrier(CMD_REGISTER_PRIVATE_EXPEDITED).is_ok()
    }

    pub(super) fn detect() -> Backend {
        if membarrier_supported() {
            Backend::Membarrier
        } else if mprotect::supported() {
            Backend::Mprotect
        } else {
            Backend::Unavailable
        }
    }

    pub(super) fn heavy(backend: Backend) -> Result<(), BarrierError> {
        match backend {
            Backend::Membarrier => match membarrier(CMD_PRIVATE_EXPEDITED) {
                Ok(_) => Ok(()),

                // `EPERM` means this address space is not registered.  Registration happened at detection, so the only
                // way to be here is a `fork`: the child's address space is a copy, and whether the registration copies
                // with it is the kernel's business.  Register again and retry once; a second refusal is real.
                Err(libc::EPERM) => {
                    membarrier(CMD_REGISTER_PRIVATE_EXPEDITED).map_err(BarrierError::Os)?;
                    membarrier(CMD_PRIVATE_EXPEDITED).map(|_| ()).map_err(BarrierError::Os)
                }
                Err(code) => Err(BarrierError::Os(code)),
            },
            Backend::Mprotect => mprotect::barrier(),
            Backend::FlushProcessWriteBuffers | Backend::Unavailable => Err(BarrierError::Unavailable),
        }
    }

    /// The TLB-shootdown fallback.
    ///
    /// One anonymous page, locked in memory so that it stays mapped, and a lock so that one barrier runs at a time.  A
    /// barrier makes the page writable, dirties it with a locked increment so that a present, dirty translation exists
    /// on this core, and then revokes all access: the revocation invalidates that translation on every core that may
    /// hold it, and on x86 Linux that is an inter-processor interrupt to each such core, which is the fence.  A core
    /// that never touched the page is not in the page's set and does not need the interrupt, because no thread of ours
    /// has run on it since its last switch, and a switch drains the buffers.
    pub(crate) mod mprotect {
        use super::BarrierError;
        use std::ffi::c_void;
        use std::ptr;
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::{LazyLock, Mutex};

        struct Page {
            base: *mut c_void,
            len: usize,
            lock: Mutex<()>,
        }

        // SAFETY: the page is private to this process, every access to it happens under `lock`, and the raw pointer is
        // never handed out.
        unsafe impl Send for Page {}
        unsafe impl Sync for Page {}

        /// The trick is enabled only where a protection downgrade is known to interrupt every core holding the
        /// translation.  That is the documented behavior of the x86 TLB-shootdown path; other architectures may
        /// invalidate remote TLBs by broadcast instructions that fence nothing.
        pub(crate) fn supported() -> bool {
            cfg!(any(target_arch = "x86", target_arch = "x86_64")) && PAGE.is_some()
        }

        static PAGE: LazyLock<Option<Page>> = LazyLock::new(map_page);

        fn map_page() -> Option<Page> {
            // SAFETY: `sysconf` reads a constant.
            let len = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
            let len = usize::try_from(len).ok().filter(|len| *len > 0)?;

            // The page is mapped writable first and only then made inaccessible, because the lock below must come in
            // between: `mlock` populates the pages it locks, and it cannot populate a `PROT_NONE` mapping, so locking
            // one fails with `ENOMEM`.  The locked state belongs to the mapping and survives the protection change.
            //
            // SAFETY: an anonymous private mapping with no file and no caller memory involved.
            let base = unsafe { libc::mmap(ptr::null_mut(), len, libc::PROT_READ | libc::PROT_WRITE, libc::MAP_PRIVATE | libc::MAP_ANONYMOUS, -1, 0) };
            if base == libc::MAP_FAILED {
                return None;
            }

            // The page must stay resident: a barrier against a page that was paged out would find no translation to
            // invalidate and interrupt nobody.  One page is within any default `RLIMIT_MEMLOCK`; if the lock is refused
            // anyway, the trick is not safe to rely on and the mapping goes back.
            //
            // SAFETY: `base` and `len` describe the mapping made above.
            let locked = unsafe { libc::mlock(base, len) } == 0;

            // SAFETY: as above; a failed protection change leaves the mapping valid and merely writable, which the
            // first barrier would set again anyway, but a page that cannot be made inaccessible cannot carry the trick
            // either.
            let hidden = locked && unsafe { libc::mprotect(base, len, libc::PROT_NONE) } == 0;
            if !hidden {
                // SAFETY: unmapping the mapping made above, which nothing else references.
                unsafe { libc::munmap(base, len) };

                return None;
            }

            Some(Page { base, len, lock: Mutex::new(()) })
        }

        pub(crate) fn barrier() -> Result<(), BarrierError> {
            let Some(page) = PAGE.as_ref() else {
                return Err(BarrierError::Unavailable);
            };

            // A poisoned lock means a previous barrier panicked between its two protection changes, which leaves the
            // page in a state the next barrier corrects on its own; the guard is still usable.
            let _guard = page.lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());

            // SAFETY: `base` and `len` are the mapping's; changing its protection touches no other memory.
            if unsafe { libc::mprotect(page.base, page.len, libc::PROT_READ | libc::PROT_WRITE) } != 0 {
                return Err(BarrierError::Os(super::errno()));
            }

            // Dirty the page under the lock so that a present, dirty translation exists before it is revoked; a clean
            // or absent translation would let the kernel skip the shootdown.
            //
            // SAFETY: the page is mapped, writable, page-aligned, and private to this process; the atomic is in-bounds
            // and aligned.
            unsafe { (*page.base.cast::<AtomicUsize>()).fetch_add(1, Ordering::SeqCst) };

            // SAFETY: as above.
            if unsafe { libc::mprotect(page.base, page.len, libc::PROT_NONE) } != 0 {
                return Err(BarrierError::Os(super::errno()));
            }

            Ok(())
        }
    }
}

#[cfg(target_os = "windows")]
mod platform {
    use super::{Backend, BarrierError};

    pub(super) fn detect() -> Backend {
        Backend::FlushProcessWriteBuffers
    }

    pub(super) fn heavy(backend: Backend) -> Result<(), BarrierError> {
        match backend {
            Backend::FlushProcessWriteBuffers => {
                // SAFETY: takes no arguments and touches no caller memory.
                unsafe { windows_sys::Win32::System::Threading::FlushProcessWriteBuffers() };

                Ok(())
            }
            Backend::Membarrier | Backend::Mprotect | Backend::Unavailable => Err(BarrierError::Unavailable),
        }
    }
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
mod platform {
    use super::{Backend, BarrierError};

    pub(super) fn detect() -> Backend {
        Backend::Unavailable
    }

    pub(super) fn heavy(_backend: Backend) -> Result<(), BarrierError> {
        Err(BarrierError::Unavailable)
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
#[path = "tests/barrier_tests.rs"]
mod tests;
