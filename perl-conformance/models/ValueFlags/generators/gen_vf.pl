#!/usr/bin/perl
our $ROOT = $ENV{MODEL_ROOT} || '.'; my $TAG = $ENV{TAG} || "matrix"; our $WORK = $ENV{MODEL_WORK} || "$ROOT/work"; mkdir $WORK unless -d $WORK;

# Differential generator: perl (the reference run) vs the design's value flags model, for __WARN__ handlers that mutate
# the scalar being converted.  Every row's perl observation goes to $WORK/matrix.$TAG.tsv as input/repl/then/outer, the
# eight observed fields and the panic field, or CRASH, exactly as observed (a result marked `?` keeps its value);
# $WORK/matrix_final.$TAG.tsv holds the rows as the table records them.  With REPLAY_MATRIX=FILE the rows are read from
# FILE, in either form, instead of running perl, and only the model side runs.
use strict; use warnings; use POSIX ();
use FindBin; use lib "$FindBin::Bin/../../../lib";
use Perl::Conformance::Model::ValueFlags; use Perl::Conformance::Model::ValueFlags::Observe; use Perl::Conformance::PerlBugs;
my $PERL = $ENV{PERL_CONFORMANCE_PERL} || 'perl';
my @inputs = (['12x',q{'12x'}],['12.5x',q{'12.5x'}],['abc',q{'abc'}],['empty',q{''}],['sp12x',q{' 12x'}],
  ['1e3x',q{'1e3x'}],['Infx',q{'Infx'}],['nanx',q{'nanx'}],['-0x',q{'-0x'}],['0x1A',q{'0x1A'}],['1_000',q{'1_000'}],
  ['12U',q{"12\x{100}"}],['12',q{'12'}],['12.5',q{'12.5'}],['undef',q{undef}],['12n',q{12}],['12.5n',q{12.5}],['ref',q{\1}]);
my @repls = (['s99',q{$x='99';}],['s99.5',q{$x='99.5';}],['szz',q{$x='zz';}],['n99',q{$x=99;}],['n99.5',q{$x=99.5;}],['ref',q{$x=\1;}],['undef',q{undef $x;}],['keep',q{}]);
my @thens = (['iv',q{my $z=$x|0;}],['nv',q{my $z=sprintf('%.17g',$x);}],['none',q{}],['die',q{die "H\n";}]);
my @outers = (['add',q{0+$x}],['bor',q{$x|0}],['spg',q{sprintf('%g',$x)}],['cat',q{$x.""}]);

my $child_tmpl = <<'CHILD';
use strict; use warnings; use B; binmode(STDOUT, ":utf8");
my @F=(IOK=>B::SVf_IOK,NOK=>B::SVf_NOK,POK=>B::SVf_POK,pIOK=>B::SVp_IOK,pNOK=>B::SVp_NOK,pPOK=>B::SVp_POK,IsUV=>B::SVf_IVisUV,ROK=>B::SVf_ROK);
use lib '__LIB__'; use Perl::Conformance::Model::ValueFlags::Observe; *fl = \&Perl::Conformance::Model::ValueFlags::Observe::flags;
my $ADDR; sub num { my $v=shift; ref $v ? "ADDR" : (defined $ADDR && $v == $ADDR) ? "ADDR" : sprintf("%.17g",$v) }
my $x = __INPUT__;
my $calls=0; my $depth=0;
my $h = sub { $calls++; return if $depth++; __REPL__ __THEN__ $depth--; };
my $n; my $died=0; my $was_str = (defined $x && !ref $x) ? 1 : 0;
{ local $SIG{__WARN__}=$h; $n = eval { __OUTER__ }; $died = 1 if $@; }
{ local $SIG{__WARN__}=sub{}; $ADDR = 0+$x if ref $x; my $d = defined $x ? 1 : 0;
  my $nr = $died ? "die" : !defined $n ? "undef" : (__ISCAT__ ? "'$n'" : num($n)); $nr = "ADDR" if ref $x && $calls == 0 && !__ISCAT__ && !$died;
  my $f = fl(\$x);
  my $s = !defined $x ? "undef" : ref $x ? "ADDR" : "'$x'"; $s = "'ADDR'" if $s =~ /^'SCALAR\(0x/;
  $nr = "'ADDR'" if $nr =~ /^'SCALAR\(0x/;

  # W2: the handler made a string holder a reference while the outer NV conversion was parsing its string, so
  # sv_2nv_flags went on to parse the reference's target through the shared slot; the result is marked unreliable.
  $nr .= "?" if __NVCONV__ && $was_str && ref $x && $calls && !$died;
  my $a = num(0+$x); my $o = num($x|0); my $g = num(0.0+$x);
  print join("\t", $nr, $s, $a, $o, $g, $f, $calls, $d), "\n";
}
CHILD

# ---------------- model of the design ----------------
$child_tmpl =~ s/__LIB__/Perl::Conformance::Model::ValueFlags::Observe::lib_dir()/e;
package Perl::Conformance::Model::ValueFlags;
our $WEAKREF_ALIAS = 0;

# handler-matrix driver (uses the M2 primitives)
sub run_model { my ($in,$repl,$then,$outer)=@_;
  my $h = $in eq 'undef' ? { kind=>'U',iv=>0,nv=>0,int_form=>0,num_form=>0,is_uv=>0,stringified=>0} : $in eq "12n" ? { kind=>"I",iv=>12,nv=>0,int_form=>2,num_form=>0,is_uv=>0,stringified=>0}
        : $in eq "12.5n" ? { kind=>"N",iv=>0,nv=>12.5,int_form=>0,num_form=>2,is_uv=>0,stringified=>0} : $in eq 'ref' ? { kind=>'R',iv=>0,nv=>0,int_form=>0,num_form=>0,is_uv=>0,stringified=>0}
        : Perl::Conformance::Model::ValueFlags::Harness::string($in eq 'empty' ? '' : $in eq 'sp12x' ? ' 12x' : $in eq '12U' ? "12\x{100}" : $in);
  $h->{utf8} = 1 if $in eq "12U";    # the literal "12\x{100}" is a UTF-8 string
  my $calls=0; my $depth=0; my $died=0;
  my $ctx; $ctx = { warn => sub { my $hh=shift; $calls++; return if $depth++;
     my %set = (s99=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','99',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 }, 's99.5'=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','99.5',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 },
                szz=>sub{ @$hh{qw(kind pv int_form num_form is_uv stringified)}=('S','zz',0,0,0,0); $hh->{cow}=1; $hh->{cow}=1 }, n99=>sub{ @$hh{qw(kind iv int_form num_form is_uv stringified)}=("I",99,2,0,0,0); $hh->{cow}=0 },
                'n99.5'=>sub{ @$hh{qw(kind nv int_form num_form is_uv stringified)}=('N',99.5,0,2,0,0); $hh->{cow}=0 }, ref=>sub{ @$hh{qw(kind int_form num_form is_uv stringified)}=('R',0,0,0,0); $hh->{cow}=0 },
                undef=>sub{ @$hh{qw(kind int_form num_form is_uv stringified)}=('U',0,0,0,0); $hh->{cow}=0 }, keep=>sub{});
     $set{$repl}->();
     $hh->{utf8} = 0 unless $repl eq "keep";    # every assignment replaces the UTF8 flag; the replacements are not UTF-8
     if ($then eq 'iv') { sv_2iv_flags($hh,$ctx) } elsif ($then eq 'nv') { sv_2nv_flags($hh,$ctx) } elsif ($then eq 'die') { die "H\n" }
     $depth--; } };
  my $n = eval { my %ops=(add=>\&pp_add,bor=>\&pp_bit_or,spg=>\&sv_vcatpvfn_flags_g,cat=>\&sv_2pv_flags); $ops{$outer}->($h,$ctx) };
  if ($@) { return ("UB", "", "", "", "", "", $calls, "", "") if $@ =~ /^UB/; $died=1 }
  my $nr = $died ? "die" : $outer eq 'cat' ? "'$n'" : Perl::Conformance::Model::ValueFlags::Harness::Num($n);
  my $quiet = { warn => sub { $calls++ } };   # post-reads under a no-op handler (perl side counts them too? no: perl's post handler is sub{} which does not count)
  $quiet = { warn => sub {} };
  my $f = Perl::Conformance::Model::ValueFlags::Harness::FlagsProjection($h);
  my $d = ($h->{kind} eq "S" || $h->{kind} eq "R" || $h->{int_form} || $h->{num_form}) ? 1 : 0;
  my $s = !$d ? "undef" : $h->{kind} eq "R" ? "ADDR" : "'".sv_2pv_flags($h,$quiet)."'";
  my $a = Perl::Conformance::Model::ValueFlags::Harness::Num(pp_add($h,$quiet)); my $o = Perl::Conformance::Model::ValueFlags::Harness::Num(pp_bit_or($h,$quiet)); my $g = Perl::Conformance::Model::ValueFlags::Harness::Num(sv_2nv_flags($h,$quiet));

  # SVf_IVisUV and SVprv_WEAKREF are the same bit (sv.h), so a reference holder left with IsUV reads as a weak
  # reference, and freeing it croaks in sv_del_backref: the referent has no back-reference list.  $WEAKREF_ALIAS is set
# when the run's version is one perl-bugs.md lists for warn-handler-continuation, which is what lets the IsUV write
# happen.
  my $panic = ($WEAKREF_ALIAS && $h->{kind} eq 'R' && $h->{is_uv}) ? 'del_backref, svp=0' : '-';
  return ($nr,$s,$a,$o,$g,$f,$calls,$d,$panic);
}
package main;

# Runs one child under a 5-second limit and classifies how it ended:
#   ('ok', OUT)             a normal exit
#   ('panic', OUT, MESSAGE) perl croaked with "panic: MESSAGE" after printing its row
#   ('crash')               SIGSEGV killed it
# Any other ending (a timeout, another signal, another nonzero exit) has no recorded form yet and stops the run, so that
# the first one met is looked at before it is given one.
sub run_child {
    my ($file, $key) = @_;
    my $err = "$WORK/child_$TAG.err";
    my $pid = open(my $out, '-|') // die "cannot fork: $!\n";
    if (!$pid) {
        open STDERR, '>', $err or POSIX::_exit(127);
        exec $PERL, $file or POSIX::_exit(127);
    }
    my $text = '';
    my $timed_out = !eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 5;
        local $/;
        $text = <$out> // '';
        alarm 0;
        1;
    };
    kill 'KILL', $pid if $timed_out;
    close $out;
    my $st = $?;
    utf8::decode($text);
    die "$key: the child ran past 5 seconds; a timeout has no recorded form yet\n" if $timed_out;
    if (my $sig = $st & 127) {
        return ('crash') if $sig == POSIX::SIGSEGV();
        die "$key: the child died of signal $sig; only SIGSEGV has a recorded form (CRASH)\n";
    }
    return ('ok', $text) if $st == 0;
    open my $eh, '<', $err or die "cannot read $err: $!\n";
    my $stderr = do { local $/; <$eh> };
    close $eh;
    my ($panic) = $stderr =~ /^panic: (.*?) at \S+ line \d+\.$/m;
    return ('panic', $text, $panic) if defined $panic && ($text =~ tr/\t//) == 7;
    my ($first) = split /\n/, $stderr;
    die "$key: the child exited " . ($st >> 8) . " without a panic and a full row: " . ($first // '') . "\n";
}

# A row is the eight observed fields and `panic` (the message perl croaked with when the scalar was later freed, or
# `-`), or the single field CRASH.  A result ending in `?` is one the child marked as read through the W2 window; the
# model decides the final form: `?` when it agrees the row is undefined, the value without the mark when it does not
# (reported as a disagreement).
my ($rows, $ok, $bad, $crash, $ub, $flagbad, $panics) = (0, 0, 0, 0, 0, 0, 0);
my @report;

# The bug behind the undefined rows (perl-bugs.md).  On a version its entry lists, the bug is assumed present and a row
# whose results show it absent stops the run (exit 3) with nothing recorded; on any other version its marks are
# dropped and its rows are ordinary observations.
my $BUG = 'warn-handler-continuation';
my $VERSION = $ENV{PERL_VERSION}
    // ($ENV{REPLAY_MATRIX} ? die "REPLAY_MATRIX needs PERL_VERSION\n" : `$PERL -e 'printf "%vd", \$^V'`);
my $BUGS = Perl::Conformance::PerlBugs->load(
    Perl::Conformance::Model::ValueFlags::Observe::lib_dir() . "/../perl-bugs.md");
my $PRESENT = $BUGS->affects($BUG, $VERSION);
$Perl::Conformance::Model::ValueFlags::WEAKREF_ALIAS = $PRESENT;
my @absent;
my %REPLAY;
if (my $file = $ENV{REPLAY_MATRIX}) {
    open my $in, '<:utf8', $file or die "cannot read $file: $!\n";
    while (<$in>) { chomp; my ($k, @f) = split /\t/, $_, -1; $REPLAY{$k} = \@f }
    close $in;
}
my ($OBS, $FINAL);
unless ($ENV{REPLAY_MATRIX}) {
    open $OBS, '>:utf8', "$WORK/matrix.$TAG.tsv" or die "cannot write $WORK/matrix.$TAG.tsv: $!\n";
    open $FINAL, '>:utf8', "$WORK/matrix_final.$TAG.tsv" or die "cannot write $WORK/matrix_final.$TAG.tsv: $!\n";
}
for my $in (@inputs) { for my $re (@repls) { for my $th (@thens) { for my $ou (@outers) {
    my $key = "$in->[0]/$re->[0]/$th->[0]/$ou->[0]";
    my @p;
    if ($ENV{REPLAY_MATRIX}) {
        my $f = $REPLAY{$key} or next;
        @p = @$f;
    }
    else {
        my $code = $child_tmpl;
        $code =~ s/__INPUT__/$in->[1]/;
        $code =~ s/__REPL__/$re->[1]/;
        $code =~ s/__THEN__/$th->[1]/;
        $code =~ s/__OUTER__/$ou->[1]/;
        $code =~ s/__ISCAT__/($ou->[0] eq "cat" ? 1 : 0)/ge;
        $code =~ s/__NVCONV__/($ou->[0] eq "spg" ? 1 : 0)/ge;
        open my $fh, '>', "$WORK/child_$TAG.pl" or die; print $fh $code; close $fh;
        my ($how, $out, $msg) = run_child("$WORK/child_$TAG.pl", $key);
        if ($how eq 'crash') { @p = ('CRASH') }
        else { chomp $out; @p = ((split /\t/, $out, -1), $how eq 'panic' ? $msg : '-') }
        print $OBS join("\t", $key, @p), "\n";
    }
    $rows++;
    my @m = Perl::Conformance::Model::ValueFlags::run_model($in->[0], $re->[0], $th->[0], $ou->[0]);
    my $is_crash = $p[0] eq 'CRASH';
    $crash++ if $is_crash;
    my $marked = !$is_crash && $p[0] =~ /\?\z/;
    $p[8] //= q{-} unless $is_crash;
    if ($PRESENT && $m[0] eq "UB") {

        # W1 and W2: the bug's crash or unreliable read is expected.  A W2 read that yields the reference's own address
        # is a conversion that looked at the scalar again, and a row with neither shows the bug absent.
        $ub++;
        local $Perl::Conformance::Model::ValueFlags::DESIGN_DEFINED = 1;
        my @d = Perl::Conformance::Model::ValueFlags::run_model($in->[0], $re->[0], $th->[0], $ou->[0]);
        if ($is_crash) { push @report, "UNDEFINED-CRASH  $key design=[@d[0..4]]" }
        elsif ($marked && $p[0] ne 'ADDR?') {
            $p[0] = '?';
            push @report, "UNDEFINED-READ  $key perl=[@p[1..4]] design=[@d[0..4]]";
        }
        else { push @absent, "$key: neither the W1 crash nor a W2 read: perl=[@p[0..4]]" }
    }
    elsif ($m[0] eq "UB") {
        $p[0] =~ s/\?\z// if $marked;
        $bad++;
        my $seen = $is_crash ? "CRASH" : "@p[0..4]";
        push @report, "OPEN  $key: $BUG is not listed for $VERSION and the model has no other branch: perl=[$seen]";
    }
    elsif ($is_crash) { $bad++; push @report, "CRASH  $key: perl crashed where the model is defined: model=[@m[0..4]]" }
    else {
        if ($marked) {
            $p[0] =~ s/\?\z//;
            if ($PRESENT) {
                $bad++;
                push @report, "READ-UNMARKED  $key: perl marked the result as read through W2, the model is defined";
            }
        }
        if ($PRESENT && $m[8] ne '-' && $p[8] eq '-') { push @absent, "$key: no panic where W3 predicts `$m[8]`" }
        $panics++ if $p[8] ne '-';
        my $vals_ok = join("|", @p[0..4], $p[7] // "", $p[8]) eq join("|", @m[0..4], $m[7], $m[8]);
        if ($vals_ok) { $ok++ }
        else {
            $bad++;
            push @report, "VALUE  $key\n         perl : @p[0..4] panic=$p[8]\n         model: @m[0..4] panic=$m[8]";
        }
        if ($p[5] ne $m[5]) { $flagbad++; push @report, "FLAGS  $key perl=$p[5] model=$m[5]" if $vals_ok }
    }
    print $FINAL join("\t", $key, @p), "\n" if $FINAL;
}}}}
if (@absent) {
    close $FINAL if $FINAL;
    unlink "$WORK/matrix_final.$TAG.tsv";
    print "STOP: perl-bugs.md lists `$BUG` for $VERSION, but these rows show it absent; check the source and correct",
        " its versions before recording:\n";
    print "  $_\n" for @absent;
    exit 3;
}
print "rows=$rows values_ok=$ok values_bad=$bad flag_mismatch_on_value_ok_rows=$flagbad crash=$crash panic=$panics",
    " ub_rows=$ub\n";
print "$_\n" for @report;
