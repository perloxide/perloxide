#!/usr/bin/env perl
use strict;
use warnings;
use Scalar::Util qw(refaddr isweak weaken dualvar isvstring);
use JSON::PP ();
my $json = JSON::PP->new->canonical;
our (@log, $w, $x, $left, $right, $root, $local_tied, $saved, $store_policy);

sub emit { my ($name,$v) = @_; print $json->encode({name=>$name,perl=>"$^V",%$v}),"\n" }
sub val { defined $_[0] ? ref($_[0]) || "$_[0]" : 'undef' }

for my $h (qw(replace replace_numify_add replace_numify_nv replace_fraction_numify)) {
    local $w = '12x';
    local $SIG{__WARN__} = sub {
        $w = $h eq 'replace_fraction_numify' ? '99.5' : '99';
        if ($h eq 'replace_numify_add' || $h eq 'replace_fraction_numify') { my $z=$w+0 }
        if ($h eq 'replace_numify_nv') { my $z=sprintf '%.17g',$w }
    };
    my $n = 0 + $w;
    emit("warn.$h", {trace=>"$w:$n:".(0+$w)});
}
{
    local $w = '12x';
    local $SIG{__WARN__} = sub { $w='99' };
    my $n = sprintf '%.17g',$w;
    emit('warn.direct_nv', {trace=>"$w:$n:".(0+$w)});
}

{
    package SimpleTie;
    sub TIESCALAR { bless {value=>$_[1],callback=>$_[2]}, $_[0] }
    sub FETCH {
        my ($s)=@_;
        my $ret=$s->{value};
        push @main::log, 'FETCH('.main::val($ret).')';
        $s->{callback}->($s) if $s->{callback};
        return $ret;
    }
    sub STORE { push @main::log, 'STORE('.main::val($_[1]).')'; $_[0]{value}=$_[1] }
    sub UNTIE { push @main::log, 'UNTIE' }
    sub DESTROY { push @main::log, 'DESTROY(tie)' }
}
for my $a (qw(replace untie retie die)) {
    @log=();
    local $x;
    tie $x,'SimpleTie','12x',sub {
        if($a eq 'replace') { $x='99' }
        if($a eq 'untie') { untie $x }
        if($a eq 'retie') { tie $x,'SimpleTie','77',undef }
        if($a eq 'die') { die "FETCH_DIED\n" }
    };
    local $SIG{__WARN__}=sub { push @log,'WARN' };
    my $r;
    eval { $r=0+$x; 1 };
    my $e="$@";
    my @trace=@log;
    emit("fetch.$a",{result=>$r,error=>$e,trace=>\@trace});
}

{
    package Stringifier;
    use overload '""'=>sub { $_[0]{callback}->() }, fallback=>1;
    sub DESTROY { push @main::log,'DESTROY(object)' }
}
for my $target (qw(fresh inplace right_alias)) {
    @log=();
    local $right='before';
    local $left=bless {callback=>sub {
        push @log,'STRINGIFY';
        $right='after';
        return 'LEFT';
    }}, 'Stringifier';
    my $r;
    if($target eq 'fresh') { $r=$left.$right }
    if($target eq 'inplace') { $left.=$right; $r=$left }
    if($target eq 'right_alias') { $right=$left.$right; $r=$right }
    emit("concat.$target",{result=>$r,right=>$right,trace=>[@log]});
}
{
    @log=();
    local $x=bless {callback=>sub { push @log,'STRINGIFY'; $x='NEW'; return 'OLD' }},'Stringifier';
    my $suffix=':tail';
    my $r=$x.$suffix;
    emit('concat.replace_operand',{result=>$r,after=>$x,trace=>[@log]});
}
{
    @log=();
    local $x=bless {callback=>sub { push @log,'STRINGIFY'; $x='NEW'; return "\x{100}" }},'Stringifier';
    my $suffix=':tail';
    my $r=$x.$suffix;
    emit('concat.replacement_utf8_flag',{first_codepoint=>ord($r),after=>$x,
        after_utf8=>utf8::is_utf8($x)?1:0,trace=>[@log]});
}

{
    my %h;
    my $r=$h{a}{b};
    emit('vivify.plain',{a_exists=>exists($h{a})?1:0,b_exists=>exists($h{a}{b})?1:0,result=>val($r)});
}
{
    package VivifyTie;
    sub TIESCALAR { bless {value=>undef,policy=>$_[1]},$_[0] }
    sub FETCH { push @main::log,'FETCH('.main::val($_[0]{value}).')'; return $_[0]{value} }
    sub STORE {
        my($s,$v)=@_;
        push @main::log,'STORE('.main::val($v).')';
        $main::saved=$v;
        $s->{value}=$v;
        $s->{value}={b=>'replacement'} if $s->{policy} eq 'replace';
        die "STORE_DIED\n" if $s->{policy} eq 'die';
    }
}
for my $policy(qw(keep replace die)) {
    @log=(); $saved=undef;
    local $root;
    tie $root,'VivifyTie',$policy;
    my $r;
    eval { $r=$root->{b}; 1 };
    my $e="$@";
    emit("vivify.tied.$policy",{result=>val($r),error=>$e,trace=>[@log],
        allocated_b_exists=>defined($saved)&&exists($saved->{b})?1:0});
}
{
    my %h;
    my @e;
    my $key=sub {push @e,exists($h{a})?'parent-present':'parent-absent';die "KEY_DIED\n"};
    eval { my $r=$h{a}{$key->()} };
    emit('vivify.later_key_dies',{error=>"$@",trace=>\@e,a_exists=>exists($h{a})?1:0});
}

for my $action(qw(bare assign self saved_alias)) {
    @log=();
    local $local_tied;
    tie $local_tied,'SimpleTie','old',undef;
    my $old=\$local_tied;
    if($action eq 'bare') { local $local_tied; push @log,'BODY' }
    elsif($action eq 'assign') { local $local_tied='new'; push @log,'BODY' }
    elsif($action eq 'self') { local $local_tied=$local_tied; push @log,'BODY' }
    else { local $local_tied='new'; $$old='changed-old'; push @log,'BODY' }
    emit("local.tied.$action",{trace=>[@log],after=>"$local_tied"});
}

{
    my %h=(k=>'base'); my $old=\$h{k}; my $inner;
    my @states;
    {
        local $h{k}='local'; $inner=\$h{k};
        push @states,[$$old,$h{k},refaddr($old)==refaddr($inner)?1:0];
        delete $h{k};
        push @states,[exists($h{k})?1:0,$$inner,$$old];
        $h{k}='recreated';
        push @states,[$h{k},$$inner,refaddr(\$h{k})==refaddr($inner)?1:0];
        $$old='base-mutated';
    }
    emit('local.element.identity',{states=>\@states,after=>$h{k},restored=>refaddr(\$h{k})==refaddr($old)?1:0,escaped=>$$inner});
}
{
    my %h;
    { local $h{k}; emit('local.absent.enter',{exists=>exists($h{k})?1:0,defined=>defined($h{k})?1:0,keys=>[keys %h]}) }
    emit('local.absent.exit',{exists=>exists($h{k})?1:0});
}
{
    my %h=(k=>'base'); my $r=\$h{k};
    { delete local $h{k}; emit('delete_local.inside',{exists=>exists($h{k})?1:0,old=>$$r}) }
    emit('delete_local.exit',{value=>$h{k},same=>refaddr(\$h{k})==refaddr($r)?1:0});
}
{
    my @a=(10,20); my $r=\$a[0]; @a=(30,40);
    emit('array.assignment.detaches',{old=>$$r,current=>$a[0],same=>refaddr($r)==refaddr(\$a[0])?1:0});
}
{
    my $n=9223372036854775807; $n+=1;
    my $d=dualvar(7,'0');
    my $owner={}; my $weak=$owner; weaken($weak); my $copy=$weak;
    emit('constraints',{ivmax_plus_1=>"$n",dualvar_truth=>$d?1:0,original_weak=>isweak($weak)?1:0,copy_weak=>isweak($copy)?1:0});
}
{
    my $v=v1.2.3; my $copy=$v; my $written=$v; $written.='';
    emit('vstring.copy_and_write',{original=>isvstring($v)?1:0,copy=>isvstring($copy)?1:0,empty_append=>isvstring($written)?1:0});
}
