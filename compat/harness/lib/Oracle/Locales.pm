package Oracle::Locales;

# Compiles the harness's own locales so that no probe depends on which locales a system has
# generated. The sources live in the harness's locales/ directory, one file per locale, each a
# complete locale definition built from the system's own i18n sources (so they always match the
# localedef that compiles them). They are compiled into a build directory that every child
# process receives as LOCPATH; a probe then names the locale as "<name>.UTF-8".
#
# Two are provided:
#   radix_comma   LC_NUMERIC with a comma decimal point, every other category POSIX; for the
#                 numeric-radix probes, which only need a radix that is not ".".
#   ctype_utf8    LC_CTYPE from the glibc i18n classification, every other category POSIX; for the
#                 character-class and case-mapping probes, in place of C.UTF-8, which not every
#                 glibc provides.
#
# compile() returns the LOCPATH directory, or undef (with a reason in $Oracle::Locales::WHY) when
# localedef or the i18n sources are missing; the caller then skips the probes that require a
# compiled locale and says so. Nothing else about a run changes.

use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;

our $WHY = '';

sub source_dir { File::Spec->catdir(dirname(__FILE__), '..', '..', 'locales') }

sub names {
    my $dir = source_dir();
    opendir my $dh, $dir or return ();
    my @names = sort grep { -f "$dir/$_" && !/^\./ } readdir $dh;
    closedir $dh;
    return @names;
}

# The compiled form is keyed by the sources' contents and the compiling localedef's version, so a
# changed source or a changed glibc recompiles and an unchanged one is reused.
sub stamp {
    my $dir = source_dir();
    my $text = `localedef --version 2>/dev/null` // '';
    for my $n (names()) {
        open my $fh, '<', "$dir/$n" or next;
        local $/;
        $text .= "\0$n\0" . <$fh>;
    }
    return unpack('%32C*', $text);
}

sub compile {
    my ($build_dir) = @_;
    $WHY = '';
    my @names = names();
    if (!@names) { $WHY = 'no locale sources under ' . source_dir(); return }
    my $localedef = `which localedef 2>/dev/null`;
    chomp $localedef;
    if (!$localedef) { $WHY = 'localedef not found'; return }
    my $charmap = (grep { -e } '/usr/share/i18n/charmaps/UTF-8.gz', '/usr/share/i18n/charmaps/UTF-8')[0];
    if (!$charmap) { $WHY = 'glibc i18n sources not installed (no /usr/share/i18n/charmaps/UTF-8)'; return }
    make_path($build_dir);
    my $stamp = stamp();
    my $stamp_file = "$build_dir/.stamp";
    my $have = '';
    if (open my $fh, '<', $stamp_file) { local $/; $have = <$fh> // ''; chomp $have }
    my $complete = $have eq $stamp && !grep { !-d "$build_dir/$_.UTF-8" } @names;
    return $build_dir if $complete;
    for my $n (@names) {
        my $src = File::Spec->catfile(source_dir(), $n);
        my $out = "$build_dir/$n.UTF-8";
        # localedef warns about categories the POSIX source does not define; the locale compiles
        # and loads regardless, so only a nonzero exit is a failure.
        my $log = `localedef -i "$src" -f UTF-8 "$out" 2>&1`;
        if ($? >> 8 > 1) { $WHY = "localedef failed on $n: $log"; return }
    }
    if (open my $fh, '>', $stamp_file) { print $fh "$stamp\n" }
    return $build_dir;
}

# True when NAME (as a probe's "oracle-requires: locale NAME" names it) is one of the compiled
# locales.
sub provides {
    my ($name) = @_;
    (my $want = lc $name) =~ s/\.utf-?8\z//;
    return scalar grep { lc($_) eq $want } names();
}

1;
