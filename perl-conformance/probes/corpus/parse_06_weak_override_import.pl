# Which subs override a keyword.  A lexical sub overrides any keyword, strong ones included.  Otherwise a strong keyword
# (`+` in regen/keywords.pl) is never overridden, and a weak one only by a sub imported into the package -- assigned to
# its glob while another package is current, as `use subs` and Exporter do -- or by an imported `CORE::GLOBAL::NAME`.
# A sub merely defined in the package does not override; the call is the built-in, with an `ambiguous` warning when that
# category is enabled.  `lock` is overridden by any sub, `x` by none, and `dump` only by an import.  An overriding sub
# is an ordinary list operator, so `//` after it begins a pattern.  The `CORE::GLOBAL` case runs last, since it affects
# everything compiled after it.

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

value('package O1; use warnings; sub lc { "mine" } lc("A")');
value('package O2; sub lc { "mine" } &lc("A")');
value('package O3; use subs "lc"; sub lc { "mine" } lc("A")');
value('package O4; BEGIN { package Q; *O4::lc = sub { "imported" } } lc("A")');
value('package O5; BEGIN { *O5::lc = sub { "same package" } } lc("A")');
value('package Exp; use Exporter "import"; BEGIN { our @EXPORT = qw(lc defined shift) } '
    . 'sub lc { "exported lc" } sub defined { "exported defined" } sub shift { "exported shift" } 1');
value('package O6; BEGIN { Exp->import } lc("A")');
value('package O7; BEGIN { Exp->import } defined(undef) ? "defined" : "builtin"');
value('package O8; BEGIN { Exp->import } my %h = (lc => 1); keys %h');
value('package O9; BEGIN { Exp->import } local @ARGV = (undef); shift // 0');
value('package O10; my sub lc { "lexical lc" } lc("A")');
value('package O11; my sub print { "lexical print" } print("A")');
value('package O12; my sub defined { "lexical defined" } defined(undef)');
value('package O13; sub lock { "mine" } lock("A")');
value('package O14; use warnings; sub x { "mine" } 2 x 3');
value('package O15; sub dump { "mine" } dump()');
value('package O16; BEGIN { package Q; *O16::dump = sub { "imported dump" } } dump()');
value('package O17; sub CORE::GLOBAL::uc { "global" } uc("a")');
value('package O18; BEGIN { *CORE::GLOBAL::lc = sub { "global" } } lc("A")');
