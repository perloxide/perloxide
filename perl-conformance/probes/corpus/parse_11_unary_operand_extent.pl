# The operand of a named unary without parentheses, of a file test, and of `stat` or `lstat` extends over every operator
# that binds more tightly than a named unary (`%nonassoc UNIOP` in perly.y: shift, additive, multiplicative, binding,
# prefix unary, `**`, `++`, `--` and `->`) and ends before relational and looser operators.  A named unary, `stat`
# included, followed by `(` directly, after whitespace, or after a comment and a newline, is a call whose operand ends
# at the `)`.  A file test has no call form: a `(` after it begins its operand, which continues past the `)`.  A file
# test whose operand is another file test stacks: `-e -e "."` is `-e "." && -e _`.  Each case runs in the probe's
# directory, where `.` exists and `./nonexistent` does not.

# Every case is a string eval run with Perl's default warnings (no `use warnings`, no `use strict`).  A `value` case is
# run, and its line reads the list it returned or the error.  A `parse` case, used where running the code would have an
# effect outside the probe, is compiled as `return 1; CODE`, which returns before any of CODE runs; its line reads
# `compiles` or the error, whose `near` text can include that prefix.  Warnings follow their case in order, and a
# newline inside a case or a message is printed as `\n`.  `$_` is undefined and `@ARGV` is empty unless a case sets
# them.
my @warnings;
$SIG{__WARN__} = sub { push @warnings, $_[0] };
sub show { my ($s) = @_; $s =~ s/\n\z//; $s =~ s/\n/\\n/g; $s }
sub report {
    my ($kind, $code, $result) = @_;
    print "$kind: ", show($code), "\n    $result\n";
    print "    warning: ", show($_), "\n" for @warnings;
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

value($_) for 'lc "A" . "B"', 'lc("A") . "B"', 'lc ("A") . "B"', qq{lc # comment\n("A") . "B"},
    'lc "A" eq "a" ? "lc first" : "eq first"';
value($_) for '-e "." . "/nonexistent"', '-e "." + 0', '-e "." eq 1 ? "test first" : "eq first"',
    '-e(".") . "/nonexistent"', '-e (".") . "/nonexistent"', '-e -e "."';
value($_) for 'my @r = (stat "." . "/"); scalar @r', 'stat(".") . "/"', qq{stat # comment\n(".") . "/"},
    'my @r = (lstat "." . "/"); scalar @r', 'lstat(".") . "/"';
