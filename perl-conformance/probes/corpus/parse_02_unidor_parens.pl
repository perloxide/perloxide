# A named unary followed by `(` (after any whitespace) is the call form, `NAME ( )` or `NAME ( expr )`; a file test
# followed by `(` takes a parenthesized term.  The expectation after the operator carries through each `(`, so after a
# UNIDOR keyword or a file test a `//` or `~~` inside the parentheses is an operator with no left operand, a syntax
# error, while after any other named unary it begins a pattern.

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

value($_) for 'shift()', 'pop()', 'lc()', 'shift(//)', 'shift (//)', 'shift((//))', 'pos(//)', 'undef(//)',
    'shift(~~@a)', '-f(//)', '-f((//))', 'lc(//)', 'lc((//))', 'ref(//)', 'stat(//)';
