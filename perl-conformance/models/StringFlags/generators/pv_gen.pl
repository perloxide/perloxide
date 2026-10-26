#!/usr/bin/perl
# pv_gen.pl -- UTF-8 flag / taint enumeration.
#
# Depth 1: for each (string family, context, taint, op) a child perl prints an observation record of the op's result --
# bytes, UTF-8 flag, length, every character's ord, tainted, warnings, croak -- and StringFlags.pm produces the same
# record from its transcription; mismatches are reported with their recipe.
#
# Depth 2: the cross-context grid.  A producer op runs under one context and its result is handed to a reader op under
# another (every ordered pair of the depth-2 contexts, equal pairs included), untainted.  A lexical pragma attaches to
# the operation, never to the value, so this is the whole space of "made under one set of rules, read under another":
# the value crosses the boundary as bytes plus the flag and nothing else.
#
# Contexts: none; `use feature "unicode_strings"`; `use bytes`; and `use locale` under four runtime locales -- the
# harness's compiled ctype_utf8 and ctype_latin1, its compiled posix, and the C library's built-in "C".  The compiled
# locales come from lib/Perl/Conformance/Locales.pm, never from the system, and a context whose locale cannot be set is
# fatal rather than silently degraded.  The three non-locale contexts run with no locale selected at all (the child
# starts with LC_ALL and LANG empty); at depth 2 every block selects its runtime locale explicitly, "C" for those three,
# because one child mixes contexts.
#
#   PERL_CONFORMANCE_PERL=/path/to/perl TAG=<tag> DEPTH=1 perl generators/pv_gen.pl   # rows=... ok=... bad=...
#   PERL_CONFORMANCE_PERL=/path/to/perl TAG=<tag> DEPTH=2 perl generators/pv_gen.pl   # the cross-context grid
#
# Every observed row goes to work/pv_table.<TAG>.tsv (depth 1) or work/pv_table2.<TAG>.tsv (depth 2), keyed
# family.context.taint.op for depth 1 and family.context1.op1+context2.op2 for depth 2, with the columns bytes (hex),
# flag, length, ords, tainted, warnings, croak; an empty field is written as "-", so that no line ends in whitespace (an
# editor or git would strip a trailing empty field and corrupt the record).
#
# When TAG is a Perl version, a depth-1 run is also merged into the model's factored table, reports/table.tsv
# (lib/Perl/Conformance/Table.pm): one line per distinct result with the set of contexts and the set of versions it
# holds for, the full product expandable on demand with `perl-conformance table expand`.  Its records are terse: `=`
# for length and ords where they are the standard decode of the bytes under the flag, and one notes column holding the
# warnings and the croak, or `-`.  A depth-2 run is recorded by its row count and the SHA-256 of its table in the
# report, the table itself being one run away.
use strict;
use warnings;
use FindBin;
use File::Spec;
my $MODEL_ROOT = $ENV{MODEL_ROOT} || "$FindBin::Bin/..";
my $WORK = $ENV{MODEL_WORK} || "$MODEL_ROOT/work";
mkdir $WORK unless -d $WORK;
require "$MODEL_ROOT/StringFlags.pm";
use lib File::Spec->catdir($FindBin::Bin, '..', '..', '..', 'lib');
use Perl::Conformance::Locales;
use Perl::Conformance::Table;
use Digest::SHA qw(sha256_hex);

my $PERL  = $ENV{PERL_CONFORMANCE_PERL} || 'perl';
my $TAG   = $ENV{TAG} || 'x';
my $DEPTH = $ENV{DEPTH} || 1;

# The compiled locales are required: a context that cannot select its locale is a wrong row, not a skipped one.
my $LOCPATH = Perl::Conformance::Locales::compile("$WORK/locales") or die "cannot compile the harness locales: $Perl::Conformance::Locales::WHY\n";
my %LOCALE = map { $_ => Perl::Conformance::Locales::locale_name($_) } Perl::Conformance::Locales::names();

my %fam = (
    A => q{"abc"},
    B => q{"\xB5\xE9"},
    L => q{do { my $s = "\xB5\xE9"; utf8::upgrade($s); $s }},
    H => q{"a\x{100}"},
    M => q{do { my $s = "\xC3\x28"; Encode::_utf8_on($s); $s }},
    E => q{""},
    S => q{"\xDF"},
);

# Each context is [name, pragma, runtime locale or undef].  The pragma is lexical to the block that runs the op; the
# locale is selected at the start of that block (the non-locale contexts select "C" only at depth 2, see above).
my @ctx = (
    [ 'none',          '',                                undef ],
    [ 'feature',       'use feature "unicode_strings";',  undef ],
    [ 'bytes',         'use bytes;',                      undef ],
    [ 'locale_utf8',   'use locale;',                     $LOCALE{ctype_utf8} ],
    [ 'locale_latin1', 'use locale;',                     $LOCALE{ctype_latin1} ],
    [ 'locale_posix',  'use locale;',                     $LOCALE{posix} ],
    [ 'locale_c',      'use locale;',                     'C' ],
);
my @ctx2 = grep { $_->[0] !~ /^locale_(posix|c)\z/ } @ctx;

# Unary ops: code operates on $s and leaves the result in $r (a string or a number).
my %ops = (
    up=>'$r=$s; utf8::upgrade($r);', down=>'$r=$s; utf8::downgrade($r);', downok=>'$r=$s; my $ok = utf8::downgrade($r,1); $r .= ($ok ? "" : "");',
    enc=>'$r=$s; utf8::encode($r);', dec=>'$r=$s; utf8::decode($r);',
    len=>'$r=length($s);', rev=>'$r=reverse($s);', chop=>'$r=$s; chop $r;', chomp=>'$r=$s; chomp $r;',
    lc=>'$r=lc($s);', uc=>'$r=uc($s);', lcf=>'$r=lcfirst($s);', ucf=>'$r=ucfirst($s);', fc=>'$r=CORE::fc($s);',
    ord=>'$r=ord($s);', chr=>'$r=chr(ord($s));', sub1=>'$r=substr($s,0,1);', idx=>'$r=index($s,"\xB5");',
    sps=>'$r=sprintf("%s",$s);', spc=>'$r=sprintf("%c",ord($s));', rep=>'$r=$s x 2;', joinb=>'$r=join(",",$s,"\xB5");', joinu=>'$r=join(",",$s,"\x{100}");',
    split=>'my @p = split //, $s; $r = join("|", map { ord } @p);', tr=>'$r=$s; $r =~ tr/\xB5/X/;', trcnt=>'$r = ($s =~ tr/\xB5//);',
    unpU=>'$r=join(",",unpack("U*",$s));', unpC=>'$r=join(",",unpack("C*",$s));', unpU0C=>'$r=join(",",unpack("U0C*",$s));', unpC0U=>'$r=join(",",unpack("C0U*",$s));',
    packU=>'$r=pack("U",ord($s));', packa=>'$r=pack("a*",$s);', packA=>'$r=pack("A*",$s);',
    rew=>'$r=($s =~ /\w/) ? 1 : 0;', res=>'$r=($s =~ /\s/) ? 1 : 0;', red=>'$r=($s =~ /\d/) ? 1 : 0;',
    rewa=>'$r=($s =~ /\w/a) ? 1 : 0;', rewaa=>'$r=($s =~ /\w/aa) ? 1 : 0;', rewu=>'$r=($s =~ /\w/u) ? 1 : 0;', rewl=>'$r=($s =~ /\w/l) ? 1 : 0;', rewd=>'$r=($s =~ /\w/d) ? 1 : 0;',
    rei=>'$r=($s =~ /\x{39C}/i) ? 1 : 0;', reiu=>'$r=($s =~ /\x{39C}/iu) ? 1 : 0;', reia=>'$r=($s =~ /\x{39C}/ia) ? 1 : 0;',
    reiss=>'$r=($s =~ /ss/i) ? 1 : 0;', reissu=>'$r=($s =~ /ss/iu) ? 1 : 0;', reissa=>'$r=($s =~ /ss/ia) ? 1 : 0;', reissaa=>'$r=($s =~ /ss/iaa) ? 1 : 0;', reissl=>'$r=($s =~ /ss/il) ? 1 : 0;',
    cap=>'($r) = $s =~ /(.*)/s;', hkey=>'my %h = ($s => 1); ($r) = keys %h;', hkey2=>'my %h; $h{$s}=1; my $t=$s; if (utf8::is_utf8($t)) { utf8::encode($t) } else { utf8::upgrade($t) } $h{$t}=2; $r = scalar(keys %h);',
    catb=>'$r = $s . "\xB5";', catu=>'$r = $s . "\x{100}";', catl=>'my $t="\xB5"; utf8::upgrade($t); $r = $s . $t;', apb=>'$r=$s; $r .= "\xB5";', apu=>'$r=$s; $r .= "\x{100}";', apl=>'my $t="\xB5"; utf8::upgrade($t); $r=$s; $r .= $t;',
    eqb=>'$r = ($s eq "\xB5\xE9") ? 1 : 0;', eql=>'my $t="\xB5\xE9"; utf8::upgrade($t); $r = ($s eq $t) ? 1 : 0;', cmpb=>'$r = ($s cmp "\xB5\xE9");',
    spd=>'$r=sprintf("%d", length($s));', arith=>'$r=length($s)+0;', copy=>'my $c=$s; $r=$c;',
);
my @unary = sort keys %ops;

# Depth 2: producers are the ops whose result bytes or flag depend on the context they run under; readers are the ops
# whose answer depends on the flag and the context they run under.
my @producers = qw(up down enc dec lc uc fc rev sub1 cap catb catu catl apb apu apl joinb joinu tr chr packU packa sps copy);
my @readers   = qw(len ord sub1 idx rew rewu rewa rewaa rewl rewd rei reiu reia reiss reissa reissaa uc lc fc eqb eql cmpb hkey hkey2 split chop rev unpU unpC);

my $head = <<'H';
use strict; no warnings; use POSIX (); use Encode (); use Scalar::Util qw(tainted); binmode(STDOUT, ":raw");
my @W; $SIG{__WARN__} = sub { my $m=$_[0]; $m =~ s/ at .*//s; $m =~ s/\s*\(.*//s; push @W, $m };
sub loc { my ($name) = @_; return unless defined $name; POSIX::setlocale(POSIX::LC_ALL(), $name) // do { print "LOCALE FAIL $name\n"; exit 3 } }
sub obs { my ($r) = @_; my $b = defined $r ? $r : "undef";
  my $f = utf8::is_utf8($b) ? 1 : 0; my $bb = $b; utf8::encode($bb) if $f;
  my $len = eval { length($b) } // "err"; my $ords = eval { join(",", map { ord } split //, $b) } // "err";
  join("\t", unpack("H*", $bb), $f, $len, $ords, (tainted($b) ? 1 : 0)) }
H

# A record for the report or the table: an empty field is written as "-", so that no line ends in whitespace.
sub show {
    my ($rec) = @_;
    return join("\t", map { length($_) ? $_ : "-" } split(/\t/, $rec, -1));
}

sub quoted {
    my ($s) = @_;
    $s =~ s/([\\"])/\\$1/g;
    return "\"$s\"";
}

# One row's child code: the start value is built outside any context (a taint-marking concatenation under `use bytes`
# would otherwise strip the flag), then the blocks that run the ops, each under its own context, writing the result to
# $rr; a croaking op leaves $rr undefined and reports the error.
sub row_code {
    my ($i, $init, @steps) = @_;
    my ($first, @rest) = @steps;
    my $code = "{ \@W=(); my \$rr; my \$err = ''; my \$ok = eval {\n  $init\n";
    $code .= "  { $first->{ctx}[1] " . ($first->{setloc} ? "loc(" . quoted($first->{ctx}[2] // 'C') . "); " : '') . "my \$r; $ops{$first->{op}} \$rr = \$r; }\n";
    for my $st (@rest) {
        $code .= "  { $st->{ctx}[1] " . ($st->{setloc} ? "loc(" . quoted($st->{ctx}[2] // 'C') . "); " : '') . "my \$s = \$rr; \$rr = undef; my \$r; $ops{$st->{op}} \$rr = \$r; }\n";
    }
    $code .= "  1 }; \$err = \$ok ? '' : do { my \$e = \$@; \$e =~ s/ at .*//s; \$e =~ s/\\n.*//s; \$e };\n";
    $code .= "  print \"$i\\t\", obs(\$rr), \"\\t\", join('|', \@W), \"\\t\$err\\n\"; }\n";
    return $code;
}

# Runs one child over the given rows (each [key, model steps, child code, family]) and compares every row with the model.
my ($ok, $bad, $n) = (0, 0, 0);
my @rep;
my %table;
sub run_child {
    my ($taint, $rows) = @_;
    my $code = $head . "\n" . join('', map { $_->[2] } @$rows);
    open my $fh, '>', "$WORK/pv_child.pl" or die "cannot write $WORK/pv_child.pl: $!\n";
    print $fh $code;
    close $fh;
    my $cmd = "LC_ALL= LANG= LOCPATH=\"$LOCPATH\" TSRC=x timeout 60 $PERL " . ($taint ? "-T " : "") . "$WORK/pv_child.pl 2>/dev/null </dev/null";
    my $out = `$cmd`;
    die "a context's locale could not be selected: $1\n" if $out =~ /^LOCALE FAIL (.*)/m;
    my %got;
    for (split /\n/, $out) { my ($k, @f) = split /\t/, $_, -1; $got{$k} = join("\t", @f) }
    my $i = 0;
    for my $row (@$rows) {
        $i++;
        my ($key, $steps, undef, $fam) = @$row;
        my $g = $got{$i} // "NO OUTPUT";
        my $m = Perl::Conformance::Model::StringFlags::Harness::Run($fam, $taint, $steps);
        $n++;
        $table{$key} = $g;

        # The warning column is recorded but not compared: warnings are not enumerated.
        my ($gc, $mc) = map { my @f = split /\t/, $_, -1; $f[5] = ""; join("\t", @f) } ($g, $m);
        if ($gc eq $mc) { $ok++ } else { $bad++; push @rep, "MISMATCH $key\n  perl:  " . show($g) . "\n  model: " . show($m) }
    }
}

if ($DEPTH == 1) {
    for my $fam (sort keys %fam) {
        for my $c (@ctx) {
            for my $taint (0, 1) {
                my $init = $taint ? 'my $s = ' . $fam{$fam} . '; my $tsrc = substr($ENV{TSRC},0); $s = $s . substr($tsrc,0,0);' : 'my $s = ' . $fam{$fam} . ';';
                my @rows;
                my $i = 0;
                for my $op (@unary) {
                    $i++;
                    my $step = { op => $op, ctx => $c, setloc => defined $c->[2] };
                    push @rows, [ "$fam.$c->[0]." . ($taint ? 'T' : 'U') . ".$op", [ [ $op, $c->[0] ] ], row_code($i, $init, $step), $fam ];
                }
                run_child($taint, \@rows);
            }
        }
    }
}
else {
    for my $fam (sort keys %fam) {
        for my $c1 (@ctx2) {
            for my $c2 (@ctx2) {
                my $init = 'my $s = ' . $fam{$fam} . ';';
                my @rows;
                my $i = 0;
                for my $p (@producers) {
                    for my $r (@readers) {
                        $i++;
                        my @steps = ({ op => $p, ctx => $c1, setloc => 1 }, { op => $r, ctx => $c2, setloc => 1 });
                        push @rows, [ "$fam.$c1->[0].$p+$c2->[0].$r", [ [ $p, $c1->[0] ], [ $r, $c2->[0] ] ], row_code($i, $init, @steps), $fam ];
                    }
                }
                run_child(0, \@rows);
            }
        }
    }
}

my $table = $DEPTH == 1 ? "$WORK/pv_table.$TAG.tsv" : "$WORK/pv_table2.$TAG.tsv";
open my $t, '>', $table or die "cannot write $table: $!\n";
print $t "$_\t", show($table{$_}), "\n" for sort keys %table;
close $t;
my $digest = do { open my $fh, '<', $table or die; local $/; sha256_hex(<$fh>) };
print "oracle=$PERL depth=$DEPTH rows=$n ok=$ok bad=$bad table-sha256=$digest\n";
print "$_\n" for @rep;

# The terse record for the factored table.
sub terse {
    my ($rec) = @_;
    my ($bytes, $flag, $len, $ords, $taint, $warn, $croak) = split /\t/, $rec, -1;
    my $raw = pack('H*', $bytes);
    my ($std_len, $std_ords);
    if ($flag) {
        my $c = $raw;
        if (utf8::decode($c)) { $std_len = length $c; $std_ords = join(',', map { ord } split //, $c) }
    }
    else {
        $std_len = length $raw;
        $std_ords = join(',', map { ord } split //, $raw);
    }
    $len  = '=' if defined $std_len  && $len eq $std_len;
    $bytes = '-' unless length $bytes;
    $ords = '=' if defined $std_ords && $ords eq $std_ords;
    my @notes = ((length $warn ? "W:$warn" : ()), (length $croak ? "E:$croak" : ()));
    return join("\t", $bytes, $flag, $len, $ords, $taint, (@notes ? join(' | ', @notes) : '-'));
}

if ($DEPTH == 1 && $TAG =~ /^\d+\.\d+\.\d+\z/) {
    my $path = "$MODEL_ROOT/reports/table.tsv";
    my $ft = -e $path ? Perl::Conformance::Table->load($path)
           : Perl::Conformance::Table->new(axes => [qw(family context taint op)], folded => 'context', fields => [qw(bytes flag length ords tainted notes)]);
    $ft->merge($TAG, { map { $_ => terse($table{$_}) } keys %table });
    $ft->write($path);
    print STDERR "merged $TAG into $path\n";
}
