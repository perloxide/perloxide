package Oracle::Run;

# Runs one Perl program under a pinned environment, capturing stdout, stderr, the probe channel on
# file descriptor 3, and a textual exit record ("exit N", "signal N", or "timeout").

use strict;
use warnings;
use Fcntl qw(F_SETFD);
use File::Basename qw(dirname basename);
use POSIX ();

# Environment variables every run starts from. Nothing else is inherited, so PERL5LIB, PERL5OPT,
# PERL_UNICODE, locale variables, and hash-seed settings from the caller cannot leak in.
sub base_env {
    return (
        PATH   => '/usr/local/bin:/usr/bin:/bin',
        HOME   => '/tmp',
        LC_ALL => 'C',
        TZ     => 'UTC',
    );
}

# Hash-seed settings for each mode. A seedN mode pins PERL_HASH_SEED to N; with the seed set, perl
# perturbs keys deterministically from it (PERL_PERTURB_KEYS defaults to DETERMINISTIC), so every
# seedN run reproduces one hash order exactly. "random" leaves PERL_HASH_SEED unset, which is perl's
# default: a fresh seed, and a fresh order, each run.
sub mode_env {
    my ($mode) = @_;
    return (PERL_HASH_SEED => $1) if $mode =~ /^seed(\d+)\z/;
    return ()                     if $mode eq 'random';
    die "unknown hash mode '$mode'\n";
}

# run(perl => PATH, file => PATH, prefix => PATH, mode => NAME, extra_env => {...},
#     probe_lib => DIR or undef, timeout => SECONDS)
# Writes PREFIX.stdout, PREFIX.stderr, PREFIX.fd3, PREFIX.exit and returns the exit record.
sub run {
    my (%arg) = @_;
    my $prefix = $arg{prefix};
    my $pid = fork;
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) {
        # Output files are opened before changing directory, so a relative prefix still resolves
        # against the caller's working directory.
        open STDIN,  '<', '/dev/null'      or POSIX::_exit(126);
        open STDOUT, '>', "$prefix.stdout" or POSIX::_exit(126);
        open STDERR, '>', "$prefix.stderr" or POSIX::_exit(126);
        open my $probe, '>', "$prefix.fd3" or POSIX::_exit(126);

        # The probe channel must be descriptor 3 and must survive exec; perl marks descriptors above
        # $^F close-on-exec, so either duplicate onto 3 or clear the flag if open already chose 3.
        if (fileno($probe) == 3) {
            fcntl($probe, F_SETFD, 0) or POSIX::_exit(126);
        }
        else {
            defined POSIX::dup2(fileno($probe), 3) or POSIX::_exit(126);
        }
        chdir dirname($arg{file}) or POSIX::_exit(126);
        %ENV = (base_env(), mode_env($arg{mode}), %{ $arg{extra_env} || {} });
        my @cmd = ($arg{perl});
        push @cmd, "-I$arg{probe_lib}", '-MProbe' if $arg{probe_lib};
        push @cmd, basename($arg{file});
        { exec { $cmd[0] } @cmd }
        POSIX::_exit(127);
    }
    my $deadline = time + ($arg{timeout} // 60);
    my $record;
    while (1) {
        my $done = waitpid($pid, POSIX::WNOHANG());
        if ($done == $pid) {
            my $status = $?;
            $record = ($status & 127) ? 'signal ' . ($status & 127) : 'exit ' . ($status >> 8);
            last;
        }
        if (time >= $deadline) {
            kill 'KILL', $pid;
            waitpid($pid, 0);
            $record = 'timeout';
            last;
        }
        select(undef, undef, undef, 0.02);
    }
    open my $fh, '>', "$prefix.exit" or die "cannot write $prefix.exit: $!\n";
    print {$fh} "$record\n";
    close $fh;
    return $record;
}

1;
