# The call form of `shift` and `pop` accepts any expression between the parentheses (`FUNC1 ( expr )` in perly.y), and
# without parentheses any term; the op check then requires the operand to be an array.  Parentheses around an
# expression make no op, so `shift((@a))` and `shift((@a),)` take `@a` itself, while an empty list, a conditional, a
# list of two arrays, an assignment or an element is not an array and fails, as do a hash and a glob with their own
# message.

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

value("my \@a = (1, 2); $_") for 'shift(@a)', 'shift((@a))', 'shift(((@a)))', 'shift((@a),)', 'shift @a', 'pop((@a))',
    'my $r = \@a; shift(@$r)', 'my $r = \@a; shift($r->@*)', 'shift(@{[7]})', 'shift(my @b)', 'shift(())',
    'shift(($_ ? @a : @b))', 'shift($_ ? @a : @b)', 'shift @a ? "true" : "false"', 'shift(@a, @b)', 'shift(@a = (1))',
    'shift(@a[0])', 'shift(%h)', 'shift(*a)', 'shift(1)';
