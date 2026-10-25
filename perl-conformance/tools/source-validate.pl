#!/usr/bin/env perl
# source-validate.pl: which Perl versions a model's transcription is valid for, decided from the C source.
#
#   source-validate.pl --repo PERL5_GIT --tags v5.38.2,v5.40.2,v5.42.0,v5.44.0 [--work DIR] MODEL.pm...
#
# A model transcribes one version's C.  For every snake_case routine the model defines, this finds the C definition
# of the function, pp routine or macro of that name (Perl_name, S_name, PP(name), #define name) in each tagged tree
# and compares the definitions after collapsing whitespace.  A routine whose definition is identical across the tags
# is transcribed equally validly for all of them; one that differs names the tag at which it changed and is where a
# version check belongs in the model, after the difference has been read.  A difference is triaged by token bag:
# when the two definitions hold the same multiset of tokens once assertions are dropped, the change is a moved
# declaration or an added assertion ("reordered"), not logic; anything else is "differs" and must be read.  Names
# with no C definition are the model's own labels, arms and helpers, listed as such.
#
# Two files beside the model refine this.  source-names.tsv maps a routine to the C symbols its definition is made
# of when the default rule cannot find it -- a function a macro generates, or a routine that mirrors several macros:
#     routine <TAB> SYMBOL[,SYMBOL...]
# source-equivalences.tsv records differences that have been read and found functionally neutral -- renamed
# locals, a restructured conditional with the same cases -- so that later runs report them as reviewed:
#     routine <TAB> TAG <TAB> reason
# A reviewed difference is reported "neutral" and counted with the identical ones; it is never silently dropped,
# and a routine that changes again at a later tag is reported as differing there.
#
# Each tag's top-level C and header files are exported once with `git archive` from a clone of
# https://github.com/Perl/perl5 (a `--filter=blob:none` clone suffices) into WORK/tree/TAG, and extracted definitions
# are kept as WORK/TAG/NAME.c, so a difference can be read with diff.  Comments are stripped before comparison, so a
# difference is one of code.  embed.h and proto.h are not searched: their macros and prototypes shadow the definitions.
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use File::Basename qw(basename);

my ($repo, $tags, $work) = (undef, undef, 'source-validate');
GetOptions('repo=s' => \$repo, 'tags=s' => \$tags, 'work=s' => \$work) or die "bad options\n";
die "usage: source-validate.pl --repo PERL5_GIT --tags v1,v2,... MODEL.pm...\n" unless $repo && $tags && @ARGV;
my @tags = split /,/, $tags;

# The C and header files of the tree at a tag, top level only, which is where every transcribed routine lives,
# exported once per tag.
my %files_of;
sub files_at {
    my ($tag) = @_;
    return @{ $files_of{$tag} } if $files_of{$tag};
    my $dir = "$work/tree/$tag";
    unless (-d $dir) {
        make_path($dir);
        system("git -C \"$repo\" archive \"$tag\" | tar -x -C \"$dir\" --wildcards --no-anchored '*.c' '*.h' 2>/dev/null") == 0
            or die "cannot export $tag from $repo\n";
    }
    opendir my $dh, $dir or die "cannot read $dir: $!\n";
    my @f = sort grep { /\.(?:c|h)\z/ && -f "$dir/$_" && !/^(?:embed|proto|embedvar)\.h\z/ } readdir $dh;
    closedir $dh;
    die "no C files at $tag in $repo\n" unless @f;
    return @{ $files_of{$tag} = \@f };
}

my %text_of;
sub text_at {
    my ($tag, $file) = @_;
    return $text_of{"$tag $file"} if exists $text_of{"$tag $file"};
    open my $fh, '<', "$work/tree/$tag/$file" or die "cannot read $work/tree/$tag/$file: $!\n";
    local $/;
    return $text_of{"$tag $file"} = <$fh>;
}

# Every definition in a tag's tree, indexed once: NAME -> [file, kind, text].  A function or PP body runs from its
# definition line (Perl_name, S_name or name at the start of a line, a PP(name) or PP_wrapped(name, ...) head, or a
# storage class and type followed by the name) to the next
# line holding only "}"; a macro runs through its backslash continuations.  A function definition wins over a macro
# of the same name, since the macro is then a wrapper or an alias.
my %index_of;
sub index_at {
    my ($tag) = @_;
    return $index_of{$tag} if $index_of{$tag};
    my %index;
    for my $file (files_at($tag)) {
        my $text = text_at($tag, $file);
        # The offsets of every line holding only "}", in order; a definition ends at the first one past its start.
        my @ends;
        push @ends, $+[0] while $text =~ /^\}[ \t]*$/mg;
        my $e = 0;
        # A definition starts a line: the bare name (perl's style puts the return type on the line before), a
        # PP or PP_wrapped head, or storage class and type followed by the name (the inline hash functions).
        while ($text =~ /^(?:PP\((\w+)\)|PP_wrapped\((\w+),|(?:Perl_|S_)?([A-Za-z_]\w*)\s*\(|(?>(?:[A-Za-z_][\w*]*[ \t]+(?![ \t]*\()){1,4})(?:Perl_|S_)?([A-Za-z_]\w*)[ \t]*\()/mg) {
            my $name = $1 // $2 // $3 // $4;
            my $start = $-[0];
            pos($text) = $start + 1;
            $e++ while $e < @ends && $ends[$e] <= $start;
            last if $e >= @ends;
            next if $index{$name} && $index{$name}[1] eq 'function';
            $index{$name} = [ $file, 'function', substr($text, $start, $ends[$e] - $start) ];
        }
        my @lines = split /\n/, $text;
        for (my $i = 0; $i < @lines; $i++) {
            next unless $lines[$i] =~ /^[ \t]*#[ \t]*define[ \t]+([A-Za-z_]\w*)\b/;
            my $name = $1;
            my $body = '';
            my $j = $i;
            while ($j < @lines) {
                $body .= "$lines[$j]\n";
                last unless $lines[$j] =~ /\\\s*$/;
                $j++;
            }
            $index{$name} = [ $file, 'macro', $body ] unless $index{$name};
            $i = $j;
        }
    }
    return $index_of{$tag} = \%index;
}

# A routine's definition at a tag: (file, kind, text) or ().  A routine named in the model's source-names.tsv is the
# concatenation of the C symbols listed there (for a function that a macro generates, say); otherwise it is the one
# definition of its own name.
sub definition_at {
    my ($tag, $name, $names) = @_;
    my @symbols = $names->{$name} ? @{ $names->{$name} } : ($name);
    my $index = index_at($tag);
    my (@parts, $file, $kind);
    for my $symbol (@symbols) {
        my $d = $index->{$symbol} or return ();
        ($file, $kind) = @$d[0, 1] unless defined $file;
        push @parts, "/* $symbol */\n$d->[2]";
    }
    return ($file, (@symbols > 1 ? 'composite' : $kind), join("\n", @parts));
}
sub normalized {
    my ($text) = @_;
    $text =~ s{/\*.*?\*/}{ }gs;
    $text =~ s{//[^\n]*}{}g;
    $text =~ s/\s+/ /g;
    $text =~ s/^ | $//g;
    return $text;
}

# The multiset of tokens with assertions removed, as a sorted string.
sub token_bag {
    my ($text) = @_;
    $text = normalized($text);
    $text =~ s/\bPERL_ARGS_ASSERT_\w+\s*;//g;
    $text =~ s/\bassert\s*\((?:[^()]|\([^()]*\))*\)\s*;//g;
    return join ' ', sort ($text =~ /\w+|[^\w\s]/g);
}

sub read_tsv {
    my ($path) = @_;
    return () unless -e $path;
    open my $fh, '<', $path or die "cannot read $path: $!\n";
    my @rows = map { [ split /\t/, $_ ] } grep { !/^\s*(#|$)/ } map { s/\s+\z//r } <$fh>;
    close $fh;
    return @rows;
}

for my $model (@ARGV) {
    open my $fh, '<', $model or die "cannot read $model: $!\n";
    my @names;
    my %seen;
    while (<$fh>) {
        next unless /^sub\s+([a-z][A-Za-z0-9_]*)\b/;
        push @names, $1 unless $seen{$1}++;
    }
    close $fh;
    (my $dir = $model) =~ s{/[^/]*\z}{};
    $dir = '.' if $dir eq $model;
    my %names = map { $_->[0] => [ split /,/, $_->[1] ] } read_tsv("$dir/source-names.tsv");
    my %neutral;
    $neutral{ $_->[0] }{ $_->[1] } = $_->[2] // 'reviewed' for read_tsv("$dir/source-equivalences.tsv");
    my $label = basename($model);
    print "# $label: ", scalar @names, " routines against @tags\n";
    my (@same, @reordered, @differ, @absent);
    for my $name (@names) {
        my (%def, $file, $kind);
        for my $tag (@tags) {
            my ($f, $k, $body) = definition_at($tag, $name, \%names);
            next unless defined $body;
            ($file, $kind) = ($f, $k) unless defined $file;
            $def{$tag} = $body;
            make_path("$work/$tag");
            open my $out, '>', "$work/$tag/$name.c" or die "cannot write $work/$tag/$name.c: $!\n";
            print {$out} $body;
            close $out;
        }
        if (!%def) { push @absent, $name; next }
        my @present = grep { exists $def{$_} } @tags;
        my $first = normalized($def{ $present[0] });
        my $bag = token_bag($def{ $present[0] });
        my @changed = grep { normalized($def{$_}) ne $first } @present[1 .. $#present];
        my @logic = grep { token_bag($def{$_}) ne $bag } @changed;
        my @reviewed = grep { $neutral{$name}{$_} } @logic;
        @logic = grep { !$neutral{$name}{$_} } @logic;
        my @missing = grep { !exists $def{$_} } @tags;
        if (!@changed && !@missing) {
            push @same, $name;
            printf "%-34s %-8s %-14s identical\n", $name, $kind, $file;
        }
        elsif (!@logic && !@missing) {
            push @reordered, $name;
            my @notes;
            push @notes, "neutral at " . join(' ', map { "$_ ($neutral{$name}{$_})" } @reviewed) if @reviewed;
            push @notes, "reordered at " . join(' ', grep { my $t = $_; !grep { $_ eq $t } @reviewed } @changed) if @changed > @reviewed;
            printf "%-34s %-8s %-14s %s\n", $name, $kind, $file, join('; ', @notes);
        }
        else {
            push @differ, $name;
            my @notes;
            push @notes, "differs at @logic" if @logic;
            push @notes, "neutral at " . join(' ', map { "$_ ($neutral{$name}{$_})" } @reviewed) if @reviewed;
            push @notes, "reordered at " . join(' ', grep { my $t = $_; !grep { $_ eq $t } @logic, @reviewed } @changed) if @changed > @logic + @reviewed;
            push @notes, "absent at @missing" if @missing;
            printf "%-34s %-8s %-14s %s\n", $name, $kind, $file, join('; ', @notes);
        }
    }
    printf "%-34s %-8s %-14s no C definition (label, arm or helper)\n", $_, '-', '-' for @absent;
    printf "# %s: %d identical across %s, %d reordered or reviewed neutral, %d differ, %d without a C definition\n",
        $label, scalar @same, join('/', @tags), scalar @reordered, scalar @differ, scalar @absent;
}
