package Perl::Conformance::PerlBugs;

# The record of bugs in perl (perl-bugs.md) as data: every entry keyed by its id, with the versions it affects.
#
# An entry is a level-two heading followed, before any other text, by its versions line:
#
#   ## `id`: title
#
#   - versions: `5.32.4 - *`
#
# The versions are a comma-separated list of items: a version (`5.44.0`), a range (`5.32.4 - 5.39.7`), a range open at
# either end (`* - 5.39.7`, `5.32.4 - *`), or `*` for every version.  Ranges include their ends.  A build tag
# (`5.44.0-threads`) is affected when its version is.

use strict;
use warnings;

# load(PATH_TO_PERL_BUGS_MD) -> object; dies on an entry that breaks the form.
sub load {
    my ($class, $path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot read $path: $!\n";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    my $self = bless { path => $path, bugs => {}, order => [] }, $class;
    my $bug;
    for my $i (0 .. $#lines) {
        my $line = $lines[$i];
        my $where = "$path:" . ($i + 1);
        if ($line =~ /^## /) {
            die "$where: a bug heading is ## `id`: title\n" unless $line =~ /^## `([a-z0-9][a-z0-9-]*)`: (\S.*)\z/;
            die "$where: duplicate bug id `$1`\n" if $self->{bugs}{$1};
            die "$where: bug `$bug->{id}` has no versions line\n" if $bug && !$bug->{ranges};
            $bug = { id => $1, title => $2, line => $i + 1 };
            $self->{bugs}{$1} = $bug;
            push @{ $self->{order} }, $1;
            next;
        }
        next unless $bug && !$bug->{ranges};
        next if $line =~ /^\s*\z/;
        die "$where: bug `$bug->{id}` must open with its - versions: line\n" unless $line =~ /^- versions: `([^`]+)`\z/;
        $bug->{versions} = $1;
        $bug->{ranges} = eval { [ parse_versions($1) ] } or die "$where: $@";
    }
    die "$path: bug `$bug->{id}` has no versions line\n" if $bug && !$bug->{ranges};
    return $self;
}

sub ids {
    my ($self) = @_;
    return @{ $self->{order} };
}

sub bug {
    my ($self, $id) = @_;
    return $self->{bugs}{$id};
}

# parse_versions(TEXT) -> list of [low, high] ranges; an undef end is open.  Dies on a malformed item.
sub parse_versions {
    my ($text) = @_;
    my $v = qr/\d+\.\d+\.\d+/;
    my @ranges;
    for my $item (split /\s*,\s*/, $text) {
        if ($item eq '*') { push @ranges, [ undef, undef ] }
        elsif ($item =~ /^($v)\z/) { push @ranges, [ $1, $1 ] }
        elsif ($item =~ /^(\*|$v) - (\*|$v)\z/) {
            my ($lo, $hi) = map { $_ eq '*' ? undef : $_ } $1, $2;
            die "the range `$item` is empty\n" if defined $lo && defined $hi && version_cmp($lo, $hi) > 0;
            push @ranges, [ $lo, $hi ];
        }
        else { die "malformed versions item `$item`\n" }
    }
    die "an empty versions list\n" unless @ranges;
    return @ranges;
}

# Numeric comparison of two X.Y.Z versions.
sub version_cmp {
    my ($a, $b) = @_;
    my @a = split /\./, $a;
    my @b = split /\./, $b;
    return $a[0] <=> $b[0] || $a[1] <=> $b[1] || $a[2] <=> $b[2];
}

# affects(ID, VERSION) -> true when the bug's versions include VERSION (a version or a build tag).  Dies on an unknown
# id or a VERSION that is not a version.
sub affects {
    my ($self, $id, $version) = @_;
    my $bug = $self->{bugs}{$id} or die "no bug `$id` in $self->{path}\n";
    my ($v) = $version =~ /^v?(\d+\.\d+\.\d+)(?:-[\w-]+)?\z/ or die "`$version` is not a perl version\n";
    for my $r (@{ $bug->{ranges} }) {
        my ($lo, $hi) = @$r;
        next if defined $lo && version_cmp($v, $lo) < 0;
        next if defined $hi && version_cmp($v, $hi) > 0;
        return 1;
    }
    return 0;
}

1;
