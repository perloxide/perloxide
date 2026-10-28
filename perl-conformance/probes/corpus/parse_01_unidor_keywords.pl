# After a keyword whose toke.c case is UNIDOR (getc pop pos readline readlink readpipe shift umask undef) and after a
# file test (FTST), `//` and `//=` are the defined-or operators and `~~` is smartmatch; after any other named unary,
# `//` begins an empty pattern and `~~` two complements.  A `//` with nothing after it is a syntax error.

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

parse("$_ // 0") for qw(getc pop pos readline readlink readpipe shift umask undef);
parse("-$_ // 0") for qw(r w x o R W X O e z s f d l p S u g k b c t T B M A C);
parse("$_ // 0") for qw(lc chr ref stat);
parse($_) for 'shift //= 0', 'lc //= 0', 'shift //', 'shift //;';
value('local @ARGV = (undef); shift // "D"');
value('local @ARGV = (0); shift // "D"');
value('local $_ = "/nonexistent/perl-conformance"; -e // "D"');
value('local @ARGV = ("x"); my @a = ("x"); shift ~~ @a ? "smartmatch" : "no match"');
value('local $_ = "X"; my @a = (7); lc ~~ @a');
value('no feature "smartmatch"; local @ARGV = ("x"); my @a = ("x"); shift ~~ @a');
