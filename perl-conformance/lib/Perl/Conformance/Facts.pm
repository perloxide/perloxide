package Perl::Conformance::Facts;

# The fact index (facts.md) as data: every entry under every area heading, keyed by its id, with the versions it is
# demonstrated on and the evidence it cites.
#
# An entry is a bullet of the form
#
#   - `area.slug`: text, possibly continued on lines indented two spaces, ending in the version bracket. [5.44.0]
#
# The id is lowercase letters, digits and hyphens on each side of one dot; the part before the dot is the area's
# prefix, which the area heading declares in brackets (`## Arrays [arrays]`) and every entry under it shares.  Entries are cited elsewhere as `[fact:area.slug]`; that spelling has
# no space so that a citation is one word, which no paragraph rewrap can split.
#
# Evidence is whatever the entry's backtick spans name: a path under the reference (probes, model reports, suites),
# a suite case by name, a model row pattern, a Perl source function or macro, or a Perl source file with line numbers.
# `evidence` classifies them and resolves the paths; `lint` reports entries that break the form and paths that do not
# exist.

use strict;
use warnings;
use File::Basename qw(basename);

# load(PATH_TO_FACTS_MD) -> object.  The reference root is the directory holding facts.md.
sub load {
    my ($class, $path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot read $path: $!\n";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    (my $root = $path) =~ s{/[^/]*\z}{};
    $root = '.' if $root eq $path;
    my $self = bless { path => $path, root => $root, areas => [], facts => {}, order => [], problems => [] }, $class;
    $self->parse(\@lines);
    return $self;
}

sub parse {
    my ($self, $lines) = @_;
    my $area;
    my $entry;
    my $finish = sub {
        return unless $entry;
        $self->admit($entry);
        $entry = undef;
    };
    for my $i (0 .. $#$lines) {
        my $line = $lines->[$i];
        my $no = $i + 1;
        if ($line =~ /^## (.*?)(?: \[([a-z0-9][a-z0-9-]*)\])?\z/) {
            $finish->();
            $area = { title => $1, line => $no, prefix => $2, facts => [] };
            push @{ $self->{problems} }, "$self->{path}:$no: area `$1` declares no id prefix" unless defined $2;
            push @{ $self->{areas} }, $area;
            next;
        }
        next unless $area;
        if ($line =~ /^- (.*)/) {
            $finish->();
            $entry = { area => $area, line => $no, text => [$1] };
            next;
        }
        if ($entry && $line =~ /^  (\S.*)/) {
            push @{ $entry->{text} }, $1;
            next;
        }
        $finish->();
    }
    $finish->();
}

# One parsed bullet becomes a fact or a problem.
sub admit {
    my ($self, $entry) = @_;
    my $text = join ' ', @{ $entry->{text} };
    my $where = "$self->{path}:$entry->{line}";
    my ($id, $body) = $text =~ /^`([^`]+)`:\s+(.*)\z/s;
    unless (defined $id) {
        push @{ $self->{problems} }, "$where: entry has no id";
        return;
    }
    unless ($id =~ /^([a-z0-9][a-z0-9-]*)\.([a-z0-9][a-z0-9-]*)\z/) {
        push @{ $self->{problems} }, "$where: malformed id `$id`";
        return;
    }
    my $prefix = $1;
    my $area = $entry->{area};
    push @{ $self->{problems} }, "$where: id `$id` is not under the area's prefix `$area->{prefix}`" if defined $area->{prefix} && $prefix ne $area->{prefix};
    if ($self->{facts}{$id}) {
        push @{ $self->{problems} }, "$where: duplicate id `$id` (first at line $self->{facts}{$id}{line})";
        return;
    }
    my ($versions) = $body =~ /\s\[([^\[\]]+)\]\z/;
    push @{ $self->{problems} }, "$where: `$id` has no version bracket" unless defined $versions;
    $body =~ s/\s\[[^\[\]]+\]\z// if defined $versions;
    my $fact = { id => $id, area => $area, line => $entry->{line}, text => $body, versions => $versions // '' };
    $self->{facts}{$id} = $fact;
    push @{ $self->{order} }, $id;
    push @{ $area->{facts} }, $fact;
}

sub fact {
    my ($self, $id) = @_;
    return $self->{facts}{$id};
}

sub ids {
    my ($self) = @_;
    return @{ $self->{order} };
}

sub areas {
    my ($self) = @_;
    return @{ $self->{areas} };
}

# The area whose prefix is PREFIX, or undef.
sub area {
    my ($self, $prefix) = @_;
    my ($area) = grep { defined $_->{prefix} && $_->{prefix} eq $prefix } @{ $self->{areas} };
    return $area;
}

# The facts whose id or text matches the regex, in index order.
sub search {
    my ($self, $re) = @_;
    return grep { $_->{id} =~ $re || $_->{text} =~ $re } map { $self->fact($_) } $self->ids;
}

# A fact's first sentence: the text up to the first sentence end followed by the two spaces that separate sentences.
sub summary {
    my ($class, $fact) = @_;
    my ($first) = $fact->{text} =~ /^(.*?[.!?])(?:  |\z)/s;
    return $first // $fact->{text};
}

# The backtick spans of a fact, classified.  Returns a list of { kind, name, path?, exists? }:
#   path    a file or directory under the reference, or a glob pattern there; `path` is relative to the root
#   case    a suite case named by its basename (`R01_literal_list_members`), resolved to `suites/*/cases/NAME.pl`
#   doc     a document of the reference named by its file name (`undefined.md`), resolved at the root
#   rows    a model row pattern (`plain/aeP/*/unshift1`, `undef.K`, `tiedweak.order`, `assign.*`, `*.hash.*`,
#           `seedX_perturb2.mask.*`), never a file name
#   source  a Perl source function, macro, type tag or file:line reference
# Spans that are Perl code, flag names in prose, or anything else are not evidence and are left out.
sub evidence {
    my ($self, $fact) = @_;
    my @spans = $fact->{text} =~ /`([^`]+)`/g;
    my @out;
    my %seen;
    for my $span (@spans) {
        next if $seen{$span}++;
        if ($span =~ m{^(?:probes|models|suites|harness|measurements|perls)/}) {
            my @hits = glob "$self->{root}/$span";
            @hits = grep { -e } @hits;
            push @out, { kind => 'path', name => $span, path => $span, exists => (@hits ? 1 : 0), matches => scalar @hits };
        }
        elsif ($span =~ /^[A-Z]\d{2}_\w+\z/) {
            my @hits = grep { -f } glob "$self->{root}/suites/*/cases/$span.pl";
            my $rel = @hits ? substr($hits[0], length($self->{root}) + 1) : undef;
            push @out, { kind => 'case', name => $span, path => $rel, exists => (@hits ? 1 : 0) };
        }
        elsif ($span =~ /^\w+\.(?:c|h|xs|y|pm)(?: \d+(?:-\d+)?)?\z/ || $span =~ m{^(?:dist|ext|lib|cpan)/[\w./-]+\z}) {
            push @out, { kind => 'source', name => $span };
        }
        elsif ($span =~ /^[\w-]+\.(?:md|txt|tsv)\z/) {
            push @out, { kind => 'doc', name => $span, path => $span, exists => (-e "$self->{root}/$span" ? 1 : 0) };
        }
        elsif ($span =~ m{^(?:plain|tied|shared)/}
               || ($span =~ /^(?:[A-Za-z]\w*|\*)(?:\.[\w*]+)+\z/ && $span !~ /\.(?:txt|tsv|md|gz)\z/)) {
            push @out, { kind => 'rows', name => $span };
        }
        elsif ($span =~ /^(?:Perl_|S_|PP_?|pp_|sv_|av_|hv_|mg_|magic_|new[A-Z]|save_|SAVE[A-Zt]|PERL_MAGIC_|MGf_|Sv[A-Z]|Av[A-Z]|Hv[A-Z]|PL_|sharedsv_|curse)\w*\z/) {
            push @out, { kind => 'source', name => $span };
        }
    }
    return @out;
}

# Structural problems found at load time plus every cited path or case that does not exist.
sub lint {
    my ($self) = @_;
    my @problems = @{ $self->{problems} };
    for my $id ($self->ids) {
        my $fact = $self->fact($id);
        for my $e ($self->evidence($fact)) {
            next unless exists $e->{exists};
            push @problems, "$self->{path}:$fact->{line}: `$id` cites $e->{kind} `$e->{name}`, which does not exist" unless $e->{exists};
        }
    }
    return @problems;
}

# The `[fact:ID]` citations in a text, as (id, line number) pairs in order of appearance.  A citation inside a code span
# is an example of the form, not a citation, and is skipped.
sub citations {
    my ($class, $text) = @_;
    my @out;
    my $no = 0;
    for my $line (split /\n/, $text, -1) {
        $no++;
        $line =~ s/`[^`]*`//g;
        push @out, [ $1, $no ] while $line =~ /\[fact:([^\]\s]+)\]/g;
    }
    return @out;
}

1;
