# After a named unary without parentheses, the next token is read as the start of a term.  If it can begin a term, it
# begins the argument; otherwise the operator takes its default operand and the token is read again as an operator.  So
# `*` and `**` begin a glob (`**` is `*main::*`), `%` a hash, `&` a call, `<` a readline or glob (`<=>` is the glob of
# `=`), `/` a pattern, `x` a bareword, and `-` and `+` a unary sign (with an `ambiguous` warning when spaced), while
# `.`, `==`, `=~`, `eq`, `?`, `||`, `..`, `,`, `=` and `->` end the operator.  `=>` quotes the word.  A keyword
# followed by a single `:` at the start of a statement is a label.

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

value("local \$_ = 'AB'; $_") for 'lc . "x"', 'lc =~ /ab/ ? "match" : "no match"', 'lc eq "ab" ? "eq" : "ne"',
    'lc ? "true" : "false"', 'lc || "f"', 'join ",", lc .. "ac"', 'lc , 1', 'lc => 1', 'lc = 1',
    'use strict "refs"; lc->[0]', 'lc * 2', 'lc *x', 'lc % 2', 'lc & 1', 'lc < 1', 'lc - 1', 'lc + 1', 'lc -1',
    'lc **', 'lc ** 2', 'lc <=>', 'lc <=> 1', 'lc < 1 >', 'lc x', 'lc x 2';
value("local \@ARGV = (5); $_") for 'shift == 5 ? "eq" : "ne"', 'shift . "x"', 'shift + 1', 'shift % 2', 'shift * 2',
    'shift < 6', 'shift / 5';
value("local \$_ = '/nonexistent/perl-conformance'; $_") for '-f == 1 ? "eq" : "ne"', '-f . "x"', '-f * 2';
value('lc: 1');
