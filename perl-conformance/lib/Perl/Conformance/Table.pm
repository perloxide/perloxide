package Perl::Conformance::Table;

# A factored result table: the record of an enumeration that is a Cartesian product of axes, stored without the
# product.  Every distinct result is written once, with the set of axis values it holds for, and the full product for
# one version is expanded on demand.
#
# A row of the product has a name whose dot-separated parts are its axis values (the string-flags model's
# `B.none.U.uc`: family, context, taint, op).  One axis is declared *folded*: rows that differ only in that axis and have
# the same record are stored as one line whose name carries the set of values in braces (`B.{none,feature}.U.uc`), or
# `*` when the set is every value the axis takes.  Versions are folded the same way in a column of their own, so one
# file holds every version the model has been run on, and the lines a new version adds are exactly the results it
# changed.
#
# File format (tab-separated, `#` comments, no line ends in whitespace):
#
#   versions<TAB>name<TAB>field...
#
# where `versions` is a comma-separated set or `*` (every version listed in the header), `name` is the folded row name,
# and the fields are the record.  The header comments declare the axes, the folded axis, the versions, and the field
# names:
#
#   # axes: family context taint op
#   # folded: context
#   # folded-values: none feature bytes locale_utf8 locale_latin1 locale_posix locale_c
#   # versions: 5.38.2 5.44.0
#   # fields: bytes flag length ords tainted notes
#
# Operations: `load` reads a file; `merge` replaces one version's rows (the full product for that version) and
# refolds; `write` writes the file; `expand` lists the product for one version; `lookup` resolves a product row name
# at a version; `diff` lists the rows whose records differ between two versions.

use strict;
use warnings;

sub new {
    my ($class, %arg) = @_;
    my $self = bless {
        axes     => $arg{axes}     || [],
        folded   => $arg{folded},
        fields   => $arg{fields}   || [],
        versions => [],
        values   => {},               # axis name -> { value => 1 }, the values seen on each axis
        cells    => {},               # version -> product row name -> record (tab-joined fields)
    }, $class;
    return $self;
}

# Reads a factored table.  Returns the table, or dies.
sub load {
    my ($class, $path) = @_;
    open my $fh, '<', $path or die "cannot read $path: $!\n";
    my $self = $class->new;
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    for my $line (@lines) {
        next unless length $line;
        if ($line =~ /^#\s*([\w-]+):\s*(.*?)\s*\z/) {
            my ($k, $v) = ($1, $2);
            my @v = split ' ', $v;
            if    ($k eq 'axes')     { $self->{axes} = \@v }
            elsif ($k eq 'folded')   { $self->{folded} = $v[0] }
            elsif ($k eq 'folded-values') { $self->{values}{ $self->{folded} }{$_} = 1 for @v }
            elsif ($k eq 'versions') { $self->{versions} = \@v }
            elsif ($k eq 'fields')   { $self->{fields} = \@v }
            next;
        }
        next if $line =~ /^#/;
        my ($versions, $name, @fields) = split /\t/, $line, -1;
        my @vers = $versions eq '*' ? @{ $self->{versions} } : split /,/, $versions;
        my $record = join("\t", @fields);
        for my $row ($self->unfold($name)) {
            $self->{cells}{$_}{$row} = $record for @vers;
            $self->note_values($row);
        }
    }
    return $self;
}

# The index of the folded axis among the axes.
sub folded_index {
    my ($self) = @_;
    my @axes = @{ $self->{axes} };
    for my $i (0 .. $#axes) { return $i if $axes[$i] eq $self->{folded} }
    die "folded axis $self->{folded} is not one of the axes @axes\n";
}

# The product row names a folded name stands for.
sub unfold {
    my ($self, $name) = @_;
    my @parts = split /\./, $name;
    my $i = $self->folded_index;
    my $set = $parts[$i];
    my @vals = $set eq '*' ? sort keys %{ $self->{values}{ $self->{folded} } }
             : $set =~ /^\{(.*)\}\z/ ? split(/,/, $1)
             : ($set);
    return map { my @p = @parts; $p[$i] = $_; join('.', @p) } @vals;
}

sub note_values {
    my ($self, $row) = @_;
    my @parts = split /\./, $row;
    my @axes = @{ $self->{axes} };
    $self->{values}{ $axes[$_] }{ $parts[$_] } = 1 for 0 .. $#axes;
}

# merge(VERSION, { product row name => record }): replaces VERSION's rows with the given product.
sub merge {
    my ($self, $version, $rows) = @_;
    $self->{cells}{$version} = { %$rows };
    $self->note_values($_) for keys %$rows;
    $self->{versions} = [ sort { version_cmp($a, $b) } keys %{ $self->{cells} } ];
    return $self;
}

sub version_cmp {
    my ($a, $b) = @_;
    my @a = split /\./, $a;
    my @b = split /\./, $b;
    for my $i (0 .. ($#a > $#b ? $#a : $#b)) {
        my $c = ($a[$i] // 0) <=> ($b[$i] // 0);
        return $c if $c;
    }
    return 0;
}

# Every product row name across every version, in axis order.
sub rows {
    my ($self) = @_;
    my %seen;
    $seen{$_} = 1 for map { keys %{ $self->{cells}{$_} } } @{ $self->{versions} };
    return sort keys %seen;
}

# The folded lines: for each group of rows that differ only in the folded axis, and each distinct (record, version
# set) among them, one line.  Returns a list of [versions, name, record].
sub lines {
    my ($self) = @_;
    my $i = $self->folded_index;
    my $all_folded = join(',', sort keys %{ $self->{values}{ $self->{folded} } });
    my $all_versions = join(',', @{ $self->{versions} });
    my %group;
    for my $row ($self->rows) {
        my @parts = split /\./, $row;
        my $fv = splice @parts, $i, 1;
        my $key = join('.', @parts);
        for my $v (@{ $self->{versions} }) {
            my $rec = $self->{cells}{$v}{$row};
            next unless defined $rec;
            push @{ $group{$key}{$rec}{$fv} }, $v;
        }
    }
    my @out;
    for my $key (sort keys %group) {
        for my $rec (sort keys %{ $group{$key} }) {
            # Within one record, the folded values that hold for the same version set share a line.
            my %by_versions;
            for my $fv (keys %{ $group{$key}{$rec} }) {
                my $vs = join(',', sort { version_cmp($a, $b) } @{ $group{$key}{$rec}{$fv} });
                push @{ $by_versions{$vs} }, $fv;
            }
            for my $vs (sort keys %by_versions) {
                my @fv = sort @{ $by_versions{$vs} };
                my $set = join(',', @fv) eq $all_folded ? '*' : @fv == 1 ? $fv[0] : '{' . join(',', @fv) . '}';
                my @parts = split /\./, $key;
                splice @parts, $i, 0, $set;
                push @out, [ $vs eq $all_versions ? '*' : $vs, join('.', @parts), $rec ];
            }
        }
    }
    return sort { $a->[1] cmp $b->[1] || $a->[0] cmp $b->[0] } @out;
}

sub write {
    my ($self, $path) = @_;
    open my $fh, '>', $path or die "cannot write $path: $!\n";
    print $fh "# axes: @{ $self->{axes} }\n";
    print $fh "# folded: $self->{folded}\n";
    print $fh "# folded-values: ", join(" ", sort keys %{ $self->{values}{ $self->{folded} } }), "\n";
    print $fh "# versions: @{ $self->{versions} }\n";
    print $fh "# fields: @{ $self->{fields} }\n";
    print $fh join("\t", @$_), "\n" for $self->lines;
    close $fh or die "cannot close $path: $!\n";
    return $self;
}

# The product for one version: a list of [row name, record].
sub expand {
    my ($self, $version) = @_;
    my $cells = $self->{cells}{$version} or die "no version $version in the table (it holds @{ $self->{versions} })\n";
    return map { [ $_, $cells->{$_} ] } sort keys %$cells;
}

# The record of one product row at a version, or undef.
sub lookup {
    my ($self, $row, $version) = @_;
    return $self->{cells}{$version}{$row};
}

# The rows whose records differ between two versions (a row absent at one of them counts as differing): a list of
# [row name, record at A, record at B].
sub diff {
    my ($self, $va, $vb) = @_;
    for ($va, $vb) { die "no version $_ in the table\n" unless $self->{cells}{$_} }
    my @out;
    for my $row ($self->rows) {
        my ($a, $b) = ($self->{cells}{$va}{$row}, $self->{cells}{$vb}{$row});
        next if defined $a && defined $b && $a eq $b;
        push @out, [ $row, $a // '(absent)', $b // '(absent)' ];
    }
    return @out;
}

1;
