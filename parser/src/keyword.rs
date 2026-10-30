//! Keyword table — maps identifier strings to `Keyword` variants, and records each keyword's strength, feature gate and
//! syntax.

use crate::pragma::Features;
use phf::phf_map;

// The keyword table.  Each row is
//
//     Variant => ±"name" [FEATURE] syntax(modifier)
//
// where `+` marks a strong keyword and `-` a weak one, `[FEATURE]` (optional) names the `Features` flag that must be
// enabled for the name to be a keyword, and `syntax`, with its optional modifier, is one of the `Syntax` values.
keywords! {
    __FILE__         => -"__FILE__"                         nullary
    __LINE__         => -"__LINE__"                         nullary
    __PACKAGE__      => -"__PACKAGE__"                      nullary
    __CLASS__        => -"__CLASS__"         [CLASS]        nullary
    __DATA__         => +"__DATA__"                         special
    __END__          => +"__END__"                          special
    __SUB__          => -"__SUB__"           [CURRENT_SUB]  nullary
    ADJUST           => +"ADJUST"            [CLASS]        statement
    AUTOLOAD         => +"AUTOLOAD"                         statement
    BEGIN            => +"BEGIN"                            statement
    UNITCHECK        => +"UNITCHECK"                        statement
    DESTROY          => +"DESTROY"                          statement
    END              => +"END"                              statement
    INIT             => +"INIT"                             statement
    CHECK            => +"CHECK"                            statement
    Abs              => -"abs"                              named_unary
    Accept           => -"accept"                           list_op
    Alarm            => -"alarm"                            named_unary
    All              => -"all"               [KEYWORD_ALL]  block_list_op
    And              => -"and"                              operator
    Any              => -"any"               [KEYWORD_ANY]  block_list_op
    Atan2            => -"atan2"                            list_op
    Bind             => -"bind"                             list_op
    Binmode          => -"binmode"                          list_op
    Bless            => -"bless"                            list_op
    Break            => -"break"             [SWITCH]       nullary
    Caller           => -"caller"                           named_unary
    Catch            => +"catch"             [TRY]          special
    Chdir            => -"chdir"                            named_unary
    Chmod            => -"chmod"                            list_op
    Chomp            => -"chomp"                            named_unary
    Chop             => -"chop"                             named_unary
    Chown            => -"chown"                            list_op
    Chr              => -"chr"                              named_unary
    Chroot           => -"chroot"                           named_unary
    Class            => -"class"             [CLASS]        statement
    Close            => -"close"                            named_unary
    Closedir         => -"closedir"                         named_unary
    Cmp              => -"cmp"                              operator
    Connect          => -"connect"                          list_op
    Continue         => -"continue"                         special
    Cos              => -"cos"                              named_unary
    Crypt            => -"crypt"                            list_op
    Dbmclose         => -"dbmclose"                         named_unary
    Dbmopen          => -"dbmopen"                          list_op
    Default          => +"default"           [SWITCH]       statement
    Defer            => +"defer"             [DEFER]        statement
    Defined          => +"defined"                          named_unary
    Delete           => +"delete"                           named_unary
    Die              => -"die"                              named_unary
    Do               => +"do"                               special
    Dump             => -"dump"                             loop_exit
    Each             => -"each"                             list_op
    Else             => +"else"                             special
    Elsif            => +"elsif"                            special

    // `elseif` is not a Perl keyword, but toke.c recognizes it in order to warn "elseif should be elsif".
    Elseif           => +"elseif"                           special
    Endgrent         => -"endgrent"                         nullary
    Endhostent       => -"endhostent"                       nullary
    Endnetent        => -"endnetent"                        nullary
    Endprotoent      => -"endprotoent"                      nullary
    Endpwent         => -"endpwent"                         nullary
    Endservent       => -"endservent"                       nullary
    Eof              => -"eof"                              named_unary
    Eq               => -"eq"                               operator
    Eval             => +"eval"                             special
    Evalbytes        => -"evalbytes"         [EVALBYTES]    named_unary
    Exec             => -"exec"                             list_op(indirect)
    Exists           => +"exists"                           named_unary
    Exit             => -"exit"                             named_unary
    Exp              => -"exp"                              named_unary
    Fc               => -"fc"                [FC]           named_unary
    Fcntl            => -"fcntl"                            list_op
    Field            => -"field"             [CLASS]        statement
    Fileno           => -"fileno"                           named_unary
    Finally          => +"finally"           [TRY]          special
    Flock            => -"flock"                            list_op
    For              => +"for"                              statement
    Foreach          => +"foreach"                          statement
    Fork             => -"fork"                             nullary
    Format           => +"format"                           statement
    Formline         => -"formline"                         list_op
    Ge               => -"ge"                               operator
    Getc             => -"getc"                             named_unary(defined_or)
    Getgrent         => -"getgrent"                         nullary
    Getgrgid         => -"getgrgid"                         named_unary
    Getgrnam         => -"getgrnam"                         named_unary
    Gethostbyaddr    => -"gethostbyaddr"                    list_op
    Gethostbyname    => -"gethostbyname"                    named_unary
    Gethostent       => -"gethostent"                       nullary
    Getlogin         => -"getlogin"                         nullary
    Getnetbyaddr     => -"getnetbyaddr"                     list_op
    Getnetbyname     => -"getnetbyname"                     named_unary
    Getnetent        => -"getnetent"                        nullary
    Getpeername      => -"getpeername"                      named_unary
    Getpgrp          => -"getpgrp"                          named_unary
    Getppid          => -"getppid"                          nullary
    Getpriority      => -"getpriority"                      list_op
    Getprotobyname   => -"getprotobyname"                   named_unary
    Getprotobynumber => -"getprotobynumber"                 named_unary
    Getprotoent      => -"getprotoent"                      nullary
    Getpwent         => -"getpwent"                         nullary
    Getpwnam         => -"getpwnam"                         named_unary
    Getpwuid         => -"getpwuid"                         named_unary
    Getservbyname    => -"getservbyname"                    list_op
    Getservbyport    => -"getservbyport"                    list_op
    Getservent       => -"getservent"                       nullary
    Getsockname      => -"getsockname"                      named_unary
    Getsockopt       => -"getsockopt"                       list_op
    Given            => +"given"             [SWITCH]       statement
    Glob             => +"glob"                             list_op
    Gmtime           => -"gmtime"                           named_unary
    Goto             => +"goto"                             loop_exit
    Grep             => +"grep"                             list_op(indirect)
    Gt               => -"gt"                               operator
    Hex              => -"hex"                              named_unary
    If               => +"if"                               statement
    Index            => -"index"                            list_op
    Int              => -"int"                              named_unary
    Ioctl            => -"ioctl"                            list_op
    Isa              => -"isa"               [ISA]          operator
    Join             => -"join"                             list_op
    Keys             => -"keys"                             list_op
    Kill             => -"kill"                             list_op
    Last             => +"last"                             loop_exit
    Lc               => -"lc"                               named_unary
    Lcfirst          => -"lcfirst"                          named_unary
    Le               => -"le"                               operator
    Length           => -"length"                           named_unary
    Link             => -"link"                             list_op
    Listen           => -"listen"                           list_op
    Local            => +"local"                            special
    Localtime        => -"localtime"                        named_unary
    Lock             => -"lock"                             named_unary
    Log              => -"log"                              named_unary
    Lstat            => -"lstat"                            named_unary
    Lt               => -"lt"                               operator
    M                => +"m"                                quote
    Map              => +"map"                              list_op(indirect)
    Method           => -"method"            [CLASS]        statement(term)
    Mkdir            => -"mkdir"                            list_op
    Msgctl           => -"msgctl"                           list_op
    Msgget           => -"msgget"                           list_op
    Msgrcv           => -"msgrcv"                           list_op
    Msgsnd           => -"msgsnd"                           list_op
    My               => +"my"                               statement(term)
    Ne               => -"ne"                               operator
    Next             => +"next"                             loop_exit
    No               => +"no"                               statement
    Not              => -"not"                              special
    Oct              => -"oct"                              named_unary
    Open             => -"open"                             list_op
    Opendir          => -"opendir"                          list_op
    Or               => -"or"                               operator
    Ord              => -"ord"                              named_unary
    Our              => +"our"                              statement(term)
    Pack             => -"pack"                             list_op
    Package          => +"package"                          statement
    Pipe             => -"pipe"                             list_op
    Pop              => -"pop"                              named_unary(defined_or)
    Pos              => +"pos"                              named_unary(defined_or)
    Print            => +"print"                            list_op(indirect)
    Printf           => +"printf"                           list_op(indirect)
    Prototype        => +"prototype"                        named_unary
    Push             => -"push"                             list_op
    Q                => +"q"                                quote
    Qq               => +"qq"                               quote
    Qr               => +"qr"                               quote
    Quotemeta        => -"quotemeta"                        named_unary
    Qw               => +"qw"                               quote
    Qx               => +"qx"                               quote
    Rand             => -"rand"                             named_unary
    Read             => -"read"                             list_op
    Readdir          => -"readdir"                          named_unary
    Readline         => -"readline"                         named_unary(defined_or)
    Readlink         => -"readlink"                         named_unary(defined_or)
    Readpipe         => -"readpipe"                         named_unary
    Recv             => -"recv"                             list_op
    Redo             => +"redo"                             loop_exit
    Ref              => -"ref"                              named_unary
    Rename           => -"rename"                           list_op
    Require          => +"require"                          named_unary
    Reset            => -"reset"                            named_unary
    Return           => +"return"                           list_op(no_call_form)
    Reverse          => -"reverse"                          list_op
    Rewinddir        => -"rewinddir"                        named_unary
    Rindex           => -"rindex"                           list_op
    Rmdir            => -"rmdir"                            named_unary
    S                => +"s"                                quote
    Say              => +"say"               [SAY]          list_op(indirect)
    Scalar           => +"scalar"                           named_unary
    Seek             => -"seek"                             list_op
    Seekdir          => -"seekdir"                          list_op
    Select           => -"select"                           list_op
    Semctl           => -"semctl"                           list_op
    Semget           => -"semget"                           list_op
    Semop            => -"semop"                            list_op
    Send             => -"send"                             list_op
    Setgrent         => -"setgrent"                         nullary
    Sethostent       => -"sethostent"                       named_unary
    Setnetent        => -"setnetent"                        named_unary
    Setpgrp          => -"setpgrp"                          list_op
    Setpriority      => -"setpriority"                      list_op
    Setprotoent      => -"setprotoent"                      named_unary
    Setpwent         => -"setpwent"                         nullary
    Setservent       => -"setservent"                       named_unary
    Setsockopt       => -"setsockopt"                       list_op
    Shift            => -"shift"                            named_unary(defined_or)
    Shmctl           => -"shmctl"                           list_op
    Shmget           => -"shmget"                           list_op
    Shmread          => -"shmread"                          list_op
    Shmwrite         => -"shmwrite"                         list_op
    Shutdown         => -"shutdown"                         list_op
    Sin              => -"sin"                              named_unary
    Sleep            => -"sleep"                            named_unary
    Socket           => -"socket"                           list_op
    Socketpair       => -"socketpair"                       list_op
    Sort             => +"sort"                             list_op(indirect)
    Splice           => -"splice"                           list_op
    Split            => +"split"                            list_op
    Sprintf          => -"sprintf"                          list_op
    Sqrt             => -"sqrt"                             named_unary
    Srand            => -"srand"                            named_unary
    Stat             => -"stat"                             named_unary
    State            => +"state"             [STATE]        statement(term)
    Study            => +"study"                            named_unary
    Sub              => +"sub"                              statement(term)
    Substr           => -"substr"                           list_op
    Symlink          => -"symlink"                          list_op
    Syscall          => -"syscall"                          list_op
    Sysopen          => -"sysopen"                          list_op
    Sysread          => -"sysread"                          list_op
    Sysseek          => -"sysseek"                          list_op
    System           => -"system"                           list_op(indirect)
    Syswrite         => -"syswrite"                         list_op
    Tell             => -"tell"                             list_op
    Telldir          => -"telldir"                          named_unary
    Tie              => -"tie"                              list_op
    Tied             => -"tied"                             named_unary
    Time             => -"time"                             nullary
    Times            => -"times"                            nullary
    Tr               => +"tr"                               quote
    Try              => +"try"               [TRY]          statement
    Truncate         => -"truncate"                         list_op
    Uc               => -"uc"                               named_unary
    Ucfirst          => -"ucfirst"                          named_unary
    Umask            => -"umask"                            named_unary(defined_or)
    Undef            => +"undef"                            named_unary(defined_or)
    Unless           => +"unless"                           statement
    Unlink           => -"unlink"                           list_op
    Unpack           => -"unpack"                           list_op
    Unshift          => -"unshift"                          list_op
    Untie            => -"untie"                            list_op
    Until            => +"until"                            statement
    Use              => +"use"                              statement
    Utime            => -"utime"                            list_op
    Values           => -"values"                           list_op
    Vec              => -"vec"                              list_op
    Wait             => -"wait"                             nullary
    Waitpid          => -"waitpid"                          list_op
    Wantarray        => -"wantarray"                        nullary
    Warn             => -"warn"                             named_unary
    When             => +"when"              [SWITCH]       statement
    While            => +"while"                            statement
    Write            => -"write"                            list_op
    X                => -"x"                                operator
    Xor              => -"xor"                              operator
    Y                => +"y"                                quote
}

/// Whether a user-defined sub can override a keyword.  This is the `+`/`-` of Perl's `regen/keywords.pl`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Strength {
    /// Never overridden, except by a lexical sub.
    Strong,

    /// Overridden by an imported sub or an imported `CORE::GLOBAL::` sub.
    Weak,
}

/// How the parser reads what follows a keyword.  Each value corresponds to one of the macros `toke.c` uses for the
/// keyword's case in `yyl_word_or_keyword`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Syntax {
    /// Takes no operand, with optional empty parentheses (`FUN0`, `FUN0OP`): `time`, `wantarray`.
    Nullary,

    /// Named unary (`UNI`): `NAME(...)` is the call form; otherwise an optional operand at named-unary precedence.
    NamedUnary,

    /// Named unary after which `//`, `//=` and `~~` are operators rather than the start of an operand (`UNIDOR`).
    NamedUnaryDefinedOr,

    /// List operator (`LOP` with `XTERM`): `NAME(...)` is the call form; otherwise a list at list-operator precedence.
    ListOp,

    /// List operator whose list may begin with an indirect object: a filehandle, block or sub name (`LOP` with `XREF`).
    ListOpIndirect,

    /// List operator with no call form, so a `(` begins its first element (`OLDLOP`): `return`.
    ListOpNoCallForm,

    /// List operator whose first argument must be a block (`BLKLOP`): `any`, `all`.
    BlockListOp,

    /// Loop exit with an optional label or operand, at the lowest precedence (`LOOPX`).
    LoopExit,

    /// Infix word operator, read in operator position: `and`, `x`, `eq`, `isa`, ...
    Operator,

    /// Quote-like operator whose delimited body the lexer scans: `q`, `qq`, `qw`, `qr`, `qx`, `m`, `s`, `tr`, `y`.
    Quote,

    /// Grammar of its own, dispatched by name at the start of a statement: `if`, `while`, `package`, `BEGIN`, ...  The
    /// table writes `statement(term)` for `my`, `our`, `state`, `sub` and `method`, which begin a statement of their
    /// own only in some forms (`my sub NAME`, `sub NAME`) and are otherwise terms; the modifier records that and does
    /// not change the value.
    Statement,

    /// Grammar of its own, read where its construct calls for it: `do`, `eval`, `local` and `not` begin a term; `else`,
    /// `elsif`, `catch`, `finally` and `continue` are clauses of another statement; `__DATA__` and `__END__` end the
    /// program.
    Special,
}

/// Look up a keyword by name, respecting feature gating.  Returns `None` for unknown names and for feature-gated
/// keywords whose feature is not active (they are plain identifiers in that context).
pub fn lookup_keyword(name: &str, features: Features) -> Option<Keyword> {
    let &kw = KEYWORDS.get(name)?;
    if kw.feature().is_none_or(|f| features.contains(f)) { Some(kw) } else { None }
}

/// Reverse lookup: get the source-text name of a keyword.
impl From<Keyword> for &'static str {
    fn from(kw: Keyword) -> &'static str {
        kw.name()
    }
}

/// Is this keyword a quote-like operator (`q`, `qq`, `qw`, `qr`, `qx`, `m`, `s`, `tr`, `y`)?  These require special
/// handling in the parser because they can start sublexing — the byte following the keyword (after whitespace) is the
/// quote delimiter, not a normal token.  The parser must avoid calling `peek_token` before deciding whether to enter
/// sublexing mode.
pub fn is_quote_keyword(kw: Keyword) -> bool {
    kw.syntax() == Syntax::Quote
}

/// String-based variant of `is_quote_keyword`, for use before keyword lookup has run (e.g. the `#`-delimiter guard
/// in `lex_word`).  No quote-like operator is feature-gated, so the features in effect do not matter.
pub fn is_quote_keyword_str(name: &str) -> bool {
    KEYWORDS.get(name).is_some_and(|kw| is_quote_keyword(*kw))
}

/// Is this keyword a named unary operator?  After a named unary, the next thing is a term (so `/` is regex).
pub fn is_named_unary(kw: Keyword) -> bool {
    matches!(kw.syntax(), Syntax::NamedUnary | Syntax::NamedUnaryDefinedOr)
}

/// Is this keyword a nullary builtin (takes no arguments)?
///
/// Nullary builtins never consume a following term as an argument, so `time+86_400` is always `time() + 86_400`.  They
/// do accept explicit empty parens: `time()`.
pub fn is_nullary(kw: Keyword) -> bool {
    kw.syntax() == Syntax::Nullary
}

/// Does this operator prefer `//` as defined-or over an empty regex argument?
///
/// Matches toke.c's `UNIDOR` macro.  After these operators, `shift // 0` is parsed as `shift() // 0`, not
/// `shift(m//)`.
pub fn prefers_defined_or(kw: Keyword) -> bool {
    kw.syntax() == Syntax::NamedUnaryDefinedOr
}

/// Is this keyword a list operator?  After a list op, the next thing is a term (so `/` is regex).
pub fn is_list_op(kw: Keyword) -> bool {
    matches!(kw.syntax(), Syntax::ListOp | Syntax::ListOpIndirect | Syntax::ListOpNoCallForm)
}

/// Is this keyword a block-list operator (sort/map/grep)?  These take an optional block as the first argument.
pub fn is_block_list_op(kw: Keyword) -> bool {
    matches!(kw, Keyword::Sort | Keyword::Map | Keyword::Grep | Keyword::Any | Keyword::All)
}

/// Is this keyword a print-like operator?  These take an optional filehandle as the first argument.
pub fn is_print_op(kw: Keyword) -> bool {
    matches!(kw, Keyword::Print | Keyword::Say | Keyword::Printf)
}

/// Does this keyword have a dedicated handler at the start of a statement (`Syntax::Statement`)?
pub fn is_statement_keyword(kw: Keyword) -> bool {
    kw.syntax() == Syntax::Statement
}

/// Is this keyword "strong" (`+` in regen/keywords.pl)?
///
/// Strong keywords always take precedence over user-defined subs.  Weak keywords (the negation) can be overridden by
/// imported subs (via `use subs`, `Exporter`, etc.).  A local `sub abs { }` produces an "Ambiguous call resolved as
/// CORE::abs()" warning but the keyword still wins; only an imported sub actually overrides.
pub fn is_strong(kw: Keyword) -> bool {
    kw.strength() == Strength::Strong
}

/// Is this keyword "weak" (`-` in regen/keywords.pl)?
///
/// Weak keywords can be overridden by imported subs.  When the lexer encounters a weak keyword whose name has been
/// imported into the current package, it emits `Token::Ident` instead of `Token::Keyword`.
pub fn is_weak(kw: Keyword) -> bool {
    !is_strong(kw)
}

macro_rules! keyword_strength {
    (+) => {
        Strength::Strong
    };
    (-) => {
        Strength::Weak
    };
}
pub(crate) use keyword_strength;

macro_rules! keyword_feature {
    () => {
        None
    };
    ($feature:ident) => {
        Some(Features::$feature)
    };
}
pub(crate) use keyword_feature;

macro_rules! keyword_syntax {
    (nullary) => {
        Syntax::Nullary
    };
    (named_unary) => {
        Syntax::NamedUnary
    };
    (named_unary(defined_or)) => {
        Syntax::NamedUnaryDefinedOr
    };
    (list_op) => {
        Syntax::ListOp
    };
    (list_op(indirect)) => {
        Syntax::ListOpIndirect
    };
    (list_op(no_call_form)) => {
        Syntax::ListOpNoCallForm
    };
    (block_list_op) => {
        Syntax::BlockListOp
    };
    (loop_exit) => {
        Syntax::LoopExit
    };
    (operator) => {
        Syntax::Operator
    };
    (quote) => {
        Syntax::Quote
    };
    (statement) => {
        Syntax::Statement
    };
    (statement(term)) => {
        Syntax::Statement
    };
    (special) => {
        Syntax::Special
    };
}
pub(crate) use keyword_syntax;

/// Generates `Keyword`, its name map and its accessors from the keyword table at the top of this file.
macro_rules! keywords {
    ($( $variant:ident => $strength:tt $name:literal $([$feature:ident])? $syntax:ident $(($modifier:ident))? )*) => {
        /// Perl keyword.
        #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
        pub enum Keyword {
            $($variant,)*
        }

        /// Perfect-hash keyword lookup table, keyed by the keyword's name.
        static KEYWORDS: phf::Map<&'static str, Keyword> = phf_map! {
            $($name => Keyword::$variant,)*
        };

        impl Keyword {
            /// The keyword's source-text name.
            pub const fn name(self) -> &'static str {
                match self {
                    $(Keyword::$variant => $name,)*
                }
            }

            /// Whether a user-defined sub can override the keyword.
            pub const fn strength(self) -> Strength {
                match self {
                    $(Keyword::$variant => $crate::keyword::keyword_strength!($strength),)*
                }
            }

            /// The feature that must be enabled for the name to be a keyword, if any.
            pub const fn feature(self) -> Option<Features> {
                match self {
                    $(Keyword::$variant => $crate::keyword::keyword_feature!($($feature)?),)*
                }
            }

            /// How the parser reads what follows the keyword.
            pub const fn syntax(self) -> Syntax {
                match self {
                    $(Keyword::$variant => $crate::keyword::keyword_syntax!($syntax $(($modifier))?),)*
                }
            }
        }
    };
}
pub(crate) use keywords;
