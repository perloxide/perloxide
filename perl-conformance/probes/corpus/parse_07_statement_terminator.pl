# An expression statement ends at `;`, or with none where its block closes or the input ends (toke.c supplies a `;`
# token before the `}` that closes a block and at the end of the input).  A term where an operator is expected is a
# syntax error, reported after a warning naming what was found; it never begins a new statement.  An `s///e`
# replacement is compiled as the body of `do { }`, so the same holds inside it.

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

value($_) for '1 2;', '$x $y;', '1 "a";', 'print 1 2;', 'foo 0;', '{1 2}', 'do { 1 } 2', 's/x/1 2/e', '1', '{ 1 }',
    '{ 1 } 2', '1; 2', 'local $_ = "x"; s/x/1/e; $_';
