# Open Work

Open questions, pending design discussions, and coding tasks that are not yet ruled or done.  `design.md` records
rulings; this file records what is still owed.  An item leaves this file when it is ruled (into `design.md`) or done
(into git), and nothing here is a ruling.

## Parser parity with perl

Each coding task below has failing parser tests, verified against perl 5.44.0, that record where the parser accepts,
rejects, or shapes code differently from perl.  Making those tests pass is the work; the design questions it raises are
listed after the tasks.

### Coding tasks

- **Statement ends.**  An expression statement that is not followed by `;`, the `}` that closes its block, or the end of
  the input is a syntax error (`1 2;`, `foo 0;`, `say 1;` without its feature); the end of an `s///e` replacement counts
  as its closing `}` [fact:parsing.statement-terminator].  Today `finish_expr_stmt` accepts the statement unterminated
  and the next term starts a new statement, which also hides most of the other divergences below.
- **Keyword classes.**  Derive each keyword's class from the macro its case uses in `toke.c`'s `yyl_word_or_keyword`
  (`FUN0`, `UNI`, `UNIDOR`, `LOP`, ...) and pin the table with a test.  The predicates in `keyword.rs` disagree for
  `keys`, `values`, `each`, `tell`, `untie` and `write` (`UNI` in `toke.c`, list operators here), for `die`, `warn` and
  `getprotobynumber` (`LOP` in `toke.c`, named unaries here), and `readpipe` (`UNIDOR`) is missing from the
  defined-or-preferring set [fact:parsing.keyword-classes].  The strong/weak split already matches `regen/keywords.pl`
  for all 266 keywords.
- **`undef` takes an argument.**  `undef $x` parses today as `undef; $x;`.
- **Optional-argument unaries.**  Decide whether an argument follows by perl's rule (below) rather than by the list of
  stop tokens in `parse_named_unary`.  This fixes `shift == 1`, `lc . "x"`, `lc =~ /x/`, `lc !~ /x/`, `-f == 1`, `lc ..
  1`, `lc ->[0]` and the like.
- **Unary operand extent.**  The operand of a file test, and of `stat` and `lstat` without parentheses, extends over
  every operator that binds more tightly than a named unary, as a named unary's does (`-s $f . "x"` is `-s($f . "x")`);
  the parser takes it at prefix unary precedence.  A file test has no call form, so `-f($x) . "y"` is `-f(($x) . "y")`
  [fact:parsing.unary-operand-extent].
- **The defined-or preference.**  After the `UNIDOR` keywords and the file tests, `//`, `//=` and (with smartmatch
  enabled) `~~` are operators.  `parse_stat_target_inner` must not see `DefinedOr` at all: `stat` and `lstat` take `//`
  as an empty pattern, and the decision for file tests belongs before argument parsing [fact:parsing.unidor-keywords]
  [fact:parsing.stat-is-uni].
- **Call parentheses.**  `NAME()` is a call with no argument (`shift()`, `lc()` and `eof()` all fail today).  For the
  operators that prefer defined-or, the preference governs the first token inside the parentheses, through any further
  opening parentheses, so `pos(//)`, `shift(~~@a)` and `-f((//))` are syntax errors [fact:parsing.unidor-parens].
- **`lex_term` parity with `XTERM`.**  `//=` in term position is `//` then `=` (`//=~ /x/`); `*`, `%` and `&` begin a
  glob, hash or sub call even after whitespace and with numeric names (`lc * 2` is `lc(*2)`); `**` and `<=>` are globs;
  `<` and `<<` fail with perl's messages (`Unterminated <> operator`, `Use of bare << to mean <<"" is forbidden`)
  [fact:parsing.unary-argument-start].
- **File tests.**  Only perl's 27 letters (`r w x o R W X O e z s f d l p S u g k b c t T B M A C`) make file tests.
  Any other letter is a unary minus applied to the word that follows: the string `-j` for a bareword, a negated call for
  a declared sub, and quoting for `m`, `q` and `y` [fact:parsing.filetest-letters].
- **Labels.**  A keyword followed by a single `:` at statement start is a label (`lc: 1;`)
  [fact:parsing.unary-argument-start].
- **Indirect objects.**  `foo bar` with neither word declared is `bar->foo`; the current heuristic requires a
  capitalized class name.  The exact rules are `S_intuit_method`'s.
- **`CORE::`.**  Add `Token::CoreKeyword(Keyword)` (§5.3), its errors, and `dump` ("dump() must be written as
  CORE::dump() as of Perl 5.30") [fact:parsing.core-prefix].
- **Overrides.**  Record imported subs, the `CORE::GLOBAL` stash and lexical subs in the symbol table, and decide
  overrides by perl's rules (§5.3), including `lock`.  Today any declared sub overrides a weak keyword, and `use subs`
  is recorded as a declaration rather than an import [fact:parsing.weak-override-import].
- **Error messages.**  These tests compare perl's message body ("syntax error", "CORE::nosuch is not a keyword", ...).
- **Test names.**  About 400 of the tests in `parser_tests.rs` carry the prefix `parse_`, which says nothing in a file
  of parser tests.  Name each by its subject instead, as the tests for this work are (`named_unary_*`, `core_*`,

### Perl's rule for whether an optional argument follows

The lexer decides first.  On a named unary (`UNI`, `UNIDOR`) it skips whitespace and comments, and if the next character
is `(` it returns `FUNC1`, the call form: the grammar then requires `FUNC1 ( )` or `FUNC1 ( expr )`.  Any `expr` is
accepted there.  For `shift` and `pop` the op check then requires the operand to be an array op (`rv2av` or `padav`),
which parentheses do not change: `shift((@a))` passes, while `shift(())`, `shift(($x ? @a : @b))` and `shift(@a, @b)`
fail with "Experimental shift on scalar is now forbidden" [fact:parsing.shift-array-argument].  Otherwise the lexer
returns `UNIOP` (file tests always return `UNIOP`).

After `UNIOP` the next token is lexed with `PL_expect` set to `XTERM`, or to `XTERMORDORDOR` for `UNIDOR` and file
tests.  The grammar has `term: UNIOP | UNIOP block | UNIOP term`.  If the token the lexer returned can begin a `term`,
the parser shifts it and parses the argument, which extends over every operator binding more tightly than a named unary
(`%nonassoc UNIOP`).  Otherwise it reduces `UNIOP` alone, with the default operand implied, and the token is whatever
follows a term.  `XTERMORDORDOR` lexes exactly as `XTERM` except that `//` (and `//=`) become the defined-or operator
and, with smartmatch enabled, `~~` becomes the smartmatch operator; none of these can begin a term.  When a `(` follows
`UNIOP` or `FUNC1`, `yyl_leftparen` keeps the expectation in force for the next token, and each further `(` does the
same.  Prototyped subs whose prototype makes them unary (`UNIOPSUB`) follow the `XTERM` rule.
[fact:parsing.unary-argument-start] [fact:parsing.unidor-parens]

In PerlOxide's terms: an argument follows if and only if, after the defined-or check for the operators that prefer it,
`lex_term()` leaves a token that `try_prefix` or `parse_term` accepts.

### Design discussions

- **Optional-argument unaries from first principles.**  How the parser should structure this decision, the call form,
  and argument parsing as an `ExprFrame` instead of recursion, using the rule above.
- **The AST form of `CORE::`.**  How the AST records that a keyword was written `CORE::NAME`.  (B::Deparse does not show
  this: it prints `CORE::` only where its own analysis of the symbol table and features calls for it, so `CORE::print 1`
  deparses as `print 1`.)
- **`NAME()` versus `NAME`.**  Perl builds the two differently (`FUNC1 ( )` sets `OPf_SPECIAL`), and the difference is
  observable for `eof()` versus `eof`.  How the AST records it.
- **Which layer reports op-tree check errors.**  "Can't modify ...", "Too many arguments for ...", "Type of arg 1 to ...
  must be ..." and "Experimental shift on scalar is now forbidden" come from perl's op checks after a successful parse.
  The tests for them accept either the parse or the exact message.
- **Diagnostics beyond the message body.**  The location text (`at FILE line N, near "..."`, `at EOF`, `at end of line`,
  by `yyerror`'s rules), the parser's warnings channel (`Number found where operator expected (...)`, `Use of "NAME"
  without parentheses is ambiguous`, `Ambiguous call resolved as CORE::NAME(), ...`), error recovery and the reporting
  of further errors, and the closing `had compilation errors` and `Execution of ... aborted` lines.
- **`use subs` in a standalone parse.**  Without the interpreter, `use subs` cannot run.  Whether the parser records it
  as an import (as `subs.pm` would make it) or drops the special case.
- **`{` classification.**  How the parser reproduces `yyl_leftcurly` exactly by default (§6.7): the positions where it
  guesses (statement level, the first argument of `map` and `grep`, `print {`, `${ }`, inside `eval ""`), its scan of
  only the current line, the rule that a comma after a lowercase bareword does not mean a hash, and how an improved
  classification is enabled.  The previous AST-based rules are not equivalent to it.
- **Stack depth.**  Perl 5.44.0 parses a million levels of `[`, `-(`, `lc `, `1 ? 1 :` and `$x =` in an 8 MiB stack, and
  100,000 nested blocks.  On a 2 MiB thread the parser overflows at 10,000 levels of named unaries, blocks, ternaries
  and assignments, and the recursive `Drop` overflows for nested containers and negations; the two `depth_*` tests pass
  only with `RUST_MIN_STACK` raised.  The choice is between explicit frames everywhere (iterative `Drop` and AST walks,
  and the remaining recursive-descent paths as `ExprFrame`s) and growing the stack on demand (the `stacker` crate, as
  rustc does).  Derived `Debug`, `Clone` and `PartialEq` are recursive too.  §6.1.4 still calls the OS stack the natural
  limit.
- **`SigDefaultKind::Eq`.**  The signature-default kind for `=` has the same comparison-sounding name the `AssignOp`
  variants had.

### Finding more divergences

- Cross every keyword class with a fixed set of following tokens and compare the parse with perl's mechanically.
- Audit the existing parser tests against perl; each verified fact is also a candidate probe for `perl-conformance/`.

## perl-conformance

- Add probes for the parsing facts above, observed through `eval STRING`, `$@` and `$SIG{__WARN__}` rather than
  `B::Deparse` so any implementation can run them, and a `[parsing]` area in `facts.md` with the slugs
  `parsing.unidor-keywords`, `parsing.unidor-parens`, `parsing.stat-is-uni`, `parsing.filetest-letters`,
  `parsing.core-prefix` and `parsing.weak-override-import`, plus proposed `parsing.statement-terminator`,
  `parsing.unary-argument-start` and `parsing.keyword-classes`.
