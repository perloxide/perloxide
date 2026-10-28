# `CORE::NAME` names the built-in for every keyword NAME: it ignores overriding subs and feature gating, keeps the
# keyword's own syntax (UNIDOR included), and is not autoquoted before `=>` or as a hash subscript.  `CORE::`
# followed by anything that is not a keyword is an error, except a further package name (`CORE::GLOBAL::shift`,
# `CORE::A::B`), which is an ordinary name.  Bare `dump` is an error that names `CORE::dump`.

# Every case is a string eval run with Perl's default warnings (no `use warnings`, no `use strict`).  A `value` case is
# run, and its line reads the list it returned or the error.  A `parse` case, used where running the code would have an
# effect outside the probe, is compiled as `return 1; CODE`, which returns before any of CODE runs; its line reads
# `compiles` or the error, whose `near` text can include that prefix.  Warnings follow their case in order, and a
# newline inside a message is printed as `\n`.  `$_` is undefined and `@ARGV` is empty unless a case sets them.
my @warnings;
$SIG{__WARN__} = sub { push @warnings, $_[0] };
sub show { my ($s) = @_; $s =~ s/\n\z//; $s =~ s/\n/\\n/g; $s }
sub report {
    my ($kind, $code, $result) = @_;
    print "$kind: $code\n    $result\n";
    print "    warning: ", show($_), "\n" for @warnings;
}
sub parse {
    my ($code) = @_;
    local $_;
    @warnings = ();
    my $ok = eval "return 1; $code";
    report('parse', $code, $ok ? 'compiles' : 'error: ' . show($@));
}
sub value {
    my ($code) = @_;
    local $_;
    @warnings = ();
    my @v = eval $code;
    my $err = $@;
    report('value', $code, $err ne '' ? 'error: ' . show($err)
        : '(' . join(', ', map { defined $_ ? "'" . show($_) . "'" : 'undef' } @v) . ')');
}

value('local @ARGV = (undef); CORE::shift // "D"');
parse('CORE::readpipe // 0');
value($_) for 'CORE::stat // 0', 'CORE::nosuch', 'CORE:: shift', 'CORE::GLOBAL::shift', 'CORE::A::B', 'CORE::x 3',
    'CORE::and';
parse($_) for 'CORE::dump', 'dump', 'say 1', 'CORE::say 1';
value('local @ARGV = ("k"); my %h = (CORE::shift => 1); keys %h');
value('local @ARGV = ("k"); my %h = (shift => 1); keys %h');
value('local @ARGV = ("k"); my %h; $h{CORE::shift} = 1; keys %h');
value('local @ARGV = ("k"); my %h; $h{shift} = 1; keys %h');
value('CORE::q(x)');
value('package C1; use subs "lc"; sub lc { "mine" } lc("A")');
value('package C2; use subs "lc"; sub lc { "mine" } CORE::lc("A")');
