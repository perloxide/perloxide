#!/usr/bin/perl
# Differential generator for `local` semantics: real perl (oracle) vs SS.pm.
# Cells: {plain, tied, magical ($/, $0), glob-aliased} x {package scalar,
# element present/absent, whole glob} x {bare, assignment, self-assignment}
# x {no mutation, pre-local-ref mutation, container clear, delete} x
# {normal, die in body, die in restoration STORE, die in displaced DESTROY}
# x depth 1-2. Observables: callback trace, first-appearance-normalized
# refaddrs at three points, final value, exists, $@ at the catch and at the
# following statement boundary.
#
# A second block enumerates structural array changes under an element
# local: plain array x {element present, element absent} x {bare,
# assignment} x {no change, shift, shift twice, unshift, pop, push,
# splice remove, splice insert, $#a = -1, $#a = 0, clear-and-refill} x
# {normal, die in body}. Its observables are per-index (identity, exists,
# value) over indices 0-6 after the scope, the final $#a, and two
# references captured inside the scope: one to the SV the local installed,
# one to the SV a removing operation handed back. Those show where the
# installed SV went and that it outlives the scope.
use strict; use warnings; use FindBin; use lib ($ENV{MODEL_ROOT} || "$FindBin::Bin/.."); my $WORK = $ENV{MODEL_WORK} || ($ENV{MODEL_ROOT} || "$FindBin::Bin/..") . "/work"; mkdir $WORK unless -d $WORK;
require SS;
my $PERL = $ENV{ORACLE} || 'perl';

my @cells;
my %SITES = (
    pkg => 1, aeP => 1, aeA => 1, heP => 1, heA => 1, glob => 1);
my %KS = (
    plain => [qw(pkg aeP aeA heP heA glob)],
    tied  => [qw(pkg aeP aeA heP heA)],
    mrs   => ['pkg'], mz => ['pkg'],
    alias => [qw(pkg glob)]);
my %MUT = (
    pkg => [qw(none preref)], aeP => [qw(none preref clear del)],
    heP => [qw(none preref clear del)], aeA => [qw(none clear)],
    heA => [qw(none clear)], glob => ['none']);
for my $k (sort keys %KS) {
    for my $s (@{ $KS{$k} }) {
        for my $m (qw(bare assign self)) {
            for my $mu (@{ $MUT{$s} }) {
                my @ex = ('ok', 'dieB');
                push @ex, 'dieS' if $k eq 'tied';
                push @ex, 'dieD' if $m eq 'assign' && $s ne 'glob'
                    && ($k eq 'plain' || $k eq 'tied' || $k eq 'alias');
                push @cells, { k => $k, s => $s, m => $m, mu => $mu,
                    ex => $_, d => 1 } for @ex;
            }
        }
    }
}
for my $k (qw(plain tied)) {
    for my $s (qw(pkg aeP heP)) {
        next if $k eq 'plain' && $s eq 'aeP' && 0;
        for my $m (qw(bare assign)) {
            for my $ex (qw(ok dieB)) {
                push @cells, { k => $k, s => $s, m => $m, mu => 'none',
                    ex => $ex, d => 2 };
            }
        }
    }
}

# Structural cells: plain arrays only. The element is index 1 of three
# (present) or index 5 (absent, vivified by the local). The no-change
# mutation is named keep so its key differs from the none cells above.
my @STRUCT = qw(keep shift1 shift2 unshift1 pop1 push1 splice_rm splice_ins
    fill_neg1 fill0 refill);
for my $s (qw(aeP aeA)) {
    for my $m (qw(bare assign)) {
        for my $mu (@STRUCT) {
            for my $ex (qw(ok dieB)) {
                push @cells, { k => 'plain', s => $s, m => $m, mu => $mu,
                    ex => $ex, d => 1, st => 1 };
            }
        }
    }
}

# ---------------- child renderer ----------------
my $prelude = <<'PRE';
use strict; use warnings; use Scalar::Util qw(refaddr);
our @T; our $ARMDIE;
sub tr2 { push @T, join(':', @_) }
sub ss { my $v = shift; !defined $v ? 'u' : ref $v ? 'r' : "$v" }
package TS; sub TIESCALAR { bless { v => $_[1] }, $_[0] }
sub FETCH { main::tr2('F', main::ss($_[0]{v})); $_[0]{v} }
sub STORE { main::tr2('S', main::ss($_[1])); die "S\n" if $main::ARMDIE; $_[0]{v} = $_[1] }
package TA; sub TIEARRAY { my ($c, @v) = @_; my %s; $s{$_} = $v[$_] for 0 .. $#v;
    bless { s => \%s, top => $#v }, $c }
sub FETCH { main::tr2('F', $_[1], main::ss($_[0]{s}{$_[1]})); $_[0]{s}{$_[1]} }
sub STORE { main::tr2('S', $_[1], main::ss($_[2])); die "S\n" if $main::ARMDIE;
    $_[0]{s}{$_[1]} = $_[2]; $_[0]{top} = $_[1] if $_[1] > $_[0]{top} }
sub FETCHSIZE { $_[0]{top} + 1 } sub STORESIZE { $_[0]{top} = $_[1] - 1 } sub EXTEND { }
sub EXISTS { main::tr2('E', $_[1]); exists $_[0]{s}{$_[1]} }
sub DELETE { main::tr2('D', $_[1]); my $t = $_[0]; delete $t->{s}{$_[1]};
    if ($_[1] == $t->{top}) { my $i = $_[1] - 1; $i-- while $i >= 0 && !exists $t->{s}{$i}; $t->{top} = $i } }
sub CLEAR { main::tr2('C'); $_[0]{s} = {}; $_[0]{top} = -1 }
package TH; sub TIEHASH { my ($c, %v) = @_; bless { s => {%v} }, $c }
sub FETCH { main::tr2('F', $_[1], main::ss($_[0]{s}{$_[1]})); $_[0]{s}{$_[1]} }
sub STORE { main::tr2('S', $_[1], main::ss($_[2])); die "S\n" if $main::ARMDIE; $_[0]{s}{$_[1]} = $_[2] }
sub EXISTS { main::tr2('E', $_[1]); exists $_[0]{s}{$_[1]} }
sub DELETE { main::tr2('D', $_[1]); delete $_[0]{s}{$_[1]} }
sub CLEAR { main::tr2('C'); $_[0]{s} = {} }
package PO; sub new { bless { n => $_[1], d => $_[2] // 0 }, $_[0] }
sub DESTROY { main::tr2('X', $_[0]{n}); die "D\n" if $_[0]{d} }
package main;
sub fmte { my $e = shift; return '' unless $e; $e =~ s/\n.*//s; $e =~ s/ at .*//;
    return substr($e, 0, 12) }
PRE

sub render_child {
    my ($c) = @_;
    my ($k, $s, $m, $mu, $ex, $d) = @$c{qw(k s m mu ex d)};
    my ($setup, $site, $exists_expr, $pre_ok) = ('', '', "'-'", 1);
    if ($s eq 'pkg') {
        if ($k eq 'plain') { $setup = 'our $x; $x = 10;'; $site = '$x' }
        elsif ($k eq 'tied') { $setup = "tie our \$x, 'TS', 10;"; $site = '$x' }
        elsif ($k eq 'mrs') { $setup = "\$/ = 10;"; $site = '$/' }
        elsif ($k eq 'mz') { $setup = "\$0 = 'ten';"; $site = '$0' }
        elsif ($k eq 'alias') { $setup = 'our $w; $w = 10; our $x; *x = \\$w;'; $site = '$x' }
    }
    elsif ($s =~ /^ae/) {
        $setup = $k eq 'tied' ? "tie our \@a, 'TA', 10, 20, 30;"
                              : 'our @a; @a = (10, 20, 30);';
        my $i = $s eq 'aeP' ? 1 : 5;
        $site = "\$a[$i]"; $exists_expr = "(exists \$a[$i] ? 1 : 0)";
        $pre_ok = $s eq 'aeP' ? 1 : 0;
    }
    elsif ($s =~ /^he/) {
        $setup = $k eq 'tied' ? "tie our \%h, 'TH', k => 10;"
                              : 'our %h; %h = (k => 10);';
        my $kk = $s eq 'heP' ? 'k' : 'nk';
        $site = "\$h{$kk}"; $exists_expr = "(exists \$h{$kk} ? 1 : 0)";
        $pre_ok = $s eq 'heP' ? 1 : 0;
    }
    elsif ($s eq 'glob') {
        $setup = $k eq 'alias' ? 'our $w; $w = 10; our $x; *x = \\$w; our $y; $y = 88;'
                               : 'our $x; $x = 10; our $y; $y = 88;';
        $site = '$x';
    }
    my $assignval = $ex eq 'dieD' ? "PO->new('V', 1)" : '20';
    my $localstmt =
        $s eq 'glob'
            ? ($m eq 'bare' ? 'local *x;'
             : $m eq 'assign' ? 'local *x = \\$y;'
             : 'local *x = *x;')
            : ($m eq 'bare' ? "local $site;"
             : $m eq 'assign' ? "local $site = $assignval;"
             : "local $site = $site;");
    my $preref = $mu eq 'preref' ? "my \$r = \\$site;" : '';
    my $mut = $mu eq 'preref' ? "\$\$r = 77;"
            : $mu eq 'clear' ? ($s =~ /^ae/ ? '@a = ();' : '%h = ();')
            : $mu eq 'del' ? ($s =~ /^ae/ ? 'delete $a[1];' : 'delete $h{k};')
            : '';
    my $exit = $ex eq 'dieB' ? 'die "B\\n";'
             : $ex eq 'dieS' ? '$ARMDIE = 1;' : '';
    my $body;
    if ($d == 1) {
        $body = "  $localstmt\n  \$p2 = refaddr(\\$site);\n"
              . ($mut ? "  $mut\n" : '') . ($exit ? "  $exit\n" : '') . "  1;\n";
    }
    else {
        my $inner = $s eq 'glob' ? 'local *x = \\$y;' : "local $site = 30;";
        $body = "  $localstmt\n  my \$pad = PO->new('P', 0);\n"
              . "  { $inner 1; }\n  \$p2 = refaddr(\\$site);\n"
              . ($exit ? "  $exit\n" : '') . "  1;\n";
    }
    my $code = $prelude . "\n$setup\n"
        . "my (\$p1, \$p2, \$p3) = ('-', '-', '-');\n"
        . ($pre_ok ? "\$p1 = refaddr(\\$site);\n" : '')
        . ($preref ? "$preref\n" : '')
        . "my (\$e1, \$e2) = ('', '');\n"
        . "eval {\n$body};\n\$e1 = fmte(\$@);\n"
        . "eval { my \$zz = 1; };\n\$e2 = fmte(\$@);\n"
        . "my \$ex = $exists_expr;\n"
        . "my \$fv = ss($site);\n"
        . "\$p3 = ('$s' !~ /A\$/ || \$ex) ? refaddr(\\$site) : '-';\n"
        . "print join('|', 'T=' . join(',', \@T), \"I=\$p1:\$p2:\$p3\","
        . " \"F=\$fv\", \"X=\$ex\", \"Q=\$e1/\$e2\"), \"\\n\";\n";
    return $code;
}

# The structural mutations as the child runs them. $r2 captures the SV a
# removing operation hands back; the backslash on shift/pop/splice takes a
# reference to that SV itself, not to a copy.
my %STRUCT_CODE = (
    keep       => '',
    shift1     => '$r2 = \shift @a;',
    shift2     => 'shift @a; $r2 = \shift @a;',
    unshift1   => 'unshift @a, 7;',
    pop1       => '$r2 = \pop @a;',
    push1      => 'push @a, 7;',
    splice_rm  => '($r2) = \splice(@a, 0, 1);',
    splice_ins => 'splice(@a, 0, 0, 7);',
    fill_neg1  => '$#a = -1;',
    fill0      => '$#a = 0;',
    refill     => '@a = (7, 8);',
);
my $STRUCT_TOP = 6;

sub render_struct_child {
    my ($c) = @_;
    my ($s, $m, $mu, $ex) = @$c{qw(s m mu ex)};
    my $i = $s eq 'aeP' ? 1 : 5;
    my $localstmt = $m eq 'bare' ? "local \$a[$i];" : "local \$a[$i] = 50;";
    my $exit = $ex eq 'dieB' ? 'die "B\\n";' : '';
    my $code = $prelude . "\nour \@a; \@a = (10, 20, 30);\n"
        . "my (\$p1, \$p2) = ('-', '-');\n"
        . ($s eq 'aeP' ? "\$p1 = refaddr(\\\$a[$i]);\n" : '')
        . "my (\$r1, \$r2);\n"
        . "my (\$e1, \$e2) = ('', '');\n"
        . "eval {\n  $localstmt\n  \$p2 = refaddr(\\\$a[$i]);\n  \$r1 = \\\$a[$i];\n"
        . "  $STRUCT_CODE{$mu}\n" . ($exit ? "  $exit\n" : '') . "  1;\n};\n"
        . "\$e1 = fmte(\$@);\n"
        . "eval { my \$zz = 1; };\n\$e2 = fmte(\$@);\n"
        . "my \@X = map { exists \$a[\$_] ? 1 : 0 } 0 .. $STRUCT_TOP;\n"
        . "my \@I = map { \$X[\$_] ? refaddr(\\\$a[\$_]) : '-' } 0 .. $STRUCT_TOP;\n"
        . "my \@F = map { \$X[\$_] ? ss(\$a[\$_]) : '-' } 0 .. $STRUCT_TOP;\n"
        . "my \@R = map { defined \$_ ? refaddr(\$_) : '-' } \$r1, \$r2;\n"
        . "my \@V = map { defined \$_ ? ss(\$\$_) : '-' } \$r1, \$r2;\n"
        . "print join('|', 'T=' . join(',', \@T),"
        . " 'I=' . join(':', \$p1, \$p2, \@I, \@R), 'F=' . join(',', \@F),"
        . " 'X=' . join('', \@X), 'N=' . \$#a, 'E=' . join(',', \@V),"
        . " \"Q=\$e1/\$e2\"), \"\\n\";\n";
    return $code;
}

sub norm_ids {
    my ($line) = @_;
    return $line unless $line =~ /I=([^|]*)/;
    my @p = split /:/, $1, -1;
    my (%map, @out); my $next = 'a';
    for (@p) {
        if ($_ eq '-') { push @out, '-'; next }
        $map{$_} //= $next++;
        push @out, $map{$_};
    }
    my $n = join(':', @out);
    $line =~ s/I=[^|]*/I=$n/;
    return $line;
}

# ---------------- SS replay ----------------
our ($RSG, $ZG);
sub fmte { my $e = shift; return '' unless $e; $e =~ s/\n.*//s; $e =~ s/ at .*//;
    return substr($e, 0, 12) }

sub replay {
    my ($c) = @_;
    my ($k, $s, $m, $mu, $ex, $d) = @$c{qw(k s m mu ex d)};
    SS::reset_world();
    $RSG = 10; $ZG = 'ten';
    my ($avid, $hvid, $gv, $idx, $key);
    my ($p1, $p2, $p3) = ('-', '-', '-');
    my $site_read; my $site_addr; my $exists_q = sub { '-' };
    if ($s eq 'pkg') {
        $gv = SS::new_glob('x');
        my $cell = ${ SS::glob_svslot('x') };
        if ($k eq 'plain') { $SS::CELL{$cell}{v} = 10 }
        elsif ($k eq 'tied') {
            my $tie = { v => 10 };
            push @{ $SS::CELL{$cell}{mag} }, { t => 'ties', o => $tie };
            $SS::CELL{$cell}{smag} = $SS::CELL{$cell}{gmag} = 1;
        }
        elsif ($k eq 'mrs') {
            push @{ $SS::CELL{$cell}{mag} }, { t => 'sv', name => '$/', gref => \$RSG };
            $SS::CELL{$cell}{smag} = $SS::CELL{$cell}{gmag} = 1;
            $SS::CELL{$cell}{v} = 10;
        }
        elsif ($k eq 'mz') {
            push @{ $SS::CELL{$cell}{mag} }, { t => 'sv', name => '$0', gref => \$ZG };
            $SS::CELL{$cell}{smag} = $SS::CELL{$cell}{gmag} = 1;
            $SS::CELL{$cell}{v} = 'ten';
        }
        elsif ($k eq 'alias') { $SS::CELL{$cell}{v} = 10 }
        $site_addr = sub { ${ SS::glob_svslot('x') } };
        $site_read = sub { SS::cell_get(${ SS::glob_svslot('x') }) };
    }
    elsif ($s =~ /^ae/) {
        $idx = $s eq 'aeP' ? 1 : 5;
        $avid = SS::new_av();
        if ($k eq 'tied') {
            $SS::AV{$avid}{tie} = { store => { 0 => 10, 1 => 20, 2 => 30 }, top => 2 };
        }
        else {
            $SS::AV{$avid}{elems} = [ map { my $c2 = SS::new_cell(); $SS::CELL{$c2}{v} = $_; $c2 } 10, 20, 30 ];
        }
        $site_addr = sub {
            if ($SS::AV{$avid}{tie}) { my (undef, $mm) = SS::av_fetch_lv($avid, $idx); return $mm }
            return $SS::AV{$avid}{elems}[$idx];
        };
        $site_read = sub {
            if ($SS::AV{$avid}{tie}) {
                my $v = $SS::AV{$avid}{tie}{store}{$idx};
                SS::trace('F', $idx, SS::vv($v)); return $v;
            }
            my $e = $SS::AV{$avid}{elems}[$idx];
            return defined $e ? SS::cell_get($e) : undef;
        };
        $exists_q = sub { SS::av_exists($avid, $idx) };
    }
    elsif ($s =~ /^he/) {
        $key = $s eq 'heP' ? 'k' : 'nk';
        $hvid = SS::new_hv();
        if ($k eq 'tied') { $SS::HV{$hvid}{tie} = { store => { k => 10 } } }
        else { my $c2 = SS::new_cell(); $SS::CELL{$c2}{v} = 10; $SS::HV{$hvid}{elems}{k} = $c2 }
        $site_addr = sub {
            if ($SS::HV{$hvid}{tie}) { my (undef, $mm) = SS::hv_fetch_lv($hvid, $key); return $mm }
            return $SS::HV{$hvid}{elems}{$key};
        };
        $site_read = sub {
            if ($SS::HV{$hvid}{tie}) {
                my $v = $SS::HV{$hvid}{tie}{store}{$key};
                SS::trace('F', $key, SS::vv($v)); return $v;
            }
            my $e = $SS::HV{$hvid}{elems}{$key};
            return defined $e ? SS::cell_get($e) : undef;
        };
        $exists_q = sub { SS::hv_exists($hvid, $key) };
    }
    elsif ($s eq 'glob') {
        $gv = SS::new_glob('x');
        $SS::CELL{ ${ SS::glob_svslot('x') } }{v} = 10;
        SS::new_glob('y');
        $SS::CELL{ ${ SS::glob_svslot('y') } }{v} = 88;
        $site_addr = sub { ${ SS::glob_svslot('x') } };
        $site_read = sub { SS::cell_get(${ SS::glob_svslot('x') }) };
    }
    my $pre_ok = !($s eq 'aeA' || $s eq 'heA');
    $p1 = $site_addr->() if $pre_ok;
    my $prerefcell;
    if ($mu eq 'preref') { $prerefcell = SS::rc_inc($site_addr->()) }

    my ($e1, $e2) = ('', '');
    my $base = @SS::SS;
    my $bodyerr = '';
    $SS::PENDING = undef;
    my $mkobj = sub {
        my ($n, $dd) = @_;
        my $obj = SS::new_cell(obj => { n => $n, d => $dd });
        my $tmp = SS::new_cell(); $SS::CELL{$tmp}{v} = ['RV', $obj];
        SS::mortal($tmp);
        return $obj;
    };
    my $do_local = sub {
        my ($assignv) = @_;
        my $fresh;
        if ($s eq 'pkg') {
            my $rhs; $rhs = ${ SS::glob_svslot("x") } if $m eq "self";
            $fresh = SS::local_pkg_scalar('x');
            if ($m eq 'assign') {
                if (ref $assignv) { SS::cell_set_rv($fresh, $$assignv) }
                else { SS::cell_set($fresh, $assignv) }
            }
            elsif ($m eq 'self') { my $v = SS::cell_get($rhs); SS::cell_set($fresh, $v) }
        }
        elsif ($s =~ /^ae/ || $s =~ /^he/) {
            my ($rhs_v, $have_rhs);
            if ($m eq 'self') {
                my $rhsm;
                if ($s =~ /^ae/) {
                    if ($SS::AV{$avid}{tie} || defined $SS::AV{$avid}{elems}[$idx]) {
                        (undef, $rhsm) = SS::av_fetch_lv($avid, $idx);
                    }
                }
                else {
                    if ($SS::HV{$hvid}{tie} || exists $SS::HV{$hvid}{elems}{$key}) {
                        (undef, $rhsm) = SS::hv_fetch_lv($hvid, $key);
                    }
                }
                $rhs_v = defined $rhsm ? SS::cell_get($rhsm) : undef;
                $have_rhs = 1;
            }
            my $slotref = $s =~ /^ae/
                ? SS::local_aelem($avid, $idx, $m ne 'bare')
                : SS::local_helem($hvid, $key, $m ne 'bare');
            $fresh = $$slotref;
            if ($m eq 'assign') {
                if (ref $assignv) { SS::cell_set_rv($fresh, $$assignv) }
                else { SS::cell_set($fresh, $assignv) }
            }
            elsif ($m eq 'self') { SS::cell_set($fresh, $rhs_v) }
        }
        elsif ($s eq 'glob') {
            my $oldgp = $SS::GLOB{x}{gp};
            SS::save_gp('x', 1);
            if ($m eq 'assign') {
                my $slot = SS::glob_svslot('x');
                my $ref = ${ SS::glob_svslot('y') };
                SS::rc_dec($$slot); $$slot = SS::rc_inc($ref);
            }
            elsif ($m eq 'self') {
                SS::gp_free($SS::GLOB{x}{gp});
                $SS::GLOB{x}{gp} = $oldgp;
                $SS::GP{$oldgp}{rc}++;
            }
        }
        return $fresh;
    };
    my $padslot;
    eval {
        if ($d == 1) {
            my $av = $ex eq 'dieD' ? \$mkobj->('V', 1) : 20;
            $do_local->($av);
            SS::boundary();
            $p2 = $site_addr->();
            SS::boundary();
            if ($mu eq 'preref') { SS::cell_set($prerefcell, 77); SS::boundary() }
            elsif ($mu eq 'clear') { ($s =~ /^ae/ ? SS::av_clear($avid) : SS::hv_clear($hvid)); SS::boundary() }
            elsif ($mu eq 'del') { ($s =~ /^ae/ ? SS::av_delete($avid, 1) : SS::hv_delete($hvid, 'k')); SS::boundary() }
            if ($ex eq 'dieB') { die "B\n" }
            elsif ($ex eq 'dieS') { $SS::ARMDIE = 1 }
        }
        else {
            $do_local->(20);
            SS::boundary();
            my $pobj = $mkobj->('P', 0);
            my $pc = SS::new_cell(); $SS::CELL{$pc}{v} = ['RV', SS::rc_inc($pobj)];
            $padslot = \$pc;
            SS::save_clearsv($padslot);
            SS::boundary();
            {
                my $b2 = @SS::SS;
                if ($s eq 'glob') {
                    SS::save_gp('x', 1);
                    my $slot = SS::glob_svslot('x');
                    my $ref = ${ SS::glob_svslot('y') };
                    SS::rc_dec($$slot); $$slot = SS::rc_inc($ref);
                }
                else {
                    my $slotref2 = $s eq 'pkg'
                        ? do { SS::local_pkg_scalar('x'); SS::glob_svslot('x') }
                        : $s =~ /^ae/ ? SS::local_aelem($avid, $idx, 1)
                        : SS::local_helem($hvid, $key, 1);
                    SS::cell_set($$slotref2, 30);
                }
                SS::boundary();
                SS::leave_scope($b2);
                die $SS::PENDING if defined $SS::PENDING;
            }
            SS::boundary();
            $p2 = $site_addr->();
            SS::boundary();
            if ($ex eq 'dieB') { die "B\n" }
        }
    };
    $bodyerr = $@;
    $SS::PENDING = undef;
    SS::leave_scope($base);
    $e1 = fmte(defined $SS::PENDING ? $SS::PENDING : $bodyerr);
    eval { SS::boundary() };
    $e2 = fmte($@);
    my $exv = $exists_q->();
    my $fvr = $site_read->();
    my $fv = SS::vv($fvr);
    $p3 = ($s !~ /A$/ || $exv) ? $site_addr->() : '-';
    return norm_ids(join('|', 'T=' . join(',', @SS::TRACE), "I=$p1:$p2:$p3",
        "F=$fv", "X=$exv", "Q=$e1/$e2"));
}

sub replay_struct {
    my ($c) = @_;
    my ($s, $m, $mu, $ex) = @$c{qw(s m mu ex)};
    SS::reset_world();
    my $idx = $s eq 'aeP' ? 1 : 5;
    my $avid = SS::new_av();
    my $mkval = sub { my $c2 = SS::new_cell(); $SS::CELL{$c2}{v} = $_[0]; $c2 };
    $SS::AV{$avid}{elems} = [ map { $mkval->($_) } 10, 20, 30 ];
    my $elems = sub { $SS::AV{$avid}{elems} };
    my ($p1, $p2) = ('-', '-');
    $p1 = $elems->()[$idx] if $s eq 'aeP';
    my ($r1, $r2);
    my $base = @SS::SS;
    $SS::PENDING = undef;

    # A removing operation's result is mortal (pp_shift, pp_pop, pp_splice
    # in list context); the reference taken to it holds a count of its
    # own, and the mortal count goes at the statement boundary.
    my $take = sub { my ($cell) = @_; $r2 = defined $cell ? SS::rc_inc($cell) : undef };
    eval {
        my $slotref = SS::local_aelem($avid, $idx, $m ne 'bare');
        SS::cell_set($$slotref, 50) if $m eq 'assign';
        SS::boundary();
        $p2 = $elems->()[$idx];
        SS::boundary();
        $r1 = SS::rc_inc($elems->()[$idx]);
        SS::boundary();
        if ($mu eq 'keep') { }
        elsif ($mu eq 'shift1') { $take->(SS::mortal(SS::av_shift($avid))); SS::boundary() }
        elsif ($mu eq 'shift2') {
            SS::mortal(SS::av_shift($avid)); SS::boundary();
            $take->(SS::mortal(SS::av_shift($avid))); SS::boundary();
        }
        elsif ($mu eq 'unshift1') {
            SS::av_unshift($avid, 1);
            $elems->()[0] = $mkval->(7);
            SS::boundary();
        }
        elsif ($mu eq 'pop1') { $take->(SS::mortal(SS::av_pop($avid))); SS::boundary() }
        elsif ($mu eq 'push1') { SS::av_push($avid, $mkval->(7)); SS::boundary() }
        elsif ($mu eq 'splice_rm') { $take->((SS::av_splice($avid, 'list', 0, 1))[0]); SS::boundary() }
        elsif ($mu eq 'splice_ins') { SS::av_splice($avid, 'scalar', 0, 0, $mkval->(7)); SS::boundary() }
        elsif ($mu eq 'fill_neg1') { SS::av_fill($avid, -1); SS::boundary() }
        elsif ($mu eq 'fill0') { SS::av_fill($avid, 0); SS::boundary() }
        elsif ($mu eq 'refill') {

            # pp_aassign to an array: av_clear, then a fresh copy of each
            # right-hand value stored in order.
            SS::av_clear($avid);
            push @{ $elems->() }, $mkval->(7), $mkval->(8);
            SS::boundary();
        }
        die "B\n" if $ex eq 'dieB';
    };
    my $bodyerr = $@;
    $SS::PENDING = undef;
    SS::leave_scope($base);
    my $e1 = fmte(defined $SS::PENDING ? $SS::PENDING : $bodyerr);
    eval { SS::boundary() };
    my $e2 = fmte($@);
    my $e = $elems->();
    my @X = map { $_ <= $#$e && defined $e->[$_] ? 1 : 0 } 0 .. $STRUCT_TOP;
    my @I = map { $X[$_] ? $e->[$_] : '-' } 0 .. $STRUCT_TOP;
    my @F = map { $X[$_] ? SS::vv(SS::cell_get($e->[$_])) : '-' } 0 .. $STRUCT_TOP;
    my @R = map { defined $_ ? $_ : '-' } $r1, $r2;
    my @V = map { defined $_ ? SS::vv(SS::cell_get($_)) : '-' } $r1, $r2;
    return norm_ids(join('|', 'T=' . join(',', @SS::TRACE),
        'I=' . join(':', $p1, $p2, @I, @R), 'F=' . join(',', @F),
        'X=' . join('', @X), 'N=' . $#$e, 'E=' . join(',', @V), "Q=$e1/$e2"));
}

# ---------------- drive ----------------
my ($n, $ok, $bad, $crash) = (0, 0, 0, 0);
my @report;
open my $tab, '>', ($ENV{TABLE} || '/dev/null') or die $!;
for my $c (@cells) {
    my $key = join('/', @$c{qw(k s m mu ex)}, "d$c->{d}");
    my $code = $c->{st} ? render_struct_child($c) : render_child($c);
    open my $fh, '>', "$WORK/ss_child.pl" or die $!;
    print $fh $code; close $fh;
    my $out = `timeout 5 $PERL $WORK/ss_child.pl 2>/dev/null`;
    my $st = $?;
    $n++;
    if ($st & 127 || ($st >> 8) >= 124 || $out !~ /\S/) {
        $crash++; push @report, "CRASH $key (status $st)";
        print $tab "$key\tCRASH\tCRASH\n";
        next;
    }
    chomp $out; $out = norm_ids($out);
    my $mod = eval { $c->{st} ? replay_struct($c) : replay($c) };
    $mod = "REPLAY-DIED: " . fmte($@) unless defined $mod;
    if ($c->{k} eq 'tied' && $c->{s} ne 'pkg') {
        $_ =~ s/I=[^|]*/I=masked/ for $out, $mod;
    }
    print $tab "$key\t$out\t$mod\n";
    if ($out eq $mod) { $ok++ }
    else { $bad++; push @report, "MISMATCH $key\n  perl: $out\n  SS  : $mod" }
}
close $tab;
print "cells=$n ok=$ok mismatch=$bad crash=$crash\n";
print "$_\n" for @report;
