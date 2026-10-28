package Perl::Conformance::Table;

# A factored result table: the record of an enumeration that is a Cartesian product of axes, stored without the
# product.  Every distinct result is written once, with the set of axis values it holds for and the set of versions it
# was observed on, and the full product for one version is expanded on demand.
#
# A row of the product is one value per axis (the string-flags model's family, context, taint and op: `B`, `none`,
# `U`, `uc`).  One axis is declared *folded*: rows that differ only in that axis and have the same record are stored as
# one line whose folded column carries the set of values in braces (`{none,feature}`), or `*` when the set is every
# value the axis takes.  Versions are folded the same way in a column of their own, so one file holds every version the
# model has been run on, and the lines a new version adds are exactly the results it changed.
#
# A version is a Perl the enumeration was run on, named as its perlbrew build is: `5.44.0` is the stock build of
# 5.44.0, `5.44.0-threads` its -Dusethreads build, `5.44.0-noreuse` the allocator-instrumented one; builds sort after
# the stock build of their version.  A version listed in the header has been merged in full, so a row that is absent at
# a version is one that enumeration did not produce there (a test that needs ithreads has no row on an unthreaded
# build).  A version set is written as a comma-separated list in which `5.44.0-*` stands for every build of 5.44.0 in
# the header, stock included, and `*` alone for every version in the header -- never for every conceivable build.
#
# File format (UTF-8, tab-separated, `#` comments, no line ends in whitespace): one column per axis, so an axis value
# may hold any character but a tab or a newline -- except the folded axis's values, which may not hold `,`, `{` or `}`:
#
#   versions<TAB>axis-1<TAB>...<TAB>axis-n<TAB>field...
#
# where `versions` is a version set, the axis columns name the row (the folded column a set), and the fields are the
# record.  The header comments declare the axes, the folded axis and its values, the versions, the field names, and the
# separator that joins a row's values into one name where a name is wanted (a citation, a command line); the separator
# defaults to `.` and must not occur in any axis value:
#
#   # axes: family context taint op
#   # folded: context
#   # folded-values: none feature bytes locale_utf8 locale_latin1 locale_posix locale_c
#   # versions: 5.38.2 5.44.0 5.44.0-threads
#   # fields: bytes flag length ords tainted notes
#   # separator: .
#
# A table may declare `# layout: nested` instead: each row group's non-folded axis values are written once, on a line of
# their own, and every (versions, folded set, record) of that group follows on a line that begins with a tab:
#
#   axis-1<TAB>...<TAB>axis-n (the folded axis left out)
#   <TAB>versions<TAB>folded-set<TAB>field...
#
# which saves repeating long axis values -- a model state, say -- on every line of the group.  A nested table needs at
# least two axes, and its first axis value is never empty.
#
# Operations: `load` reads a file; `merge` replaces one version's rows (the full product for that version) and
# refolds; `write` writes the file; `expand` lists the product for one version; `lookup` resolves a product row at a
# version; `diff` lists the rows whose records differ between two versions.  A row is passed as an array of axis
# values or as one name joined by the separator; the records are tab-joined fields.

use strict;
use warnings;

sub new {
    my ($class, %arg) = @_;
    my $self = bless {
        axes      => $arg{axes}      || [],
        folded    => $arg{folded},
        fields    => $arg{fields}    || [],
        separator => $arg{separator} // '.',
        layout    => $arg{layout}    // 'flat',
        versions  => [],
        values    => {},              # axis name -> { value => 1 }, the values seen on each axis
        cells     => {},              # version -> row key (tab-joined axis values) -> record (tab-joined fields)
    }, $class;
    $self->{values}{ $self->{folded} }{$_} = 1 for @{ $arg{folded_values} || [] };
    return $self;
}

# Reads a factored table.  Returns the table, or dies.
sub load {
    my ($class, $path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot read $path: $!\n";
    my $self = $class->new;
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    my @key;    # the current row group's non-folded axis values, in a nested table
    for my $line (@lines) {
        next unless length $line;
        if ($line =~ /^#\s*([\w-]+):\s*(.*?)\s*\z/) {
            my ($k, $v) = ($1, $2);
            my @v = split ' ', $v;
            if    ($k eq 'axes')          { $self->{axes} = \@v }
            elsif ($k eq 'folded')        { $self->{folded} = $v[0] }
            elsif ($k eq 'folded-values') { $self->{values}{ $self->{folded} }{$_} = 1 for @v }
            elsif ($k eq 'versions')      { $self->{versions} = \@v }
            elsif ($k eq 'fields')        { $self->{fields} = \@v }
            elsif ($k eq 'separator')     { $self->{separator} = $v }
            elsif ($k eq 'layout')        { $self->{layout} = $v[0] }
            next;
        }
        next if $line =~ /^#/;
        my $n = @{ $self->{axes} };
        my ($versions, @cols, @parts);
        if ($self->{layout} eq 'nested') {
            if ($line !~ /^\t/) { @key = split /\t/, $line, -1; next }
            die "$path: a group line before any key line: $line\n" unless @key;
            (undef, $versions, my $set, @cols) = split /\t/, $line, -1;
            @parts = @key;
            splice @parts, $self->folded_index, 0, $set;
            die "$path: a key line with other than @{[ $n - 1 ]} values\n" unless @parts == $n;
        }
        else {
            ($versions, @cols) = split /\t/, $line, -1;
            die "$path: a line with fewer columns than the $n axes: $line\n" if @cols < $n;
            @parts = splice @cols, 0, $n;
        }
        my @vers = $self->unfold_versions($versions);
        my $record = join("\t", @cols);
        for my $row ($self->unfold(\@parts)) {
            my $key = join("\t", @$row);
            $self->{cells}{$_}{$key} = $record for @vers;
            $self->note_values($row);
        }
    }
    return $self;
}

# The versions a version set stands for: `*` is every version in the header, and `P-*` every header version that is
# `P` or begins `P-` (`5.44.0-*` is every build of 5.44.0, `5.44.0-threads-*` every threaded one).
sub unfold_versions {
    my ($self, $set) = @_;
    return @{ $self->{versions} } if $set eq '*';
    my @out;
    for my $item (split /,/, $set) {
        if ($item =~ /^(.*)-\*\z/) {
            my $prefix = $1;
            push @out, grep { $_ eq $prefix || index($_, "$prefix-") == 0 } @{ $self->{versions} };
        } else {
            push @out, $item;
        }
    }
    return @out;
}

# A version set written as compactly as the header allows: `*` for every version, else the shortest prefixes `P-*`
# whose every header version is in the set, shortest first, and the rest listed.
sub fold_versions {
    my ($self, @vers) = @_;
    my %left = map { $_ => 1 } @vers;
    return '*' unless grep { !$left{$_} } @{ $self->{versions} };
    my %prefix;
    for my $v (@{ $self->{versions} }) {
        my @p = split /-/, $v;
        $prefix{ join('-', @p[0 .. $_]) } = 1 for 0 .. $#p;
    }
    my @out;
    for my $p (sort { length $a <=> length $b || version_cmp($a, $b) } keys %prefix) {
        my @covered = grep { $_ eq $p || index($_, "$p-") == 0 } @{ $self->{versions} };
        next if @covered < 2 || grep { !$left{$_} } @covered;
        push @out, "$p-*";
        delete $left{$_} for @covered;
    }
    push @out, grep { $left{$_} } @vers;
    return join(',', sort { version_cmp($a =~ s/-\*\z//r, $b =~ s/-\*\z//r) } @out);
}

# The index of the folded axis among the axes.
sub folded_index {
    my ($self) = @_;
    my @axes = @{ $self->{axes} };
    for my $i (0 .. $#axes) { return $i if $axes[$i] eq $self->{folded} }
    die "folded axis $self->{folded} is not one of the axes @axes\n";
}

# A row as an array of axis values, from an array or from a name joined by the separator.
sub parts {
    my ($self, $row) = @_;
    return [ @$row ] if ref $row;
    my $sep = quotemeta $self->{separator};
    return [ split /$sep/, $row, -1 ];
}

# A row's name: its axis values joined by the separator.
sub name {
    my ($self, $row) = @_;
    return join($self->{separator}, @{ $self->parts($row) });
}

# The product rows a folded row stands for, each as an array of axis values.
sub unfold {
    my ($self, $row) = @_;
    my @parts = @{ $self->parts($row) };
    my $i = $self->folded_index;
    my $set = $parts[$i];
    my @vals = $set eq '*' ? sort keys %{ $self->{values}{ $self->{folded} } }
             : $set =~ /^\{(.*)\}\z/ ? split(/,/, $1)
             : ($set);
    return map { my @p = @parts; $p[$i] = $_; \@p } @vals;
}

sub note_values {
    my ($self, $row) = @_;
    my @parts = @{ $self->parts($row) };
    my @axes = @{ $self->{axes} };
    $self->{values}{ $axes[$_] }{ $parts[$_] } = 1 for 0 .. $#axes;
}

# merge(VERSION, { row key => record }): replaces VERSION's rows with the given product.  A key is the row's axis
# values joined by tabs, or by the separator.
sub merge {
    my ($self, $version, $rows) = @_;
    my %cells;
    for my $k (keys %$rows) {
        my $row = $k =~ /\t/ ? [ split /\t/, $k, -1 ] : $self->parts($k);
        die "row `$k` has @{[ scalar @$row ]} values for @{[ scalar @{ $self->{axes} } ]} axes\n"
            unless @$row == @{ $self->{axes} };
        $cells{ join("\t", @$row) } = $rows->{$k};
        $self->note_values($row);
    }
    $self->{cells}{$version} = \%cells;
    $self->{versions} = [ sort { version_cmp($a, $b) } keys %{ $self->{cells} } ];
    return $self;
}

# Orders versions numerically by their dotted parts, a version's stock build before its named builds, and the named
# builds of one version alphabetically.
sub version_cmp {
    my ($a, $b) = @_;
    my ($va, $ba) = split /-/, $a, 2;
    my ($vb, $bb) = split /-/, $b, 2;
    my @a = split /\./, $va;
    my @b = split /\./, $vb;
    for my $i (0 .. ($#a > $#b ? $#a : $#b)) {
        my $c = ($a[$i] // 0) <=> ($b[$i] // 0);
        return $c if $c;
    }
    return ($ba // '') cmp ($bb // '');
}

# Every product row across every version, as arrays of axis values, in axis order.
sub rows {
    my ($self) = @_;
    my %seen;
    $seen{$_} = 1 for map { keys %{ $self->{cells}{$_} } } @{ $self->{versions} };
    return map { [ split /\t/, $_, -1 ] } sort keys %seen;
}

# The folded lines: for each group of rows that differ only in the folded axis, and each distinct (record, version
# set) among them, one line.  Returns a list of [versions, axis values..., fields...].
sub lines {
    my ($self) = @_;
    my $i = $self->folded_index;
    my $all_folded = join(',', sort keys %{ $self->{values}{ $self->{folded} } });
    my %group;
    for my $row ($self->rows) {
        my $key = join("\t", @$row);
        my @parts = @$row;
        my $fv = splice @parts, $i, 1;
        my $gkey = join("\t", @parts);
        for my $v (@{ $self->{versions} }) {
            my $rec = $self->{cells}{$v}{$key};
            next unless defined $rec;
            push @{ $group{$gkey}{$rec}{$fv} }, $v;
        }
    }
    my @out;
    for my $gkey (sort keys %group) {
        for my $rec (sort keys %{ $group{$gkey} }) {
            # Within one record, the folded values that hold for the same version set share a line.
            my %by_versions;
            for my $fv (keys %{ $group{$gkey}{$rec} }) {
                my $vs = $self->fold_versions(@{ $group{$gkey}{$rec}{$fv} });
                push @{ $by_versions{$vs} }, $fv;
            }
            for my $vs (sort keys %by_versions) {
                my @fv = sort @{ $by_versions{$vs} };
                my $set = join(',', @fv) eq $all_folded ? '*' : @fv == 1 ? $fv[0] : '{' . join(',', @fv) . '}';
                my @parts = split /\t/, $gkey, -1;
                splice @parts, $i, 0, $set;
                push @out, [ $vs, @parts, split(/\t/, $rec, -1) ];
            }
        }
    }
    my $n = @{ $self->{axes} };
    return sort { join("\t", @$a[1 .. $n]) cmp join("\t", @$b[1 .. $n]) || $a->[0] cmp $b->[0] } @out;
}

sub write {
    my ($self, $path) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "cannot write $path: $!\n";
    print $fh "# axes: @{ $self->{axes} }\n";
    print $fh "# folded: $self->{folded}\n";
    print $fh "# folded-values: ", join(" ", sort keys %{ $self->{values}{ $self->{folded} } }), "\n";
    print $fh "# versions: @{ $self->{versions} }\n";
    print $fh "# fields: @{ $self->{fields} }\n";
    print $fh "# separator: $self->{separator}\n" if $self->{separator} ne '.';
    if ($self->{layout} eq 'nested') {
        my $n = @{ $self->{axes} };
        die "a nested table needs at least two axes\n" if $n < 2;
        print $fh "# layout: nested\n";
        my $i = $self->folded_index;
        my (%group, @order);
        for my $l ($self->lines) {
            my ($vs, @rest) = @$l;
            my @axes = splice @rest, 0, $n;
            my ($set) = splice @axes, $i, 1;
            my $gk = join("\t", @axes);
            die "a nested table's first axis value may not be empty\n" unless length $axes[0];
            push @order, $gk unless $group{$gk};
            push @{ $group{$gk} }, [ $vs, $set, @rest ];
        }
        for my $gk (sort @order) {
            print $fh "$gk\n";
            print $fh join("\t", '', @$_), "\n" for @{ $group{$gk} };
        }
    }
    else {
        print $fh join("\t", @$_), "\n" for $self->lines;
    }
    close $fh or die "cannot close $path: $!\n";
    return $self;
}

# The product for one version: a list of [axis values..., fields...].
sub expand {
    my ($self, $version) = @_;
    my $cells = $self->{cells}{$version} or die "no version $version in the table (it holds @{ $self->{versions} })\n";
    return map { [ split(/\t/, $_, -1), split(/\t/, $cells->{$_}, -1) ] } sort keys %$cells;
}

# The product for one version as { row key => record }, row keys tab-joined -- the shape `merge` takes.
sub cells {
    my ($self, $version) = @_;
    my $cells = $self->{cells}{$version} or die "no version $version in the table (it holds @{ $self->{versions} })\n";
    return { %$cells };
}

# The record of one product row at a version, or undef.
sub lookup {
    my ($self, $row, $version) = @_;
    return $self->{cells}{$version}{ join("\t", @{ $self->parts($row) }) };
}

# A field value made safe for a table line: a backslash, newline and tab are written `\\`, `\n` and `\t`, any other
# control character `\xNN`, a trailing space `\x20` (so no line ends in whitespace), the empty string `-` and a lone
# `-` `\x2d`.  `unescape` inverts it.  These are functions, not methods.
sub escape {
    my ($v) = @_;
    return '-' unless length $v;
    $v =~ s/\\/\\\\/g;
    $v =~ s/\n/\\n/g;
    $v =~ s/\t/\\t/g;
    $v =~ s/([\x00-\x1f\x7f])/sprintf('\\x%02x', ord $1)/ge;
    $v =~ s/ \z/\\x20/;
    $v = '\\x2d' if $v eq '-';
    return $v;
}

sub unescape {
    my ($v) = @_;
    return '' if $v eq '-';
    $v =~ s/\\(\\|n|t|x[0-9a-f]{2})/$1 eq '\\' ? '\\' : $1 eq 'n' ? "\n" : $1 eq 't' ? "\t" : chr(hex substr($1, 1))/ge;
    return $v;
}

# The rows whose records differ between two versions (a row absent at one of them counts as differing): a list of
# [row (axis values), record at A, record at B].
sub diff {
    my ($self, $va, $vb) = @_;
    for ($va, $vb) { die "no version $_ in the table\n" unless $self->{cells}{$_} }
    my @out;
    for my $row ($self->rows) {
        my $key = join("\t", @$row);
        my ($a, $b) = ($self->{cells}{$va}{$key}, $self->{cells}{$vb}{$key});
        next if defined $a && defined $b && $a eq $b;
        push @out, [ $row, $a // '(absent)', $b // '(absent)' ];
    }
    return @out;
}

1;
