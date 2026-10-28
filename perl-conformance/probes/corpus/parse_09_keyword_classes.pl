# A keyword's syntactic class is the macro its case uses in toke.c's yyl_word_or_keyword, not its prototype or its
# entry in perlfunc.  `keys`, `values`, `each`, `tell`, `untie` and `write` are named unaries (UNI): a comma or a
# comparison after the operand ends the operator.  `die`, `warn` and `getprotobynumber` are list operators (LOP): they
# take every comma-separated argument, so `getprotobynumber` with two fails its argument count even though its
# prototype is `$;`.

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

parse($_) for 'my %h; my @x = (keys %h, 1)', 'my %h; my @x = (values %h, 1)', 'my %h; my @x = (each %h, 1)',
    'my $f; my @x = (tell $f, 1)', 'my %h; my @x = (untie %h, 1)', 'my $f; my @x = (write $f, 1)',
    'my @x = (getprotobyname "tcp", 1)', 'my @x = (getprotobynumber 6, 1)';
value('my %h = (a => 1, b => 2); keys %h < 3 ? "unary" : "list"');
value('eval { die "a", "b" }; $@');
value('my $w; local $SIG{__WARN__} = sub { $w = shift }; warn "a", "b\n"; $w');
value('CORE::prototype("CORE::getprotobynumber")');
