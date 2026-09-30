#!/usr/bin/env perl
use strict;
use warnings;
use B ();
use Scalar::Util qw(blessed isweak refaddr weaken);
use JSON::PP ();
use POSIX ();
use Config ();

# Each generated case runs in a fresh child: malformed reentry can make the
# reference interpreter crash. No value is inspected through FETCH/overload
# until after the first result and raw SV state have been captured.
our ($x, $action, $busy, $observing, $keeper, $mode);
our @events;
my $json = JSON::PP->new->canonical->allow_nonref;
my @inputs = (
    ['zero_true', sub { '0 but true' }], ['space12', sub { ' 12' }],
    ['junk12', sub { '12x' }], ['exp1e5', sub { '1e5' }],
    ['hextext', sub { '0x10' }], ['inf', sub { 'inf' }],
    ['nan', sub { 'nan' }], ['ivmax', sub { 9223372036854775807 }],
    ['uvmax', sub { 18446744073709551615 }], ['minuszero', sub { '-0' }],
    ['empty', sub { '' }], ['undef', sub { undef }],
    ['ivmax_text', sub { '9223372036854775807' }],
    ['uvmax_text', sub { '18446744073709551615' }],
    ['zero_num', sub { 0 }], ['twelve_num', sub { 12 }],
    ['fraction_num', sub { 12.5 }], ['fraction_junk', sub { '12.5x' }],
);
my @actions = qw(none replace99 replace_bad replace_num replace_float
    numify_current numify_current_nv replace99_numify replace99_numify_iv
    replace99_numify_nv replace_fraction_numify replace_fraction_numify_nv
    bless_cell bless_ref weaken_ref localize tie untie die);
my @ops = qw(add iv nv concat stringify);

sub snapshot {
    my ($r) = @_;
    my $b = B::svref_2object($r);
    my $f = $b->FLAGS;
    my %s = (svtype => ref($b), flags => sprintf('%08x', $f));
    $s{pv} = $b->PV if $f & B::SVp_POK();
    if ($f & B::SVp_IOK()) {
        $s{iv} = '' . $b->IVX;
        $s{uv} = '' . $b->UVX if ($f & B::SVf_IVisUV()) && !($f & B::SVf_ROK());
    }
    $s{nv} = sprintf('%.17g', $b->NVX) if $f & B::SVp_NOK();
    $s{nv_slot} = sprintf('%.17g', $b->NVX) if ref($b) =~ /^B::(?:PVNV|PVMG)$/;
    $s{rok} = ($f & B::SVf_ROK()) ? 1 : 0;
    # SVprv_WEAKREF in sv.h for both tested builds; B does not export it.
    $s{weak} = ($f & 0x80000000) ? 1 : 0 if $f & B::SVf_ROK();
    # Do not call tied(), ref($$r), or stringify the value to inspect it.
    return \%s;
}

sub iv { use integer; return 0 + $_[0] }
sub nv { return sprintf('%.17g', $_[0]) }
sub operation {
    my ($op) = @_;
    return 0 + $x if $op eq 'add';
    return iv($x) if $op eq 'iv';
    return nv($x) if $op eq 'nv';
    my $tail = ':tail';
    return $x . $tail if $op eq 'concat';
    return "$x" if $op eq 'stringify';
    die "unknown op $op";
}

sub mutate {
    return if $busy || $observing;
    local $busy = 1;
    push @events, {event => 'handler.enter', state => snapshot(\$x)};
    if ($action eq 'none') { }
    elsif ($action eq 'replace99') { $x = '99' }
    elsif ($action eq 'replace_bad') { $x = '99y' }
    elsif ($action eq 'replace_num') { $x = 99 }
    elsif ($action eq 'replace_float') { $x = 99.5 }
    elsif ($action eq 'numify_current') { my $z = $x + 0; push @events, {event=>'nested', value=>"$z"} }
    elsif ($action eq 'numify_current_nv') { my $z = nv($x); push @events, {event=>'nested', value=>"$z"} }
    elsif ($action eq 'replace99_numify') { $x = '99'; my $z = $x + 0; push @events, {event=>'nested',value=>"$z"} }
    elsif ($action eq 'replace99_numify_iv') { $x = '99'; my $z = iv($x); push @events, {event=>'nested',value=>"$z"} }
    elsif ($action eq 'replace99_numify_nv') { $x = '99'; my $z = nv($x); push @events, {event=>'nested',value=>"$z"} }
    elsif ($action eq 'replace_fraction_numify') { $x = '99.5'; my $z = $x + 0; push @events, {event=>'nested',value=>"$z"} }
    elsif ($action eq 'replace_fraction_numify_nv') { $x = '99.5'; my $z = nv($x); push @events, {event=>'nested',value=>"$z"} }
    elsif ($action eq 'bless_cell') { bless \$x, 'Reentry::Cell' }
    elsif ($action eq 'bless_ref') { $x = bless {}, 'Reentry::Object' }
    elsif ($action eq 'weaken_ref') { $keeper = {}; $x = $keeper; weaken($x) }
    elsif ($action eq 'localize') { local $x = '99'; push @events, {event=>'local.body', state=>snapshot(\$x)} }
    elsif ($action eq 'tie') { tie $x, 'Reentry::Tie', sub { '77' }, 0 }
    elsif ($action eq 'untie') { untie $x }
    elsif ($action eq 'die') { die "HANDLER_DIED\n" }
    else { die "unknown action $action" }
    push @events, {event => 'handler.leave', state => snapshot(\$x)};
}

{
    package Reentry::Tie;
    sub TIESCALAR { my ($c,$factory,$active) = @_; bless {value=>$factory->(), active=>$active}, $c }
    sub FETCH {
        my ($self) = @_;
        my $ret = $self->{value};
        push @main::events, {event=>'FETCH.enter', value=>main::snapshot(\$ret)};
        main::mutate() if $self->{active};
        push @main::events, {event=>'FETCH.return', value=>main::snapshot(\$ret)};
        return $ret;
    }
    sub STORE {
        my ($self,$v) = @_;
        push @main::events, {event=>'STORE', value=>main::snapshot(\$v)};
        $self->{value} = $v;
    }
    sub UNTIE { push @main::events, {event=>'UNTIE'} }
    sub DESTROY { push @main::events, {event=>'tie.DESTROY'} }
}
{
    package Reentry::Overload;
    use overload '""' => \&stringify, fallback => 1;
    sub stringify {
        my ($self) = @_;
        my $ret = $self->{value};
        push @main::events, {event=>'overload.enter', value=>main::snapshot(\$ret)};
        main::mutate();
        push @main::events, {event=>'overload.return', value=>main::snapshot(\$ret)};
        return $ret;
    }
    sub DESTROY { push @main::events, {event=>'overload.DESTROY'} }
}

sub run_case {
    my ($m, $input, $a, $op) = @_;
    $mode = $m; $action = $a; $busy = $observing = 0; @events = ();
    my ($label,$factory) = @$input;
    $x = $factory->();
    tie $x, 'Reentry::Tie', $factory, ($m eq 'fetch' ? 1 : 0) if $m eq 'fetch' || $m eq 'warn_tied';
    $x = bless {value=>$factory->()}, 'Reentry::Overload' if $m eq 'overload';
    my $initial = snapshot(\$x);
    local $SIG{__WARN__} = sub {
        push @events, {event=>'WARN', message=>$_[0]};
        mutate() if $m eq 'warn' || $m eq 'warn_tied';
    };
    my ($result, $error);
    my $ok = eval { $result = operation($op); 1 };
    $error = "$@" unless $ok;
    my $post = snapshot(\$x);
    my @primary = @events;
    # Observe continued behavior only after raw post-operation state is saved.
    $observing = 1; @events = ();
    my ($text,$next,$observer_error);
    eval { $text = "$x"; $next = 0 + $x; 1 } or $observer_error = "$@";
    return {
        mode=>$m, input=>$label, action=>$a, op=>$op,
        initial=>$initial, ok=>$ok ? 1 : 0, error=>$error,
        result=>defined($result) ? "$result" : undef,
        post=>$post, events=>\@primary,
        observed=>{text=>$text, next=>defined($next) ? "$next" : undef,
                   error=>$observer_error, events=>[@events], state=>snapshot(\$x)},
    };
}

my @selected = @ARGV;
print $json->encode({metadata=>{perl=>"$^V", arch=>$Config::Config{archname},
    ivsize=>$Config::Config{ivsize}, nvtype=>$Config::Config{nvtype},
    input_count=>scalar @inputs, action_count=>scalar @actions, ops=>\@ops}}), "\n";
for my $m (qw(warn fetch overload warn_tied)) {
    next if @selected && $selected[0] ne $m;
    for my $input (@inputs) {
        next if @selected > 1 && $selected[1] ne $input->[0];
        for my $a (@actions) {
            next if @selected > 2 && $selected[2] ne $a;
            for my $op (@ops) {
                next if @selected > 3 && $selected[3] ne $op;
                pipe(my $read, my $write) or die "pipe: $!";
                my $pid = fork();
                die "fork: $!" unless defined $pid;
                if (!$pid) {
                    close $read;
                    alarm 3;
                    my $stderr = '';
                    local *STDERR;
                    open STDERR, '>', \$stderr or die "capture stderr: $!";
                    my $r = eval { run_case($m,$input,$a,$op) };
                    $r //= {mode=>$m,input=>$input->[0],action=>$a,op=>$op,harness_error=>"$@"};
                    $r->{stderr} = $stderr;
                    print {$write} $json->encode($r), "\n";
                    close $write;
                    POSIX::_exit(0);
                }
                close $write;
                my $out = do { local $/; <$read> };
                close $read;
                waitpid($pid,0);
                if ($? || !length($out // '')) {
                    print $json->encode({mode=>$m,input=>$input->[0],action=>$a,op=>$op,
                        child_status=>$?,partial=>$out}), "\n";
                } else { print $out }
            }
        }
    }
}
