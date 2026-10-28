# A hyphen followed by a single letter that is not followed by a word character is a file test only for the 27 letters
# in toke.c's yyl_hyphen (r w x o R W X O e z s f d l p S u g k b c t T B M A C).  For any other letter it is a unary
# minus applied to the word that follows: a bareword gives the string `-j`, after which `//` is defined-or; a declared
# sub is called and its result negated, after which `//` begins a pattern; and a quote-like operator (`m`, `q`, `y`)
# starts quoting.  Each letter runs with `$_` naming a file that does not exist; stdin is /dev/null.

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

value("local \$_ = '/nonexistent/perl-conformance'; -$_") for 'a' .. 'z', 'A' .. 'Z';
value($_) for '-j // 0', '-j//0', 'package F1; sub j { 5 } -j', 'package F2; sub j { 5 } -j // 0';
