# The condition of a block `while`, and the middle test of a C-style `for`, may be empty, and an empty one is true, so
# both loops run until left (perly.y's `texpr`).  The statement modifiers take an ordinary expression, so in `STMT while
# ();` the condition is the empty list, which is false.  The conditions of block `if`, `unless`, `elsif` and `until` are
# required, and an empty one is a syntax error.

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

value($_) for 'my $n = 0; while () { last if ++$n == 3 } $n', 'my $n = 0; for (;;) { last if ++$n == 4 } $n',
    'my $n = 0; for (my $i = 0; ; $i++) { last if ++$n == 2 } $n';
value($_) for 'my $c = 0; $c++ while (); $c', 'my $c = 0; $c++ if (); $c', 'my $c = 0; $c++ unless (); $c';
value($_) for 'if () { 1 }', 'unless () { 1 }', 'if (1) { 1 } elsif () { 2 }', 'until () { 1 }';
