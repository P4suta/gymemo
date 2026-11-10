//! Reads the repository's Swift files and separates their code from their comments and from the text of their literals.
//!
//! One lexer reads each source for every check, so the checks agree on what the code is.
//! The [lexical structure](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/) of Swift gives the rules.
//! A block comment nests, and a literal between three quotes spans lines when the three quotes end their line.
//! A literal between pound signs takes the same pound signs in its escapes and its interpolations.
//! A literal that opens with one quote ends with its line, and so does every interpolation and literal that it holds open, because the compiler accepts no line feed there.
//! A regular expression literal between pound signs, such as `#/a/*b/#`, ends with the same pound signs, and it spans lines when its opening delimiter ends its line.
//! A bare regular expression literal such as `/\/*/` opens only where an expression may start, as [SE-0354](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0354-regex-literals.md) states.
//! `opens_bare_pattern` reads that place from the tokens around the slash, after `tryScanOperatorAsRegexLiteral` and `isInRegexLiteralPosition` in `Sources/SwiftParser/Lexer/RegexLiteralLexer.swift` of [swift-syntax](https://github.com/swiftlang/swift-syntax).
//! `closes_bare` reads the contents as Swift 6.4.2 does, after `tryScanRegexLiteral` in `lib/Parse/Lexer.cpp` of the compiler and `DelimiterLexing.swift` of swift-experimental-string-processing.
//! A raw identifier such as `` `per /day` ``, which [SE-0451](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0451-escaped-identifiers.md) adds, is one name from a backtick to the next backtick on its line, so nothing opens inside it.
//! The identifier heads, the identifier characters, the operator heads, and the operator characters are the sets of the lexer of Swift 6.4.2.
//! `lib/Parse/Lexer.cpp` and `include/swift/AST/Identifier.h` of the compiler define them.
//! The whitespace is that of the lexical structure and the no-break space, which the compiler reads as whitespace with a warning.
//! `step` reads each name and each operator to its longest form.
//! The compiler skips a byte order mark at the start of a source, and the lexer reads it like a comment.
//!
//! The lexer agrees with Swift 6.4.2 on the constructs of the 31 shipped sources, as the two measures below show.
//! It agrees in the same two measures on the 6,251 Swift files that `fd -e swift` lists under the local projects directory, as many as the review compared.
//! Swift parses each of those files without an error.
//! In each of them the lexer reads the regular expression literals that `swiftc -frontend -dump-parse -swift-version 6` dumps and no other.
//! It also shows as code the first character of each declaration, statement, and other explicit node to which the dump gives a source range.
//! A scratch tool made that comparison on 2026-11-10.
//! It fed each file to `swiftc -frontend -dump-parse -swift-version 6` and compared the dump with the marks.
//!
//! Two known exceptions remain in sources that Swift accepts.
//! The first is a constant named `yield` right before a slash, as in `let yield = 6; let q = yield/2; let d = Date()`.
//! Swift divides there.
//! The lexer reads the keyword that starts an expression in a `_read` accessor, so it reads a regular expression literal from that slash to the last slash of the line.
//! That misread ends with its line, as every bare literal does, and it costs the findings of the rest of that line.
//! The second is a carriage return that no line feed follows, as in a line comment `// c` with a carriage return and `let d = Date()` after it.
//! Swift ends the comment and the line there, but the lexer ends a line comment and counts a line only at a line feed.
//! That misread reaches the next line feed, which is the end of the source in a file that ends each line with a carriage return alone.
//!
//! The lexer also reads some sources that Swift refuses differently from the compiler.
//! After `,` or `:` outside parentheses, the parser of the compiler reads a literal even where a closing parenthesis closes no group.
//! It reads such a literal in `let r = [1, /)a/]` and in `let r = true ? /a/ : /)b/`, and the compiler then refuses that literal as an unbalanced group.
//! The lexer reads code there, which reaches the end of the line.
//! Where the contents hold `/*`, the misread reaches the `*/` that closes that nesting comment, often the end of the source.
//! The compiler reads no raw identifier between two backticks around a backslash, a tab, or operator characters alone.
//! It also refuses a raw identifier such as `` `a //b` `` inside an interpolation.
//! The lexer reads each of them as a name, which hides nothing.
//! Three quotes with a blank or a tab after them on their line open a literal that spans lines for the lexer.
//! That misread reaches the next three quotes or the end of the source.
//! Three quotes with a comment or another character after them on their line open a literal of one line for the lexer.
//! The three quotes that close that literal then open one that spans lines, and that misread reaches the next three quotes or the end of the source.
//! A slash right after a keyword and a postfix mark opens a literal for the lexer, as in `return!/a"/`, which reaches the end of the line.
//! A slash with a separator after it on the line after `let x = 6`, as in `/,a"/`, opens one too.
//! A block comment or a literal between three quotes that never closes reaches the end of the source, as it does for Swift.

use crate::failure::{Context, Result, ensure};
use std::{
    fs,
    path::{Path, PathBuf},
};

/// The directories whose Swift code ships in the app or its packages.
pub const SHIPPED: [&str; 2] = ["App", "Sources"];

/// Whether `character` is a blank inside a line.
fn blank(character: char) -> bool {
    matches!(character, ' ' | '\t')
}

/// Whether `character` ends a line, which a carriage return does for a regular expression literal and for the opening delimiter of a literal that spans lines.
fn line_end(character: char) -> bool {
    matches!(character, '\n' | '\r')
}

/// Whether `character` before an operator leaves it unbound on its left, as `isLeftBound` of swift-syntax reads it.
/// The carriage return, the null character, and the no-break space stand there like a blank.
fn opens_before(character: char) -> bool {
    matches!(
        character,
        ' ' | '\t' | '\n' | '\r' | '\0' | '\u{a0}' | '(' | '[' | '{' | ',' | ';' | ':'
    )
}

/// Whether `character` after an operator leaves it unbound on its right, as `isRightBound` of swift-syntax reads it.
/// The carriage return, the null character, and the no-break space stand there like a blank.
fn closes_after(character: char) -> bool {
    matches!(
        character,
        ' ' | '\t' | '\n' | '\r' | '\0' | '\u{a0}' | ')' | ']' | '}' | ',' | ';' | ':'
    )
}

/// Whether `character` stands between two tokens, as the whitespace of the lexical structure does.
/// The grammar names the null character, the tab, the line feed, the vertical tab, the form feed, the carriage return, and the blank.
/// The lexer of the compiler also reads the no-break space as whitespace, with a warning.
/// A byte order mark stands between tokens only at the start of a source, which `Lexer::code` reads on its own.
/// Elsewhere the mark is an identifier head.
fn spacing(character: char) -> bool {
    matches!(
        character,
        '\0' | '\t' | '\n' | '\u{b}' | '\u{c}' | '\r' | ' ' | '\u{a0}'
    )
}

/// Whether `character` is a control character that ends a regular expression literal of one line.
/// Every control character but the null character does, as `advance` in `DelimiterLexing.swift` of swift-experimental-string-processing reads it.
fn unprintable(character: char) -> bool {
    character.is_ascii_control() && character != '\0'
}

/// Whether `character` may stand in an operator, where the period counts too, as in `..<`.
pub fn dotted(character: char) -> bool {
    operator(character) || character == '.'
}

/// Whether `character` may start an identifier, as `isValidIdentifierStartCodePoint` in `lib/Parse/Lexer.cpp` of Swift 6.4.2 reads it.
/// The set is that of the identifier heads of the lexical structure, except that the compiler reads the five characters from U+FFF9 on as no character of an identifier.
/// Inside ASCII the letters and the underscore are the identifier heads, and the lexer answers there without the ranges outside ASCII.
fn identifier_head(character: char) -> bool {
    if character.is_ascii() {
        return character.is_ascii_alphabetic() || character == '_';
    }
    matches!(
        character,
        '\u{a8}'
            | '\u{aa}'
            | '\u{ad}'
            | '\u{af}'
            | '\u{b2}'..='\u{b5}'
            | '\u{b7}'..='\u{ba}'
            | '\u{bc}'..='\u{be}'
            | '\u{c0}'..='\u{d6}'
            | '\u{d8}'..='\u{f6}'
            | '\u{f8}'..='\u{ff}'
            | '\u{100}'..='\u{2ff}'
            | '\u{370}'..='\u{167f}'
            | '\u{1681}'..='\u{180d}'
            | '\u{180f}'..='\u{1dbf}'
            | '\u{1e00}'..='\u{1fff}'
            | '\u{200b}'..='\u{200d}'
            | '\u{202a}'..='\u{202e}'
            | '\u{203f}'..='\u{2040}'
            | '\u{2054}'
            | '\u{2060}'..='\u{206f}'
            | '\u{2070}'..='\u{20cf}'
            | '\u{2100}'..='\u{218f}'
            | '\u{2460}'..='\u{24ff}'
            | '\u{2776}'..='\u{2793}'
            | '\u{2c00}'..='\u{2dff}'
            | '\u{2e80}'..='\u{2fff}'
            | '\u{3004}'..='\u{3007}'
            | '\u{3021}'..='\u{302f}'
            | '\u{3031}'..='\u{303f}'
            | '\u{3040}'..='\u{d7ff}'
            | '\u{f900}'..='\u{fd3d}'
            | '\u{fd40}'..='\u{fdcf}'
            | '\u{fdf0}'..='\u{fe1f}'
            | '\u{fe30}'..='\u{fe44}'
            | '\u{fe47}'..='\u{fff8}'
            | '\u{10000}'..='\u{1fffd}'
            | '\u{20000}'..='\u{2fffd}'
            | '\u{30000}'..='\u{3fffd}'
            | '\u{40000}'..='\u{4fffd}'
            | '\u{50000}'..='\u{5fffd}'
            | '\u{60000}'..='\u{6fffd}'
            | '\u{70000}'..='\u{7fffd}'
            | '\u{80000}'..='\u{8fffd}'
            | '\u{90000}'..='\u{9fffd}'
            | '\u{a0000}'..='\u{afffd}'
            | '\u{b0000}'..='\u{bfffd}'
            | '\u{c0000}'..='\u{cfffd}'
            | '\u{d0000}'..='\u{dfffd}'
            | '\u{e0000}'..='\u{efffd}'
    )
}

/// Whether `character` may continue an identifier or a keyword without starting one, as `isValidIdentifierContinuationCodePoint` in `lib/Parse/Lexer.cpp` of Swift 6.4.2 reads it.
/// The decimal digits and four ranges of combining marks make up this set, and the combining marks may also continue an operator.
/// The set holds the identifier characters of the lexical structure that are no identifier heads.
/// The compiler also continues an identifier with a dollar sign, which `step` reads on its own.
/// The identifier characters are the identifier heads and these.
fn identifier_tail(character: char) -> bool {
    matches!(
        character,
        '0'..='9'
            | '\u{300}'..='\u{36f}'
            | '\u{1dc0}'..='\u{1dff}'
            | '\u{20d0}'..='\u{20ff}'
            | '\u{fe20}'..='\u{fe2f}'
    )
}

/// Whether `character` may continue an operator without starting one, as `isOperatorContinuationCodePoint` in `include/swift/AST/Identifier.h` of Swift 6.4.2 reads it.
/// The combining marks that may also continue an identifier and two ranges of variation selectors, which may also start one, make up this set with U+3021 to U+302F.
/// The lexical structure lists U+3021 to U+302F as identifier heads only, but `isOperatorStartCodePoint` holds them too.
/// The lexer of the compiler tries an identifier first, so they start a name and continue an operator, as in `±〡`, and Swift refuses `prefix operator 〡`.
/// The operator characters are the operator heads and these.
fn operator_tail(character: char) -> bool {
    matches!(
        character,
        '\u{300}'..='\u{36f}'
            | '\u{1dc0}'..='\u{1dff}'
            | '\u{20d0}'..='\u{20ff}'
            | '\u{3021}'..='\u{302f}'
            | '\u{fe00}'..='\u{fe0f}'
            | '\u{fe20}'..='\u{fe2f}'
            | '\u{e0100}'..='\u{e01ef}'
    )
}

/// Whether `character` may start an operator, as `isOperatorStartCodePoint` in `include/swift/AST/Identifier.h` of Swift 6.4.2 reads it where no identifier starts.
/// The set is that of the operator heads of the lexical structure, and the period, which starts only a dot operator, stands apart in `step`.
/// Inside ASCII fourteen characters are operator heads, and the lexer answers there without the ranges outside ASCII.
fn operator_head(character: char) -> bool {
    if character.is_ascii() {
        return matches!(
            character,
            '/' | '=' | '-' | '+' | '!' | '*' | '%' | '<' | '>' | '&' | '|' | '^' | '~' | '?'
        );
    }
    matches!(
        character,
        '\u{a1}'..='\u{a7}'
            | '\u{a9}'
            | '\u{ab}'
            | '\u{ac}'
            | '\u{ae}'
            | '\u{b0}'..='\u{b1}'
            | '\u{b6}'
            | '\u{bb}'
            | '\u{bf}'
            | '\u{d7}'
            | '\u{f7}'
            | '\u{2016}'..='\u{2017}'
            | '\u{2020}'..='\u{2027}'
            | '\u{2030}'..='\u{203e}'
            | '\u{2041}'..='\u{2053}'
            | '\u{2055}'..='\u{205e}'
            | '\u{2190}'..='\u{23ff}'
            | '\u{2500}'..='\u{2775}'
            | '\u{2794}'..='\u{2bff}'
            | '\u{2e00}'..='\u{2e7f}'
            | '\u{3001}'..='\u{3003}'
            | '\u{3008}'..='\u{3020}'
            | '\u{3030}'
    )
}

/// Whether `character` is the token after which an element of a list or an argument starts.
fn lists(character: char) -> bool {
    matches!(character, '(' | ',' | ':')
}

/// Whether `character` after an operator ends an element of a list, as `listElementIsBinaryOperator` in `lib/Parse/ParseExpr.cpp` of the compiler reads it.
fn ends_element(character: char) -> bool {
    matches!(character, ',' | ')')
}

/// Whether `character` may continue an operator such as `/=`, as `isOperatorContinuationCodePoint` of the compiler reads it.
fn operator(character: char) -> bool {
    operator_head(character) || operator_tail(character)
}

/// One Swift file with its path relative to the repository root.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Source {
    pub file: String,
    pub text: String,
}

/// One string literal of a source.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Literal {
    /// The line of the opening quote.
    pub line: usize,
    /// The text outside the interpolations, with one blank in place of each escape.
    pub text: String,
}

/// One interpolation of a string literal.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Interpolation {
    /// The line of the backslash that opens it.
    pub line: usize,
    /// What stands between the parentheses, as `code_only` shows it.
    pub code: String,
}

/// What the lexer reads one character as.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Class {
    /// Code, with the delimiters of each literal and of each interpolation.
    Code,
    /// A character of a comment, or the byte order mark at the start of a source, which the compiler skips.
    Comment,
    /// A character of the text of a literal.
    Text,
    /// The backslash of an escape, which stands for one blank of the text.
    Escape,
    /// What an escape holds after its backslash.
    Escaped,
    /// A character of a regular expression literal between its delimiters.
    Pattern,
}

/// The class of one character, with the number of literals and interpolations that are open after it.
/// A literal opens only in code, and an interpolation opens only in the text of a literal.
/// That order puts the literals at the odd levels and the interpolations at the even ones.
#[derive(Clone, Copy)]
struct Mark {
    class: Class,
    level: usize,
}

/// The comment that holds the character under the lexer.
enum Comment {
    None,
    /// A comment that ends with its line.
    Line,
    /// A comment between `/*` and `*/`, with the number of block comments around it.
    Block(usize),
}

/// A regular expression literal that hasn't ended yet.
#[derive(Clone, Copy)]
struct Pattern {
    /// The number of pound signs that delimit it, which is zero for a bare literal.
    pounds: usize,
    multiline: bool,
}

/// A literal or an interpolation that hasn't ended yet.
#[derive(Clone, Copy)]
struct Open {
    kind: Kind,
    /// The number of open literals and interpolations up to the innermost one that may hold a line feed, counted with this one.
    spanning: usize,
}

#[derive(Clone, Copy)]
enum Kind {
    /// A literal, with whether it spans lines and the number of pound signs that delimit it.
    Literal(bool, usize),
    /// An interpolation, with the number of parentheses that its code has opened.
    Interpolation(usize),
}

/// What binds an operator on its left.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Left {
    /// Nothing, as at the start of the source, after a blank, an opening bracket, or a separator, and right after a block comment.
    Free,
    /// A character that binds the operator where an expression starts, which the parser of the compiler reads past.
    /// The last character of a keyword binds it so, as in `return/a/`, and so does a vertical tab or a form feed.
    Reread,
    /// Any other character of the code.
    Bound,
}

/// What the token before an operator says about a regular expression literal at that operator, as `isInRegexLiteralPosition` of swift-syntax reads it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Before {
    /// `func` or `operator`, after which the operator names a declaration.
    Declaration,
    /// The end of an operand, such as a name, a literal, `)`, or a postfix operator, after which an operator free on both sides is binary.
    Operand,
    /// A place where an expression starts, such as the start of the source or the place after `=`, `;`, `{`, a binary operator, or a keyword like `return`.
    Expression,
    /// The keyword `try`, after which an expression starts and a `?` or `!` right after it ends no operand, as in `try? /a/`.
    Try,
    /// A place where an element of a list or an argument starts, after `(`, `,`, or `:`.
    Element,
}

/// Whether a character belongs to a name, an operator, or neither, as the lexical structure reads each token to its longest form.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Run {
    /// A name or a keyword, which starts at an identifier head or at a dollar sign, as in `$0`, and continues with identifier characters and dollar signs.
    Word,
    /// An operator, which starts at an operator head or a period and continues with operator characters and periods.
    Operator,
    /// A character that starts neither, such as a digit at the start of a number.
    Other,
}

/// Reads a source one token at a time and keeps what the source holds open.
/// `classify` hands it each character once, so the reading ends with the source.
struct Lexer<'a> {
    characters: &'a [char],
    /// What the source holds from each place on, as `ahead` reads it.
    ahead: Vec<Ahead>,
    /// Whether the character under the lexer belongs to a name, an operator, or neither, as `step` reads it.
    run: Run,
    /// The same for the character right before it.
    previous: Run,
    /// What binds the character under the lexer on its left, as `left_of` reads it once for each character.
    binding: Left,
    /// Whether the character right before the one under the lexer stands in an operator before its first slash.
    after_leads: bool,
    /// The mark of each character that the lexer has passed.
    marks: Vec<Mark>,
    /// What the last token that the lexer has passed says about an operator after it.
    last: Before,
    /// What binds the last run of operator characters other than the slash on its left, which `start_operator` records where the run starts.
    operator_left: Left,
    /// What the last token before that run says about it.
    operator_before: Before,
    /// The last word that the lexer has passed, as `spell` packs it.
    word: u128,
    /// Whether a period stands right before that word, which makes it the name of a member.
    member: bool,
    /// Whether the last run of operator characters that the lexer has passed is a postfix operator.
    postfix: bool,
    comment: Comment,
    /// The regular expression literal that holds the character under the lexer.
    pattern: Option<Pattern>,
    /// The pound signs that stand in the code right before the character under the lexer.
    pounds: usize,
    /// One place for each character of the source, which is room for every literal and interpolation, because each of them opens at its own character.
    /// The places below `level` hold the open ones, the innermost one last, so the store never grows while the lexer reads.
    places: Vec<Open>,
    /// The number of literals and interpolations that are open.
    level: usize,
    /// The characters that the token under the lexer holds after the one under the lexer.
    left: usize,
    /// The class of those characters.
    rest: Class,
}

impl Lexer<'_> {
    /// The innermost open literal or interpolation.
    fn innermost(&mut self) -> Option<&mut Open> {
        let top = self.level.checked_sub(1)?;
        self.places.get_mut(top)
    }

    /// The number of open literals and interpolations up to the innermost one that may hold a line feed.
    fn spanning(&mut self) -> usize {
        self.innermost().map_or(0, |open| open.spanning)
    }

    /// Opens a literal or an interpolation inside the innermost open one.
    /// A line feed may stand inside it when `multiline` holds, as in a literal between three quotes and in its interpolations.
    fn open(&mut self, multiline: bool, kind: Kind) {
        let spanning = if multiline {
            self.level + 1
        } else {
            self.spanning()
        };
        if let Some(place) = self.places.get_mut(self.level) {
            *place = Open { kind, spanning };
            self.level += 1;
        }
    }

    /// Whether `character` follows the character at `at`.
    fn followed_by(&self, at: usize, character: char) -> bool {
        self.characters.get(at + 1) == Some(&character)
    }

    /// Whether the character right before `at` is one that `part` accepts.
    fn after(&self, at: usize, part: fn(char) -> bool) -> bool {
        at.checked_sub(1)
            .and_then(|before| self.characters.get(before))
            .is_some_and(|character| part(*character))
    }

    /// Whether the character right before `at`, the character under the lexer, stands in an operator before its first slash, as the `!` before the slash of `!/a/` does.
    fn leads_before(&self, at: usize) -> bool {
        at.checked_sub(1)
            .and_then(|before| self.characters.get(before))
            .is_some_and(|character| leads(self.previous, *character))
    }

    /// Records what stands before the operator at `at`, the character under the lexer, where a run of operator characters other than the slash starts there, as in the `!/` of `!/a/`.
    /// A slash later in the run tries a literal with what this record holds, so the lexer never searches back from a slash.
    fn start_operator(&mut self, character: char) {
        if leads(self.run, character) && !self.after_leads {
            self.operator_left = self.binding;
            self.operator_before = self.last;
        }
    }

    /// What binds the operator at `at`, the character under the lexer, on its left, as `isLeftBound` of swift-syntax reads it.
    /// Nothing binds it at the start of the source, after a blank, an opening bracket, or a separator, or right after a block comment.
    /// The last character of a word binds it, and so do the vertical tab and the form feed, which `isLeftBound` doesn't list.
    /// Where an expression starts, the parser reads past that binding, as in `return/a/`, in the `!/` of `try!/a/`, and after the vertical tab of `= \u{b}/a/`.
    fn left_of(&self, at: usize) -> Left {
        let bound = at.checked_sub(1).and_then(|before| {
            let character = *self.characters.get(before)?;
            let mark = self.marks.get(before)?;
            (!opens_before(character) && mark.class != Class::Comment).then_some(character)
        });
        match bound {
            None => Left::Free,
            Some(character)
                if (self.previous == Run::Word || spacing(character))
                    && matches!(self.last, Before::Expression | Before::Try) =>
            {
                Left::Reread
            }
            Some(_) => Left::Bound,
        }
    }

    /// Whether the character right before `at`, the character under the lexer, is code that belongs to `run`.
    /// The character under the lexer then continues that token, because `step` reads each token to its longest form.
    fn continues(&self, at: usize, run: Run) -> bool {
        self.previous == run
            && at
                .checked_sub(1)
                .and_then(|before| self.marks.get(before))
                .is_some_and(|mark| mark.class == Class::Code)
    }

    /// Records what the character at `at`, which the lexer has just passed as `class`, says about an operator after it.
    /// Blanks, line feeds, comments, and the text of literals leave the record unchanged.
    /// A run of operator characters that something binds on its left is a postfix operator and ends an operand, unless it stands right after `try`, as in `try?`.
    /// A word after a period is the name of a member, as the parser of the compiler reads it, and `after_word` reads every other word.
    /// The closing backtick of a raw identifier ends an operand, whatever the characters between the backticks spell, as `isInRegexLiteralPosition` reads an identifier.
    /// The lexer reads each character once in its order, so this record replaces a search back from each slash.
    fn follow(&mut self, at: usize, character: char, class: Class) {
        if class != Class::Code || spacing(character) {
            return;
        }
        let run = self.run;
        self.last = if lists(character) {
            Before::Element
        } else if opens_before(character) {
            Before::Expression
        } else if run == Run::Operator {
            if !self.continues(at, Run::Operator) {
                self.postfix = self.binding != Left::Free && self.last != Before::Try;
            }
            if self.postfix {
                Before::Operand
            } else {
                Before::Expression
            }
        } else if run == Run::Word {
            // A character outside ASCII takes the code of the delete character, which no keyword holds.
            let code = if character.is_ascii() {
                u128::from(u32::from(character))
            } else {
                127
            };
            if self.continues(at, Run::Word) {
                self.word = (self.word << 7) + code;
            } else {
                self.word = code;
                self.member = self.after(at, |before| before == '.');
            }
            if self.member {
                Before::Operand
            } else {
                after_word(self.word)
            }
        } else {
            Before::Operand
        };
    }

    /// Whether the slash at `at` in the code opens a bare regular expression literal such as `/a/`, as swift-syntax and Swift 6.4.2 read it.
    /// `tryScanOperatorAsRegexLiteral` of swift-syntax tries the first slash of an operator that nothing binds on its left, and it never tries one after `func` or `operator`.
    /// An operator that something binds on its right, such as the `!/` of `!/a/`, is a prefix operator, and the literal opens when `closes_bare` reads its end.
    /// An operator free on both sides, such as `/` in `f(/,a/)` or `/=` in `let r = /= a/`, opens a literal only where an expression starts, as `isInRegexLiteralPosition` reads it.
    /// There the parser of the compiler reads the literal without the test of the parentheses, except where the slash may stand for the operator itself.
    /// `listElementIsBinaryOperator` in `lib/Parse/ParseExpr.cpp` finds that place where an element starts and a comma or a closing parenthesis follows the operator, as in `reduce(1, /)`.
    /// At the start of an expression, `tryLexRegexLiteral` in the same file reads an operator that both of its sides bind as a literal without that test.
    /// It reads no literal at a postfix operator.
    /// Where an expression starts, a slash that a keyword, a vertical tab, or a form feed binds opens a literal when something binds it on its right, as in `return/a)/` and `try!/a/`.
    /// After an operand, an operator free on both sides is binary.
    /// `parseExprSequence` of the compiler refuses a binary operator that a closing bracket, a comma, a semicolon, or a colon follows, because none of them starts an operand.
    /// Such an operator stands at the start of a statement, as on the line after `#endif` or after the body of a declaration in `/,a/`.
    /// The parser reads it there as a literal without the test of the parentheses.
    /// The operators outside ASCII, such as the `±` of `let r = ±/a/` and the `±〡` of `let r = ±〡/a/`, are the operator characters of the compiler.
    /// The compiler tests no parentheses after `,` or `:` outside parentheses, so it reads a literal in `[1, /)a/]` and in `c ? a : /)b/`.
    /// The lexer reads code there, and the compiler then refuses that literal as an unbalanced group.
    fn opens_bare_pattern(&self, at: usize) -> bool {
        let (left, before) = if self.after_leads {
            (self.operator_left, self.operator_before)
        } else {
            (self.binding, self.last)
        };
        let Some(balanced) = closes_bare(self.characters, at + 1) else {
            return false;
        };
        let after = self.ahead.get(at).and_then(|ahead| ahead.after_operator);
        let right = after.is_some_and(|next| !closes_after(next));
        let tentative = match (left, before) {
            (_, Before::Declaration) | (Left::Bound, _) => return false,
            (Left::Reread, _) => return right,
            _ if right => true,
            (_, Before::Operand) => return after.is_some_and(|next| !spacing(next)),
            (_, Before::Element) => after.is_some_and(ends_element),
            (_, Before::Expression | Before::Try) => false,
        };
        balanced || !tentative
    }

    /// Whether two more quotes follow the quote at `at`.
    fn opens_three_quotes(&self, at: usize) -> bool {
        self.followed_by(at, '"') && self.followed_by(at + 1, '"')
    }

    /// The number of pound signs in a row from `at` on.
    fn pounds_from(&self, at: usize) -> usize {
        self.ahead.get(at).map_or(0, |ahead| ahead.pounds)
    }

    /// Whether only blanks and tabs stand between `at` and the end of its line, which a line feed or a carriage return marks.
    fn ends_its_line(&self, at: usize) -> bool {
        self.ahead.get(at).is_some_and(|ahead| ahead.ends_line)
    }

    /// Passes the character at `at` and returns its class.
    fn pass(&mut self, at: usize, character: char) -> Class {
        if let Some(left) = self.left.checked_sub(1) {
            self.left = left;
            return self.rest;
        }
        let (length, class) = self.token(at, character);
        self.left = length.saturating_sub(1);
        self.rest = if class == Class::Escape {
            Class::Escaped
        } else {
            class
        };
        class
    }

    /// The length of the token that starts at `at`, and the class of its first character.
    fn token(&mut self, at: usize, character: char) -> (usize, Class) {
        match self.comment {
            Comment::Line if character == '\n' => self.comment = Comment::None,
            Comment::Line => return (1, Class::Comment),
            Comment::Block(outer) => return self.block_comment(at, character, outer),
            Comment::None => {}
        }
        match self.pattern {
            Some(pattern) if pattern.multiline || character != '\n' => {
                return self.regular_expression(at, character, pattern);
            }
            // A regular expression literal of one line ends with its line, and the code around it reads the line feed.
            Some(_) => self.pattern = None,
            None => {}
        }
        match self.innermost().map(|open| open.kind) {
            Some(Kind::Literal(multiline, pounds)) => self.text(at, character, multiline, pounds),
            _ => self.code(at, character),
        }
    }

    /// The token at `at` inside a block comment that `outer` block comments hold.
    fn block_comment(&mut self, at: usize, character: char, outer: usize) -> (usize, Class) {
        let opens = character == '/' && self.followed_by(at, '*');
        let closes = character == '*' && self.followed_by(at, '/');
        if opens {
            self.comment = Comment::Block(outer + 1);
        }
        if closes {
            self.comment = outer.checked_sub(1).map_or(Comment::None, Comment::Block);
        }
        (if opens || closes { 2 } else { 1 }, Class::Comment)
    }

    /// The token at `at` in the code that stands outside every literal or inside an interpolation.
    /// The lexer of the compiler skips a byte order mark at the start of a source, so the lexer reads it like a comment, which binds nothing.
    fn code(&mut self, at: usize, character: char) -> (usize, Class) {
        let pounds = self.pounds;
        self.pounds = 0;
        match character {
            '\u{feff}' if at == 0 => return (1, Class::Comment),
            '/' if pounds > 0 => return self.open_pattern(at, pounds),
            '/' if self.followed_by(at, '/') => {
                self.comment = Comment::Line;
                return (1, Class::Comment);
            }
            '/' if self.followed_by(at, '*') => {
                self.comment = Comment::Block(0);
                return (2, Class::Comment);
            }
            '/' if self.opens_bare_pattern(at) => return self.open_pattern(at, 0),
            '`' => {
                if let Some(length) = self.raw_identifier(at) {
                    return (length, Class::Code);
                }
            }
            '#' => self.pounds = pounds + 1,
            '"' => return self.open_literal(at, pounds),
            '(' => {
                if let Some(Open {
                    kind: Kind::Interpolation(depth),
                    ..
                }) = self.innermost()
                {
                    *depth += 1;
                }
            }
            ')' => {
                if let Some(Open {
                    kind: Kind::Interpolation(depth),
                    ..
                }) = self.innermost()
                {
                    match depth.checked_sub(1) {
                        Some(outer) => *depth = outer,
                        None => self.level -= 1,
                    }
                }
            }
            '\n' => self.level = self.spanning(),
            _ => {}
        }
        (1, Class::Code)
    }

    /// The length of the raw identifier whose opening backtick stands at `at`, which runs to the next backtick on its line, as in `` `per /day` ``.
    /// `lexEscapedIdentifier` in `Sources/SwiftParser/Lexer/Cursor.swift` of swift-syntax reads it as one name, so no comment, literal, or regular expression literal opens inside it.
    /// A backtick without a partner on its line is `None`, and it stays one character of the code.
    /// Each turn of the loop moves one character on, and the end of the source stops it.
    /// `lexEscapedIdentifier` in `lib/Parse/Lexer.cpp` of Swift 6.4.2 reads a lone backtick where a control character, a backslash, or a blank other than the space stands between two backticks.
    /// It does the same where the two backticks hold nothing, only blanks, or only operator characters.
    /// The compiler then refuses the source, so the lexer reads those two backticks as one name.
    fn raw_identifier(&self, at: usize) -> Option<usize> {
        let mut end = at;
        loop {
            end += 1;
            match self.characters.get(end) {
                Some('`') => return Some(end + 1 - at),
                Some('\n') | None => return None,
                Some(_) => {}
            }
        }
    }

    /// Opens the literal whose first quote stands at `at`, after `pounds` pound signs.
    /// Three quotes open a literal that spans lines only where blanks and tabs alone stand between them and the end of their line.
    /// `lexStringLiteral` in `lib/Parse/Lexer.cpp` of Swift 6.4.2 refuses anything else there, as in `"""a`, and the lexer then opens a literal of one line at the first quote, as in `#"""#`.
    /// A quote that the lexer misreads, such as one inside a regular expression literal that it reads as code, then never hides more than its line.
    fn open_literal(&mut self, at: usize, pounds: usize) -> (usize, Class) {
        let multiline = self.opens_three_quotes(at) && self.ends_its_line(at + 3);
        self.open(multiline, Kind::Literal(multiline, pounds));
        (if multiline { 3 } else { 1 }, Class::Code)
    }

    /// Opens the regular expression literal whose slash stands at `at`, after `pounds` pound signs.
    /// It spans lines when only blanks and tabs follow its slash on its line and a line feed may stand where it opens.
    /// It also needs a closing slash with the same pound signs later in the source.
    /// Swift 6.4.2 refuses an opening delimiter that ends its line and never closes, as in `#/` alone, and reads the next line as code.
    /// The lexer then ends the literal with its line, as it ends a literal of one line that never closes, so the misread hides no later line.
    /// The opening slash closes nothing itself, because a blank or a line end follows it there.
    fn open_pattern(&mut self, at: usize, pounds: usize) -> (usize, Class) {
        let multiline = self.ends_its_line(at + 1)
            && self.spanning() == self.level
            && self
                .ahead
                .get(at)
                .is_some_and(|ahead| ahead.closers >= pounds);
        self.pattern = Some(Pattern { pounds, multiline });
        (1, Class::Code)
    }

    /// The token at `at` inside the regular expression literal that `pattern` describes.
    /// A backslash escapes the character after it, so an escaped slash closes nothing.
    fn regular_expression(
        &mut self,
        at: usize,
        character: char,
        pattern: Pattern,
    ) -> (usize, Class) {
        match character {
            '/' if self.pounds_from(at + 1) >= pattern.pounds => {
                self.pattern = None;
                (1 + pattern.pounds, Class::Code)
            }
            '\\' => {
                let escapes = self
                    .characters
                    .get(at + 1)
                    .is_some_and(|next| pattern.multiline || *next != '\n');
                (1 + usize::from(escapes), Class::Pattern)
            }
            _ => (1, Class::Pattern),
        }
    }

    /// The token at `at` in the text of the innermost literal, which `pounds` pound signs delimit.
    fn text(
        &mut self,
        at: usize,
        character: char,
        multiline: bool,
        pounds: usize,
    ) -> (usize, Class) {
        let quotes = if multiline { 3 } else { 1 };
        match character {
            '\\' if self.pounds_from(at + 1) >= pounds => {
                let next = self.characters.get(at + 1 + pounds).copied();
                if next == Some('(') {
                    self.open(multiline, Kind::Interpolation(0));
                    return (pounds + 2, Class::Code);
                }
                // The line feed that ends a literal of one line stays outside the escape.
                let escapes = next.is_some_and(|next| multiline || next != '\n');
                (pounds + 1 + usize::from(escapes), Class::Escape)
            }
            '"' if (!multiline || self.opens_three_quotes(at))
                && self.pounds_from(at + quotes) >= pounds =>
            {
                self.level -= 1;
                (quotes + pounds, Class::Code)
            }
            '\n' if !multiline => {
                self.level = self.spanning();
                (1, Class::Code)
            }
            _ => (1, Class::Text),
        }
    }
}

/// What a source holds from one place on, which the lexer reads ahead of that place.
#[derive(Clone, Copy)]
struct Ahead {
    /// The number of pound signs in a row from the place on.
    pounds: usize,
    /// The most pound signs that follow a slash that no backslash escapes, from the place on.
    /// A regular expression literal that opens at the place may close only where this number reaches its own pound signs.
    /// An odd number of backslashes right before a slash escapes it.
    /// A literal that spans lines opens with a slash that a blank or a line end follows, so no backslash before it escapes a slash inside it.
    /// This one reading serves every such literal.
    closers: usize,
    /// Whether only blanks and tabs stand between the place and the end of its line, which the line feed or the carriage return at the place also makes true.
    ends_line: bool,
    /// The character after the operator that starts at the place, which is `None` where the source ends or a comment opens after the operator.
    /// The operator runs over the operator characters and stops before a comment, which stands between two tokens like a blank.
    /// The lexer reads it only at a slash, and each operator character after a slash continues its operator, as `step` reads it.
    after_operator: Option<char>,
}

/// Whether a comment opens at `at` of `characters`.
fn opens_comment(characters: &[char], at: usize) -> bool {
    characters.get(at) == Some(&'/') && matches!(characters.get(at + 1), Some('/' | '*'))
}

/// What `characters` holds from each place on, read in one pass from the last character to the first.
/// One pass keeps the bounded proofs inside the memory of their container, where four passes with the same work didn't fit.
/// A slash waits in `pending` with the pound signs after it until the pass meets the character before its backslashes.
/// Their number then decides whether they escape it.
fn ahead(characters: &[char]) -> Vec<Ahead> {
    let mut pounds = 0;
    let mut closers = 0;
    let mut pending: Option<(usize, usize)> = None;
    let mut ends_line = false;
    let mut after_operator = None;
    let mut found = characters
        .iter()
        .enumerate()
        .rev()
        .map(|(at, &character)| {
            pending = match pending {
                Some((after, backslashes)) if character == '\\' => Some((after, backslashes + 1)),
                Some((after, backslashes)) => {
                    if backslashes % 2 == 0 {
                        closers = closers.max(after);
                    }
                    None
                }
                None => None,
            };
            if character == '/' {
                pending = Some((pounds, 0));
            }
            pounds = if character == '#' { pounds + 1 } else { 0 };
            ends_line = line_end(character) || (blank(character) && ends_line);
            let comment = opens_comment(characters, at);
            if !operator(character) || comment {
                after_operator = (!comment).then_some(character);
            }
            Ahead {
                pounds,
                closers,
                ends_line,
                after_operator,
            }
        })
        .collect::<Vec<_>>();
    found.reverse();
    found
}

/// Whether `character` belongs to a name, an operator, or neither after a character that belongs to `run`, as the lexical structure reads each token to its longest form.
/// A combining mark such as U+0301 may continue both a name and an operator.
/// The token right before it decides which, as in the name `returń` and the operator `±́`.
/// The lexical structure starts a name at a dollar sign, as in `$in`, and the lexer of the compiler also continues a name with one, as in `a$b`.
fn step(run: Run, character: char) -> Run {
    let name = identifier_head(character) || character == '$';
    let operator = operator_head(character) || character == '.';
    match run {
        Run::Word if name || identifier_tail(character) => Run::Word,
        Run::Operator if operator || operator_tail(character) => Run::Operator,
        _ if name => Run::Word,
        _ if operator => Run::Operator,
        _ => Run::Other,
    }
}

/// Whether a character that belongs to `run` stands in an operator before its first slash, which every operator character other than the slash may, as the `!` of `!/a/` does.
/// The period of a dot operator such as `.+` stands there too, because the compiler reads what binds the whole operator from its first character.
/// A combining mark continues the name before it, as in `returń`, so it stands in no operator there.
fn leads(run: Run, character: char) -> bool {
    run == Run::Operator && character != '/'
}

/// Packs `word` into seven bits for each character, which keeps every two words of up to eighteen ASCII characters distinct.
/// The lexer packs each word that it passes the same way, a character at a time, so it compares a word with a keyword without a loop.
/// A longer word keeps its last eighteen characters, and none of them is zero, so it never packs like a keyword, which is shorter.
const fn spell(word: &[u8]) -> u128 {
    match word {
        [] => 0,
        [rest @ .., last] => (spell(rest) << 7) + *last as u128,
    }
}

/// Whether `word`, as `spell` packs it, is one of the keywords after it.
macro_rules! spells {
    ($word:expr, $($keyword:literal),+) => {
        false $(|| $word == const { spell($keyword.as_bytes()) })+
    };
}

/// What the word before an operator, as `spell` packs it, says about a regular expression literal at that operator.
/// The keywords are the ones that the lexer of swift-syntax classifies, in `Sources/SwiftParser/generated/IsLexerClassified.swift`, and `await`, before which the parser of the compiler reads an expression.
/// `true`, `false`, `Any`, `nil`, `self`, `Self`, and `super` are expressions themselves, so they end an operand like a name.
fn after_word(word: u128) -> Before {
    if spells!(word, "func", "operator") {
        Before::Declaration
    } else if spells!(word, "try") {
        Before::Try
    } else if spells!(
        word,
        "as",
        "associatedtype",
        "await",
        "break",
        "case",
        "catch",
        "class",
        "continue",
        "default",
        "defer",
        "deinit",
        "do",
        "else",
        "enum",
        "extension",
        "fallthrough",
        "fileprivate",
        "for",
        "guard",
        "if",
        "import",
        "in",
        "init",
        "inout",
        "internal",
        "is",
        "let",
        "precedencegroup",
        "private",
        "protocol",
        "public",
        "repeat",
        "rethrows",
        "return",
        "static",
        "struct",
        "subscript",
        "switch",
        "throw",
        "throws",
        "typealias",
        "var",
        "where",
        "while",
        "yield"
    ) {
        Before::Expression
    } else {
        Before::Operand
    }
}

/// Whether a bare regular expression literal whose contents start at `from` of `characters` ends on its line, as Swift 6.4.2 reads it, and if so, whether its parentheses balance.
/// `tryScanRegexLiteral` in `lib/Parse/Lexer.cpp` refuses contents that start with a blank.
/// `DelimiterLexing.swift` ends the contents at the first slash that no backslash escapes.
/// It refuses a control character other than the null character before that slash, even after a backslash.
/// `tryScanRegexLiteral` then refuses a closing slash where a comment opens, and contents that end with a blank unless a backslash stands right before the blank.
/// The parentheses balance when each closing parenthesis outside the character classes closes a group that the contents opened, which a tentative literal needs.
/// A character class runs from `[` to the `]` that matches it, and the classes nest, while a `]` outside every class is a character of the pattern.
fn closes_bare(characters: &[char], from: usize) -> Option<bool> {
    if characters.get(from) == Some(&' ') {
        return None;
    }
    let mut escaped = false;
    let mut classes = 0_usize;
    let mut groups = 0_usize;
    let mut balanced = true;
    for (at, &character) in characters.iter().enumerate().skip(from) {
        match character {
            _ if unprintable(character) => return None,
            _ if escaped => escaped = false,
            '\\' => escaped = true,
            '/' => {
                let back = |distance| {
                    at.checked_sub(distance)
                        .and_then(|before| characters.get(before))
                        .copied()
                };
                let ends_with_a_blank = back(1) == Some(' ') && back(2) != Some('\\');
                return (!ends_with_a_blank && !opens_comment(characters, at)).then_some(balanced);
            }
            '[' => classes += 1,
            ']' => classes = classes.saturating_sub(1),
            '(' if classes == 0 => groups += 1,
            ')' if classes == 0 => match groups.checked_sub(1) {
                Some(outer) => groups = outer,
                None => balanced = false,
            },
            _ => {}
        }
    }
    None
}

/// One mark for each character of `characters`, read from the first one to the last one.
fn classify(characters: &[char]) -> Vec<Mark> {
    let unused = Open {
        kind: Kind::Interpolation(0),
        spanning: 0,
    };
    let mut lexer = Lexer {
        characters,
        ahead: ahead(characters),

        run: Run::Other,
        previous: Run::Other,
        binding: Left::Free,
        after_leads: false,
        marks: Vec::with_capacity(characters.len()),
        last: Before::Expression,
        operator_left: Left::Free,
        operator_before: Before::Expression,
        word: 0,
        member: false,
        postfix: false,
        comment: Comment::None,
        pattern: None,
        pounds: 0,
        places: vec![unused; characters.len()],
        level: 0,
        left: 0,
        rest: Class::Code,
    };
    for (at, &character) in characters.iter().enumerate() {
        lexer.previous = lexer.run;
        lexer.run = step(lexer.run, character);
        lexer.binding = lexer.left_of(at);
        lexer.after_leads = lexer.leads_before(at);
        lexer.start_operator(character);
        let class = lexer.pass(at, character);
        let level = lexer.level;
        lexer.marks.push(Mark { class, level });
        lexer.follow(at, character, class);
    }
    lexer.marks
}

/// The code-only view of `characters`, with one character for each of them.
/// A character outside the code shows as a blank, and a line feed always shows.
fn view(characters: &[char], marks: &[Mark]) -> Vec<char> {
    characters
        .iter()
        .zip(marks)
        .map(|(&character, mark)| {
            if mark.class == Class::Code || character == '\n' {
                character
            } else {
                ' '
            }
        })
        .collect()
}

/// Where a literal or an interpolation stands in its source.
struct Span {
    /// The line where it opens.
    line: usize,
    /// The level of the marks that it holds.
    level: usize,
    /// The place of the opening quote of a literal, or of the backslash that opens an interpolation.
    from: usize,
    /// The place where it ends.
    to: usize,
}

impl Span {
    fn is_literal(&self) -> bool {
        self.level % 2 == 1
    }

    /// The part of `items` that the span holds, where `items` holds one item for each character of the source.
    fn of<'a, T>(&self, items: &'a [T]) -> &'a [T] {
        items.get(self.from..self.to).unwrap_or_default()
    }
}

/// The literals and the interpolations of a source, in the order in which they end.
/// The level rises by one where one of them opens and falls where one or more of them end.
fn spans(characters: &[char], marks: &[Mark]) -> Vec<Span> {
    let mut open = Vec::new();
    let mut found = Vec::new();
    let mut line = 1;
    // A level of zero after the last character ends what the source leaves open.
    for at in 0..=marks.len() {
        let level = marks.get(at).map_or(0, |mark| mark.level);
        for _ in level..open.len() {
            let ended = open.len();
            if let Some((opened, from)) = open.pop() {
                found.push(Span {
                    line: opened,
                    level: ended,
                    from,
                    to: at,
                });
            }
        }
        if open.len() < level {
            open.push((line, at));
        }
        if characters.get(at) == Some(&'\n') {
            line += 1;
        }
    }
    found
}

/// The characters of `source` with their marks.
fn lex(source: &str) -> (Vec<char>, Vec<Mark>) {
    let characters = source.chars().collect::<Vec<_>>();
    let marks = classify(&characters);
    (characters, marks)
}

/// The code of a Swift file, with a blank in place of each character of a comment or of a literal's text.
/// Every character keeps its place and every line feed stays, so a finding can name its line.
/// The code of an interpolation stays, because it runs like the code around the literal.
pub fn code_only(source: &str) -> String {
    let (characters, marks) = lex(source);
    view(&characters, &marks).into_iter().collect()
}

/// The string literals of a Swift file, in the order in which they end.
/// A literal that the source or its line cuts short still counts, with the text that it holds.
pub fn literals(source: &str) -> Vec<Literal> {
    let (characters, marks) = lex(source);
    literals_in(&spans(&characters, &marks), &characters, &marks)
}

/// The literals among `spans`, which a source with `characters` and `marks` holds.
fn literals_in(spans: &[Span], characters: &[char], marks: &[Mark]) -> Vec<Literal> {
    spans
        .iter()
        .filter(|span| span.is_literal())
        .map(|span| Literal {
            line: span.line,
            text: span
                .of(characters)
                .iter()
                .zip(span.of(marks))
                .filter(|(_, mark)| mark.level == span.level)
                .filter_map(|(character, mark)| match mark.class {
                    Class::Text => Some(*character),
                    Class::Escape => Some(' '),
                    _ => None,
                })
                .collect(),
        })
        .collect()
}

/// The interpolations of a Swift file, in the order in which they end.
pub fn interpolations(source: &str) -> Vec<Interpolation> {
    let (characters, marks) = lex(source);
    interpolations_in(&spans(&characters, &marks), &view(&characters, &marks))
}

/// The interpolations among `spans`, with their code from `code`, the code-only view of their source.
fn interpolations_in(spans: &[Span], code: &[char]) -> Vec<Interpolation> {
    spans
        .iter()
        .filter(|span| !span.is_literal())
        .map(|span| Interpolation {
            line: span.line,
            code: span
                .of(code)
                .iter()
                .skip_while(|shown| **shown != '(')
                .skip(1)
                .collect(),
        })
        .collect()
}

pub fn identifier(character: char) -> bool {
    character.is_alphanumeric() || character == '_'
}

/// Whether `code` names `name` as a whole identifier.
pub fn names(code: &str, name: &str) -> bool {
    code.match_indices(name).any(|(at, _)| {
        !code[..at].chars().next_back().is_some_and(identifier)
            && !code[at + name.len()..]
                .chars()
                .next()
                .is_some_and(identifier)
    })
}

fn swift_files(directory: &Path, found: &mut Vec<PathBuf>) -> Result<()> {
    let entries = fs::read_dir(directory).context(|| format!("Read {}", directory.display()))?;
    for entry in entries {
        let path = entry
            .context(|| format!("Read {}", directory.display()))?
            .path();
        if path.is_dir() {
            swift_files(&path, found)?;
        } else if path
            .extension()
            .is_some_and(|extension| extension == "swift")
        {
            found.push(path);
        }
    }
    Ok(())
}

/// Every Swift file under `directories`, in path order, and never an empty set.
pub fn read(root: &Path, directories: &[&str]) -> Result<Vec<Source>> {
    let mut files = Vec::new();
    for directory in directories {
        swift_files(&root.join(directory), &mut files)?;
    }
    files.sort();
    ensure(!files.is_empty(), || {
        format!("Found no Swift files under {}", directories.join(", "))
    })?;
    files
        .iter()
        .map(|file| {
            let relative = file
                .strip_prefix(root)
                .context(|| format!("Locate {}", file.display()))?;
            Ok(Source {
                file: relative.display().to_string(),
                text: fs::read_to_string(file).context(|| format!("Read {}", file.display()))?,
            })
        })
        .collect()
}

/// Bounded proofs about the lexer, which Kani checks for every source of each length up to three over every character.
/// Three characters are the shortest source that holds a bare regular expression literal, such as `/a/`.
/// The test `every_source_of_up_to_four_characters_keeps_each_place_and_each_line_feed` runs every source of up to four characters over one character for each set of characters that the lexer reads alike.
#[cfg(kani)]
mod proofs {
    use super::{Class, Mark, classify, view};

    /// Reads every source of `N` characters and returns it with its marks.
    /// The code-only view holds one character for each character of the source: that character or a blank, and the line feed wherever the source holds one.
    /// The level rises by at most one from a character to the next, and the text of a literal stands at an odd level.
    /// The contents of a regular expression literal stand in code, at an even level.
    fn check<const N: usize>() -> ([char; N], Vec<Mark>) {
        let characters: [char; N] = kani::any();
        let marks = classify(&characters);
        let code = view(&characters, &marks);
        assert!(marks.len() == N);
        assert!(code.len() == N);
        let mut before = 0;
        for ((shown, character), mark) in code.iter().zip(&characters).zip(&marks) {
            assert!(shown == character || (*shown == ' ' && *character != '\n'));
            assert!(mark.level <= before + 1);
            let text = matches!(mark.class, Class::Text | Class::Escape | Class::Escaped);
            assert!(!text || mark.level % 2 == 1);
            assert!(mark.class != Class::Pattern || mark.level % 2 == 0);
            before = mark.level;
        }
        (characters, marks)
    }

    /// The level after the last character of a source, which is zero for the empty source.
    fn last_level(marks: &[Mark]) -> usize {
        marks.last().map_or(0, |mark| mark.level)
    }

    #[kani::proof]
    #[kani::unwind(1)]
    fn the_empty_source_gives_an_empty_view() {
        let marks = classify(&[]);
        assert!(marks.is_empty());
        assert!(view(&[], &marks).is_empty());
        kani::cover!(marks.is_empty(), "the empty source gives no mark");
    }

    #[kani::proof]
    #[kani::unwind(2)]
    fn every_source_of_one_character_keeps_its_place_and_its_line_feed() {
        let (_, marks) = check::<1>();
        kani::cover!(last_level(&marks) == 1, "a source opens a literal");
    }

    /// `Vec::reverse` in `ahead` swaps the two records of a source of two characters eight bytes at a time.
    /// That takes four turns of a loop of the standard library, so the bound is four.
    #[kani::proof]
    #[kani::unwind(4)]
    fn every_source_of_two_characters_keeps_each_place_and_each_line_feed() {
        let (_, marks) = check::<2>();
        kani::cover!(
            last_level(&marks) == 0 && marks.iter().any(|mark| mark.level == 1),
            "a source closes the literal that it opens"
        );
    }

    /// The shortest bare regular expression literal, such as `/a/`, takes three characters.
    /// The cover holds only where the first character opens a bare literal, because a literal between pound signs needs a pound sign before its slash.
    #[kani::proof]
    #[kani::unwind(4)]
    fn every_source_of_three_characters_keeps_each_place_and_each_line_feed() {
        let (characters, marks) = check::<3>();
        kani::cover!(
            characters[0] == '/' && marks[1].class == Class::Pattern,
            "a source opens a bare regular expression literal at its first character"
        );
    }
}

/// A small repository in a fresh temporary directory, for the tests of the checks.
#[cfg(test)]
pub mod fixture {
    use crate::failure::{Context, Result};
    use std::{
        env, fs,
        path::{Path, PathBuf},
        process,
    };

    /// The beginnings of eleven sources that hold quotes inside a comment or inside a regular expression literal.
    /// The first three comments stand right after the backslash of a key path.
    /// The later beginnings hold a character class with a closing parenthesis, a slash that a separator follows where an expression starts, or a slash right after a block comment.
    /// Each of the last five puts a construct with one quote before or after it.
    /// Swift 6.4.2 type-checks each beginning with a statement after it, given a structure `S` with an `Int` property `count` and a function `f` that takes a `Regex<Substring>`.
    /// Each beginning comes with the line on which the code after it stands.
    pub const AFTER_SLASHES: [(&str, usize); 11] = [
        ("let j: KeyPath<S, Int> = \\/* \" */.count; ", 1),
        ("let k: KeyPath<S, Int> = \\/* \"\"\" */.count\n", 2),
        ("let k: KeyPath<S, Int> = \\// \"\"\"\n  .count\n", 3),
        ("let r = /\\/* \" */; ", 1),
        ("let q = /\\/* \"\"\" */\n", 2),
        ("let r = /\"/; ", 1),
        ("let quote = #/\"/#\nlet closer = /[)\"]/; ", 2),
        ("f(/,a\"/); let s = #\"\"\"\n  a \"# b\n  \"\"\"#\n", 4),
        ("let quote = #/\"/#\nf(/,a\"/); ", 2),
        ("let quote = #/\"/#\nf(/]a\"/); ", 2),
        ("let quote = #/\"/#\nlet r = /**//a\"/; ", 2),
    ];

    /// The beginnings of sixteen sources whose regular expression literal holds three quotes or the mark of a comment.
    /// If the lexer read the literal as code, those would hide later lines.
    /// The first six open the literal right after a keyword where an expression starts, as in `return/"""a"/`, and the sixth puts a block comment after it.
    /// The seventh opens the literal right after the prefix operator `±`, whose character lies outside ASCII.
    /// The next four open the literal free on both sides on the line after `#endif` or after the body of a function.
    /// The last two of those four put a block comment after it.
    /// The twelfth opens the literal after `±` and puts a block comment after it, as the screen of `OPERATOR_SCREEN` does.
    /// The thirteenth opens the literal right after the byte order mark at the start of its source.
    /// The fourteenth opens the literal after the prefix operator `.+`, which starts with a period, and puts a block comment after it.
    /// The fifteenth opens the literal right after `yield` in a `_read` accessor, as the reviewer's e7 does, and puts a block comment after it.
    /// The last opens the literal after the prefix operator `±〡`, which U+3021 continues, as the reviewer's e8 does, and puts a block comment after it.
    /// Swift 6.4.2 type-checks each beginning with a statement after it, and each comes with the line on which the code after it stands.
    pub const AFTER_PATTERNS: [(&str, usize); 16] = [
        (
            "func g() -> Regex<Substring> {\n  return/\"\"\"a\"/\n}\n",
            4,
        ),
        (
            "func g() throws -> Regex<Substring> {\n  try/\"\"\"a\"/\n}\n",
            4,
        ),
        ("func g() -> Regex<Substring>? {\n  try?/\"\"\"a\"/\n}\n", 4),
        ("let f: () -> Regex<Substring> = { () in/\"\"\"a\"/ }\n", 2),
        (
            "func g() async -> Regex<Substring> {\n  await/\"\"\"a\"/\n}\n",
            4,
        ),
        (
            "func g() -> Regex<Substring> {\n  return/\\/*/\n}\n/* note */\n",
            5,
        ),
        (
            "prefix operator ±\nprefix func ±(r: Regex<Substring>) -> Regex<Substring> { r }\nlet r = ±/\"\"\"a\"/\n",
            4,
        ),
        ("#if DEBUG\n#endif\n/,\"\"\"a\"/\n", 4),
        ("func f() {}\n/,\"\"\"a\"/\n", 3),
        ("#if DEBUG\n#endif\n/,\\/*/\n/* note */\n", 5),
        ("func f() {}\n/,\\/*/\n/* note */\n", 4),
        (
            "prefix operator ±\nprefix func ±(r: Regex<Substring>) -> Regex<Substring> { r }\nlet r = ±/\\/*/\n/* note */\n",
            5,
        ),
        ("\u{feff}/\\/*/\n/* note */\n", 3),
        (
            "prefix operator .+\nprefix func .+(r: Regex<Substring>) -> Regex<Substring> { r }\nlet r = .+/\\/*/\n/* note */\n",
            5,
        ),
        (
            "struct Holder {\n  var stored: Regex<Substring> = /a/\n  var pattern: Regex<Substring> {\n    _read { yield/\\/*/ }\n  }\n}\n/* note */\n",
            8,
        ),
        (
            "prefix operator ±\u{3021}\nprefix func ±\u{3021}(r: Regex<Substring>) -> Regex<Substring> { r }\nlet r = ±\u{3021}/\\/*/\n/* note */\n",
            5,
        ),
    ];

    /// A screen whose regular expression literal opens right after `return` and holds three quotes, which Swift 6.4.2 type-checks for the iOS 26 simulator without a diagnostic.
    /// Line 8 names a clock, the network, the console, and a file timestamp key, and line 9 shows text and a fixed hue.
    pub const KEYWORD_SCREEN: &str = "import SwiftUI\nfunc pattern(_ strict: Bool) -> Regex<Substring> {\n  if strict { return/\"\"\"a\"/ } else { return /b/ }\n}\nstruct Row: View {\n  var v: URL\n  var body: some View {\n    let d = Date(); let s = URLSession.shared; print(s); let t = try? v.resourceValues(forKeys: [.contentModificationDateKey]); _ = (d, t)\n    return Text(\"Log set\").foregroundStyle(.blue)\n  }\n}\n";

    /// A screen whose regular expression literal opens right after the prefix operator `±` and holds the mark of a block comment.
    /// Swift 6.4.2 type-checks it as a library for the iOS 26 simulator without a diagnostic.
    /// The block comment on line 7 would close only the inner one of two nested comments if the lexer read the literal as code.
    /// Line 8 names a clock, the network, the console, and the user defaults, and line 9 shows text and a fixed hue.
    pub const OPERATOR_SCREEN: &str = "import SwiftUI\nprefix operator ±\nprefix func ±(r: Regex<Substring>) -> Regex<Substring> { r }\nstruct Row: View {\n  var body: some View {\n    let r = ±/\\/*/\n    /* note */\n    let d = Date(); let s = URLSession.shared; print(s); let u = UserDefaults.standard; _ = (r, d, u)\n    return Text(\"Log set\").foregroundStyle(.blue)\n  }\n}\n";

    /// One file under `directory` for each beginning of `beginnings`, which holds that beginning, then `code`, and a line feed.
    /// Each filename is `stem` and the place of its beginning in two digits from `01` on, so the path order of the files is the order of `beginnings`.
    fn after(
        beginnings: &[(&str, usize)],
        stem: &str,
        directory: &str,
        code: &str,
    ) -> Vec<(String, String)> {
        beginnings
            .iter()
            .enumerate()
            .map(|(index, (beginning, _))| {
                (
                    format!("{directory}/{stem}{:02}.swift", index + 1),
                    format!("{beginning}{code}\n"),
                )
            })
            .collect()
    }

    /// The place of the code after each beginning of `beginnings`, as `file:line` under `directory`, for the files of `after`.
    fn places_after(beginnings: &[(&str, usize)], stem: &str, directory: &str) -> Vec<String> {
        beginnings
            .iter()
            .enumerate()
            .map(|(index, (_, line))| format!("{directory}/{stem}{:02}.swift:{line}", index + 1))
            .collect()
    }

    /// One file under `directory` for each beginning of `AFTER_SLASHES`, from `Slash01.swift` on, which holds that beginning, then `code`, and a line feed.
    pub fn after_slashes(directory: &str, code: &str) -> Vec<(String, String)> {
        after(&AFTER_SLASHES, "Slash", directory, code)
    }

    /// The place of the code after each beginning of `AFTER_SLASHES`, as `file:line` under `directory`.
    pub fn places_after_slashes(directory: &str) -> Vec<String> {
        places_after(&AFTER_SLASHES, "Slash", directory)
    }

    /// One file under `directory` for each beginning of `AFTER_PATTERNS`, from `Pattern01.swift` on, which holds that beginning, then `code`, and a line feed.
    pub fn after_patterns(directory: &str, code: &str) -> Vec<(String, String)> {
        after(&AFTER_PATTERNS, "Pattern", directory, code)
    }

    /// The place of the code after each beginning of `AFTER_PATTERNS`, as `file:line` under `directory`.
    pub fn places_after_patterns(directory: &str) -> Vec<String> {
        places_after(&AFTER_PATTERNS, "Pattern", directory)
    }

    /// The code before and after a statement on one line.
    /// A slash before the statement names or references an operator, and a slash after it divides or opens a regular expression literal.
    /// The fifth puts a comment between `func` and the name of the operator, and the last puts quotes inside two regular expression literals.
    /// Swift 6.4.2 parses each line with a statement in its place.
    pub const AROUND_OPERATORS: [(&str, &str); 9] = [
        (
            "func /(lhs: S, rhs: S) -> S { ",
            "; return S(v: lhs.v/rhs.v) }",
        ),
        (
            "struct T { var v: Int; static func /=(lhs: inout T, rhs: T) { ",
            "; lhs.v = lhs.v/rhs.v } }",
        ),
        (
            "struct U { var v: Int; static func /<I: BinaryInteger>(lhs: U, rhs: I) -> U { ",
            "; return U(v: lhs.v/Int(rhs)) } }",
        ),
        (
            "infix operator /%: MultiplicationPrecedence; func /%(lhs: Int, rhs: Int) -> Int { ",
            "; return lhs/rhs }",
        ),
        (
            "extension Double { static func /* c */ /(lhs: Double, rhs: Weight) -> Double { ",
            "; return lhs/rhs.grams } }",
        ),
        ("prefix operator /; ", "; let h = m/2"),
        (
            "let ops: [(Int, Int) -> Int] = [(/), (*)]; ",
            "; let h = m/2",
        ),
        ("let product = [1.0, 2.0].reduce(1, /); ", "; let h = m/2"),
        ("let patterns = [/\"/, 0] as [Any]; ", "; let more = [/\"/]"),
    ];

    /// The code before and after a statement on one line, with a raw identifier before the statement.
    /// The raw identifier holds a slash, a pound sign and a slash, a quote, or the mark of a comment.
    /// [SE-0451](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0451-escaped-identifiers.md) lets a name between backticks hold each of them, and none of them opens anything there.
    /// Each line divides after the statement, so a regular expression literal that opened inside the raw identifier would run over the statement.
    /// Swift 6.4.2 parses each line with a statement in its place.
    pub const AROUND_RAW_IDENTIFIERS: [(&str, &str); 7] = [
        ("let `per /day` = 1; ", "; let rate = 4/2"),
        ("let `a #/b` = 1; ", "; let rate = 4/2"),
        ("func `divide a /b`() {}; ", "; let y = 4/2"),
        ("enum Unit { case `kg/m`, `lb /in` }; ", "; let y = 4/2"),
        ("let `a\"` = 1; ", "; let y = 4/2"),
        ("let `a //` = 1; ", "; let y = 4/2"),
        ("let `a /*` = 1; ", "; let y = 4/2"),
    ];

    /// One file under `directory` for each line of `lines`, which holds `code` in the place of the statement.
    /// Each filename is `stem` and the place of its line in two digits from `01` on, so the path order of the files is the order of `lines`.
    fn around(
        lines: &[(&str, &str)],
        stem: &str,
        directory: &str,
        code: &str,
    ) -> Vec<(String, String)> {
        lines
            .iter()
            .enumerate()
            .map(|(index, (before, after))| {
                (
                    format!("{directory}/{stem}{:02}.swift", index + 1),
                    format!("{before}{code}{after}\n"),
                )
            })
            .collect()
    }

    /// The place of the statement of each line of `lines`, as `file:line` under `directory`, for the files of `around`.
    fn places(lines: &[(&str, &str)], stem: &str, directory: &str) -> Vec<String> {
        (1..=lines.len())
            .map(|number| format!("{directory}/{stem}{number:02}.swift:1"))
            .collect()
    }

    /// One file under `directory` for each line of `AROUND_OPERATORS`, from `Operator01.swift` on, which holds `code` in the place of the statement.
    pub fn around_operators(directory: &str, code: &str) -> Vec<(String, String)> {
        around(&AROUND_OPERATORS, "Operator", directory, code)
    }

    /// The place of the statement of each line of `AROUND_OPERATORS`, as `file:line` under `directory`.
    pub fn places_around_operators(directory: &str) -> Vec<String> {
        places(&AROUND_OPERATORS, "Operator", directory)
    }

    /// One file under `directory` for each line of `AROUND_RAW_IDENTIFIERS`, from `Raw01.swift` on, which holds `code` in the place of the statement.
    pub fn around_raw_identifiers(directory: &str, code: &str) -> Vec<(String, String)> {
        around(&AROUND_RAW_IDENTIFIERS, "Raw", directory, code)
    }

    /// The place of the statement of each line of `AROUND_RAW_IDENTIFIERS`, as `file:line` under `directory`.
    pub fn places_around_raw_identifiers(directory: &str) -> Vec<String> {
        places(&AROUND_RAW_IDENTIFIERS, "Raw", directory)
    }

    /// The directory of one test, which the drop removes.
    pub struct Tree {
        root: PathBuf,
    }

    impl Tree {
        /// Writes each file of `files` under a new directory.
        /// `name` and the process identifier make the directory unique, so the tests of one run and of two runs never share one.
        pub fn new<P: AsRef<Path>, T: AsRef<[u8]>>(name: &str, files: &[(P, T)]) -> Result<Self> {
            let root = env::temp_dir().join(format!("gymemo-xtask-{name}-{}", process::id()));
            if root.exists() {
                fs::remove_dir_all(&root).context(|| format!("Remove {}", root.display()))?;
            }
            fs::create_dir(&root).context(|| format!("Create {}", root.display()))?;
            let tree = Self { root };
            for (path, text) in files {
                let file = tree.root.join(path);
                if let Some(directory) = file.parent() {
                    fs::create_dir_all(directory)
                        .context(|| format!("Create {}", directory.display()))?;
                }
                fs::write(&file, text).context(|| format!("Write {}", file.display()))?;
            }
            Ok(tree)
        }

        pub fn root(&self) -> &Path {
            &self.root
        }
    }

    impl Drop for Tree {
        fn drop(&mut self) {
            if let Err(error) = fs::remove_dir_all(&self.root) {
                eprintln!("Remove {}: {error}", self.root.display());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{fixture::Tree, *};
    use crate::failure::Failure;

    /// Each character at an edge of a range of the character sets, with five verdicts of Swift 6.4.2.
    /// The edges are the first and the last character of each range and the characters right before and right after it.
    /// The ranges are those of the [lexical structure](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/), as `LexicalStructure.md` of swift-book states them at commit 16a2a4c, and those of the lexer of the compiler.
    /// The lexer of the compiler takes them from `isValidIdentifierStartCodePoint` and `isValidIdentifierContinuationCodePoint` in `lib/Parse/Lexer.cpp` and from `isOperatorStartCodePoint` and `isOperatorContinuationCodePoint` in `include/swift/AST/Identifier.h`.
    /// For a character `c`, each verdict says whether `swiftc -frontend -dump-parse -swift-version 6 -parse-as-library` parses one source without an error.
    /// The sources are `let cz = 0`, `func zcy() {}`, `prefix operator c~`, `prefix operator ~c~`, and `letcz = 0`, in that order, each with a line feed after it.
    /// `target/oracle/edges` of the scratch directory wrote the table from those runs.
    const EDGES: [(char, bool, bool, bool, bool, bool); 248] = [
        ('\u{0}', true, false, true, false, true),
        ('\u{1}', false, false, false, false, false),
        ('\u{8}', false, false, false, false, false),
        ('\u{9}', true, false, true, false, true),
        ('\u{a}', true, false, true, false, true),
        ('\u{b}', true, false, true, false, true),
        ('\u{c}', true, false, true, false, true),
        ('\u{d}', true, false, true, false, true),
        ('\u{e}', false, false, false, false, false),
        ('\u{1f}', false, false, false, false, false),
        ('\u{20}', true, false, true, false, true),
        ('\u{21}', false, false, true, true, false),
        ('\u{22}', false, false, false, false, false),
        ('\u{23}', false, false, false, false, false),
        ('\u{24}', false, true, false, false, false),
        ('\u{25}', false, false, true, true, false),
        ('\u{26}', false, false, true, true, false),
        ('\u{27}', false, false, false, false, false),
        ('\u{29}', false, false, false, false, false),
        ('\u{2a}', false, false, true, true, false),
        ('\u{2b}', false, false, true, true, false),
        ('\u{2c}', false, false, false, false, false),
        ('\u{2d}', false, false, true, true, false),
        ('\u{2e}', false, false, true, false, false),
        ('\u{2f}', false, false, true, true, false),
        ('\u{30}', false, true, false, false, false),
        ('\u{39}', false, true, false, false, false),
        ('\u{3a}', false, false, false, false, false),
        ('\u{3b}', false, false, false, false, false),
        ('\u{3c}', false, false, true, true, false),
        ('\u{3d}', false, false, true, true, false),
        ('\u{3e}', false, false, true, true, false),
        ('\u{3f}', false, false, true, true, false),
        ('\u{40}', false, false, false, false, false),
        ('\u{41}', true, true, false, false, false),
        ('\u{5a}', true, true, false, false, false),
        ('\u{5b}', false, false, false, false, false),
        ('\u{5d}', false, false, false, false, false),
        ('\u{5e}', false, false, true, true, false),
        ('\u{5f}', true, true, false, false, false),
        ('\u{60}', false, false, false, false, false),
        ('\u{61}', true, true, false, false, false),
        ('\u{7a}', true, true, false, false, false),
        ('\u{7b}', false, false, false, false, false),
        ('\u{7c}', false, false, true, true, false),
        ('\u{7d}', false, false, false, false, false),
        ('\u{7e}', false, false, true, true, false),
        ('\u{7f}', false, false, false, false, false),
        ('\u{9f}', false, false, false, false, false),
        ('\u{a0}', true, false, true, false, true),
        ('\u{a1}', false, false, true, true, false),
        ('\u{a7}', false, false, true, true, false),
        ('\u{a8}', true, true, false, false, false),
        ('\u{a9}', false, false, true, true, false),
        ('\u{aa}', true, true, false, false, false),
        ('\u{ab}', false, false, true, true, false),
        ('\u{ac}', false, false, true, true, false),
        ('\u{ad}', true, true, false, false, false),
        ('\u{ae}', false, false, true, true, false),
        ('\u{af}', true, true, false, false, false),
        ('\u{b0}', false, false, true, true, false),
        ('\u{b1}', false, false, true, true, false),
        ('\u{b2}', true, true, false, false, false),
        ('\u{b5}', true, true, false, false, false),
        ('\u{b6}', false, false, true, true, false),
        ('\u{b7}', true, true, false, false, false),
        ('\u{ba}', true, true, false, false, false),
        ('\u{bb}', false, false, true, true, false),
        ('\u{bc}', true, true, false, false, false),
        ('\u{be}', true, true, false, false, false),
        ('\u{bf}', false, false, true, true, false),
        ('\u{c0}', true, true, false, false, false),
        ('\u{d6}', true, true, false, false, false),
        ('\u{d7}', false, false, true, true, false),
        ('\u{d8}', true, true, false, false, false),
        ('\u{f6}', true, true, false, false, false),
        ('\u{f7}', false, false, true, true, false),
        ('\u{f8}', true, true, false, false, false),
        ('\u{ff}', true, true, false, false, false),
        ('\u{100}', true, true, false, false, false),
        ('\u{2ff}', true, true, false, false, false),
        ('\u{300}', false, true, false, true, false),
        ('\u{36f}', false, true, false, true, false),
        ('\u{370}', true, true, false, false, false),
        ('\u{167f}', true, true, false, false, false),
        ('\u{1680}', false, false, false, false, false),
        ('\u{1681}', true, true, false, false, false),
        ('\u{180d}', true, true, false, false, false),
        ('\u{180e}', false, false, false, false, false),
        ('\u{180f}', true, true, false, false, false),
        ('\u{1dbf}', true, true, false, false, false),
        ('\u{1dc0}', false, true, false, true, false),
        ('\u{1dff}', false, true, false, true, false),
        ('\u{1e00}', true, true, false, false, false),
        ('\u{1fff}', true, true, false, false, false),
        ('\u{2000}', false, false, false, false, false),
        ('\u{200a}', false, false, false, false, false),
        ('\u{200b}', true, true, false, false, false),
        ('\u{200d}', true, true, false, false, false),
        ('\u{200e}', false, false, false, false, false),
        ('\u{2015}', false, false, false, false, false),
        ('\u{2016}', false, false, true, true, false),
        ('\u{2017}', false, false, true, true, false),
        ('\u{2018}', false, false, false, false, false),
        ('\u{201f}', false, false, false, false, false),
        ('\u{2020}', false, false, true, true, false),
        ('\u{2027}', false, false, true, true, false),
        ('\u{2028}', false, false, false, false, false),
        ('\u{2029}', false, false, false, false, false),
        ('\u{202a}', true, true, false, false, false),
        ('\u{202e}', true, true, false, false, false),
        ('\u{202f}', false, false, false, false, false),
        ('\u{2030}', false, false, true, true, false),
        ('\u{203e}', false, false, true, true, false),
        ('\u{203f}', true, true, false, false, false),
        ('\u{2040}', true, true, false, false, false),
        ('\u{2041}', false, false, true, true, false),
        ('\u{2053}', false, false, true, true, false),
        ('\u{2054}', true, true, false, false, false),
        ('\u{2055}', false, false, true, true, false),
        ('\u{205e}', false, false, true, true, false),
        ('\u{205f}', false, false, false, false, false),
        ('\u{2060}', true, true, false, false, false),
        ('\u{206f}', true, true, false, false, false),
        ('\u{2070}', true, true, false, false, false),
        ('\u{20cf}', true, true, false, false, false),
        ('\u{20d0}', false, true, false, true, false),
        ('\u{20ff}', false, true, false, true, false),
        ('\u{2100}', true, true, false, false, false),
        ('\u{218f}', true, true, false, false, false),
        ('\u{2190}', false, false, true, true, false),
        ('\u{23ff}', false, false, true, true, false),
        ('\u{2400}', false, false, false, false, false),
        ('\u{245f}', false, false, false, false, false),
        ('\u{2460}', true, true, false, false, false),
        ('\u{24ff}', true, true, false, false, false),
        ('\u{2500}', false, false, true, true, false),
        ('\u{2775}', false, false, true, true, false),
        ('\u{2776}', true, true, false, false, false),
        ('\u{2793}', true, true, false, false, false),
        ('\u{2794}', false, false, true, true, false),
        ('\u{2bff}', false, false, true, true, false),
        ('\u{2c00}', true, true, false, false, false),
        ('\u{2dff}', true, true, false, false, false),
        ('\u{2e00}', false, false, true, true, false),
        ('\u{2e7f}', false, false, true, true, false),
        ('\u{2e80}', true, true, false, false, false),
        ('\u{2fff}', true, true, false, false, false),
        ('\u{3000}', false, false, false, false, false),
        ('\u{3001}', false, false, true, true, false),
        ('\u{3003}', false, false, true, true, false),
        ('\u{3004}', true, true, false, false, false),
        ('\u{3007}', true, true, false, false, false),
        ('\u{3008}', false, false, true, true, false),
        ('\u{3020}', false, false, true, true, false),
        ('\u{3021}', true, true, false, true, false),
        ('\u{302f}', true, true, false, true, false),
        ('\u{3030}', false, false, true, true, false),
        ('\u{3031}', true, true, false, false, false),
        ('\u{303f}', true, true, false, false, false),
        ('\u{3040}', true, true, false, false, false),
        ('\u{d7ff}', true, true, false, false, false),
        ('\u{f8ff}', false, false, false, false, false),
        ('\u{f900}', true, true, false, false, false),
        ('\u{fd3d}', true, true, false, false, false),
        ('\u{fd3e}', false, false, false, false, false),
        ('\u{fd3f}', false, false, false, false, false),
        ('\u{fd40}', true, true, false, false, false),
        ('\u{fdcf}', true, true, false, false, false),
        ('\u{fdd0}', false, false, false, false, false),
        ('\u{fdef}', false, false, false, false, false),
        ('\u{fdf0}', true, true, false, false, false),
        ('\u{fdff}', true, true, false, false, false),
        ('\u{fe00}', true, true, false, true, false),
        ('\u{fe0f}', true, true, false, true, false),
        ('\u{fe10}', true, true, false, false, false),
        ('\u{fe1f}', true, true, false, false, false),
        ('\u{fe20}', false, true, false, true, false),
        ('\u{fe2f}', false, true, false, true, false),
        ('\u{fe30}', true, true, false, false, false),
        ('\u{fe44}', true, true, false, false, false),
        ('\u{fe45}', false, false, false, false, false),
        ('\u{fe46}', false, false, false, false, false),
        ('\u{fe47}', true, true, false, false, false),
        ('\u{fff8}', true, true, false, false, false),
        ('\u{fff9}', false, false, false, false, false),
        ('\u{fffd}', false, false, false, false, false),
        ('\u{fffe}', false, false, false, false, false),
        ('\u{ffff}', false, false, false, false, false),
        ('\u{10000}', true, true, false, false, false),
        ('\u{1fffd}', true, true, false, false, false),
        ('\u{1fffe}', false, false, false, false, false),
        ('\u{1ffff}', false, false, false, false, false),
        ('\u{20000}', true, true, false, false, false),
        ('\u{2fffd}', true, true, false, false, false),
        ('\u{2fffe}', false, false, false, false, false),
        ('\u{2ffff}', false, false, false, false, false),
        ('\u{30000}', true, true, false, false, false),
        ('\u{3fffd}', true, true, false, false, false),
        ('\u{3fffe}', false, false, false, false, false),
        ('\u{3ffff}', false, false, false, false, false),
        ('\u{40000}', true, true, false, false, false),
        ('\u{4fffd}', true, true, false, false, false),
        ('\u{4fffe}', false, false, false, false, false),
        ('\u{4ffff}', false, false, false, false, false),
        ('\u{50000}', true, true, false, false, false),
        ('\u{5fffd}', true, true, false, false, false),
        ('\u{5fffe}', false, false, false, false, false),
        ('\u{5ffff}', false, false, false, false, false),
        ('\u{60000}', true, true, false, false, false),
        ('\u{6fffd}', true, true, false, false, false),
        ('\u{6fffe}', false, false, false, false, false),
        ('\u{6ffff}', false, false, false, false, false),
        ('\u{70000}', true, true, false, false, false),
        ('\u{7fffd}', true, true, false, false, false),
        ('\u{7fffe}', false, false, false, false, false),
        ('\u{7ffff}', false, false, false, false, false),
        ('\u{80000}', true, true, false, false, false),
        ('\u{8fffd}', true, true, false, false, false),
        ('\u{8fffe}', false, false, false, false, false),
        ('\u{8ffff}', false, false, false, false, false),
        ('\u{90000}', true, true, false, false, false),
        ('\u{9fffd}', true, true, false, false, false),
        ('\u{9fffe}', false, false, false, false, false),
        ('\u{9ffff}', false, false, false, false, false),
        ('\u{a0000}', true, true, false, false, false),
        ('\u{afffd}', true, true, false, false, false),
        ('\u{afffe}', false, false, false, false, false),
        ('\u{affff}', false, false, false, false, false),
        ('\u{b0000}', true, true, false, false, false),
        ('\u{bfffd}', true, true, false, false, false),
        ('\u{bfffe}', false, false, false, false, false),
        ('\u{bffff}', false, false, false, false, false),
        ('\u{c0000}', true, true, false, false, false),
        ('\u{cfffd}', true, true, false, false, false),
        ('\u{cfffe}', false, false, false, false, false),
        ('\u{cffff}', false, false, false, false, false),
        ('\u{d0000}', true, true, false, false, false),
        ('\u{dfffd}', true, true, false, false, false),
        ('\u{dfffe}', false, false, false, false, false),
        ('\u{dffff}', false, false, false, false, false),
        ('\u{e0000}', true, true, false, false, false),
        ('\u{e00ff}', true, true, false, false, false),
        ('\u{e0100}', true, true, false, true, false),
        ('\u{e01ef}', true, true, false, true, false),
        ('\u{e01f0}', true, true, false, false, false),
        ('\u{efffd}', true, true, false, false, false),
        ('\u{efffe}', false, false, false, false, false),
    ];

    /// A set of characters of the lexer, such as `operator`.
    type Set = fn(char) -> bool;

    /// Each set of characters answers at each character of `EDGES` as Swift 6.4.2 reads that character.
    /// A whitespace character passes every probe that puts it between two tokens, so a character starts a name or an operator only where it stands between no tokens.
    /// A character starts a name where `let cz = 0` parses, and it continues one, as `step` reads a word, where `func zcy() {}` parses.
    /// It starts an operator where both `prefix operator c~` and `prefix operator ~c~` parse, because the period starts only a dot operator, which `step` reads on its own.
    /// It continues an operator where `prefix operator ~c~` parses, and it stands between tokens where `letcz = 0` parses.
    /// The compiler continues an operator with U+3021 to U+302F, which start a name.
    /// It reads the five characters from U+FFF9 on as no character of a name, though the lexical structure lists them as identifier heads.
    /// The test fails when a range of a set moves, because it reads both sides of each edge.
    #[test]
    fn each_set_of_characters_reads_the_edge_of_each_range_as_swift_does() {
        for (character, name, word, head, operates, between) in EDGES {
            assert_eq!(spacing(character), between, "{character:?}");
            assert_eq!(
                identifier_head(character),
                name && !between,
                "{character:?}"
            );
            assert_eq!(
                step(Run::Word, character) == Run::Word,
                word,
                "{character:?}"
            );
            assert_eq!(
                operator_head(character),
                head && operates && !between,
                "{character:?}"
            );
            assert_eq!(operator(character), operates, "{character:?}");
        }
    }

    /// One character for each set of characters that the lexer reads alike.
    /// The blank and the tab may stand between an opening delimiter that spans lines and the end of its line.
    /// The lexer also compares both on its own inside a bare literal.
    /// The carriage return ends a line there and inside a bare literal, though only the line feed ends the line of a literal or a comment.
    /// The no-break space stands for the null character, and both stand between two tokens like a blank without ending a line.
    /// The vertical tab stands for the form feed, and both stand between two tokens but bind an operator.
    /// U+0001 stands for the other control characters, which end a bare literal.
    /// The comma, the colon, the semicolon, and the two braces each answer the sets around an operator in their own way.
    /// The equals sign stands for the operator heads other than the slash and the star.
    /// The backtick opens and closes a raw identifier, the dollar sign starts a name, and the byte order mark stands for nothing at the start of a source.
    /// The letter stands for the identifier heads, and the digit stands for the identifier tails that continue no operator.
    /// U+0301 stands for the combining marks, which continue a word or an operator.
    /// U+FE0F stands for the variation selectors and for U+3021 to U+302F, which start a word and continue a word or an operator.
    /// The at sign stands for every character that no set of the lexer holds.
    /// The lexer also reads a run of letters as a word and compares the word with its keywords, which no source over `ALPHABET` spells.
    const ALPHABET: [char; 31] = [
        '"', '#', '\\', '(', ')', '/', '*', '\n', '\r', ' ', '\t', '\u{a0}', '\u{b}', '\u{1}', ',',
        ':', ';', '{', '}', '[', ']', '.', '=', '`', '$', '\u{feff}', 'a', '1', '@', '\u{301}',
        '\u{fe0f}',
    ];

    /// The characters that open and close the literals, the interpolations, the comments, the regular expression literals, and the raw identifiers.
    /// The carriage return ends a bare literal and the line of an opening delimiter.
    /// One more character stands for the operators, and one for every other character.
    const STRUCTURE: [char; 17] = [
        '"', '#', '\\', '(', ')', '/', '*', '\n', '\r', ' ', '\t', ',', '[', ']', '=', '`', 'a',
    ];

    /// Characters outside `ALPHABET` from each set that the lexer names, for the comparison with their stand-ins.
    const OUTSIDE: [char; 16] = [
        '-',
        '!',
        '?',
        '±',
        '×',
        'é',
        '_',
        '7',
        '\u{20d7}',
        '\u{e0100}',
        '\0',
        '\u{c}',
        '\u{7f}',
        '\u{2000}',
        '\'',
        '\u{3021}',
    ];

    /// The length up to which a test compares the reading of a source with the reading of its stand-ins.
    const SUBSTITUTED: u32 = 3;

    /// The class and the level of each mark.
    fn reading(marks: &[Mark]) -> Vec<(Class, usize)> {
        marks.iter().map(|mark| (mark.class, mark.level)).collect()
    }

    /// The character of `ALPHABET` that stands in for `character`, which answers each set of the lexer as `character` does.
    fn stand_in(character: char) -> char {
        if ALPHABET.contains(&character) {
            character
        } else if operator_head(character) {
            '='
        } else if operator(character) && identifier_head(character) {
            '\u{fe0f}'
        } else if operator(character) {
            '\u{301}'
        } else if identifier_head(character) {
            'a'
        } else if identifier_tail(character) {
            '1'
        } else if opens_before(character) {
            '\u{a0}'
        } else if spacing(character) {
            '\u{b}'
        } else if unprintable(character) {
            '\u{1}'
        } else {
            '@'
        }
    }

    /// Every Unicode scalar value answers each set of the lexer as its stand-in in `ALPHABET` does, and no character of `OUTSIDE` stands in `ALPHABET`.
    /// The lexer compares each other character that it names on its own, and each of those stands in `ALPHABET`.
    /// Every source of up to `SUBSTITUTED` characters over `ALPHABET` and `OUTSIDE` reads like the same source with each stand-in in place.
    /// The test checks that the alphabet of the enumerations is enough, not that the sets are right, which `each_set_of_characters_reads_the_edge_of_each_range_as_swift_does` compares with Swift.
    /// No source of the enumerations spells a keyword, so they cover no path of the lexer through a keyword.
    /// `each_keyword_says_whether_a_regular_expression_literal_may_follow_it` covers each keyword, and `each_source_that_swift_parses_reads_its_regular_expression_literals_as_swift_does` covers each keyword that may stand before a slash in a source that Swift parses.
    #[test]
    fn each_character_that_the_lexer_names_outside_the_alphabet_reads_like_its_stand_in() {
        let sets: [Set; 14] = [
            blank,
            line_end,
            unprintable,
            opens_before,
            closes_after,
            spacing,
            identifier_head,
            identifier_tail,
            operator_head,
            operator_tail,
            operator,
            dotted,
            lists,
            ends_element,
        ];
        for character in OUTSIDE {
            assert!(!ALPHABET.contains(&character), "{character:?}");
        }
        for character in (0..=u32::from(char::MAX)).filter_map(char::from_u32) {
            let stood_in = stand_in(character);
            for set in sets {
                assert_eq!(set(character), set(stood_in), "{character:?}");
            }
        }
        let named = ALPHABET.iter().chain(&OUTSIDE).collect::<Vec<_>>();
        for length in 0..=SUBSTITUTED {
            for number in 0..named.len().pow(length) {
                let source = (0..length)
                    .map(|place| *named[number / named.len().pow(place) % named.len()])
                    .collect::<Vec<_>>();
                let stood_in = source.iter().map(|character| stand_in(*character));
                assert_eq!(
                    reading(&classify(&source)),
                    reading(&classify(&stood_in.collect::<Vec<_>>())),
                    "{source:?}"
                );
            }
        }
    }

    /// Whether the characters of `text` stand in `source` in their order, where a blank of `text` may also stand for the backslash of an escape.
    fn stands_in_order(text: &str, source: &[char]) -> bool {
        let mut rest = source.iter();
        text.chars().all(|expected| {
            rest.any(|character| *character == expected || (expected == ' ' && *character == '\\'))
        })
    }

    /// Asserts that the code-only view of `source` is `code`.
    #[track_caller]
    fn shows(source: &str, code: &str) {
        assert_eq!(code_only(source), code, "{source}");
    }

    fn literal(line: usize, text: &str) -> Literal {
        Literal {
            line,
            text: text.to_owned(),
        }
    }

    fn interpolation(line: usize, code: &str) -> Interpolation {
        Interpolation {
            line,
            code: code.to_owned(),
        }
    }

    #[test]
    fn comments_and_string_contents_are_blanked_and_lines_are_kept() {
        assert_eq!(code_only("a // b\nc"), "a     \nc");
        assert_eq!(code_only("a /* b\nc */ d"), "a     \n     d");
        assert_eq!(code_only("let x = \"print(y)\""), "let x = \"        \"");
        assert_eq!(code_only("\"a\\\"b\""), "\"    \"");
    }

    #[test]
    fn only_whole_identifiers_count_as_names() {
        assert!(names("_ = stat(path, &info)", "stat"));
        assert!(!names("let status = state", "stat"));
        assert!(!names("blueprint(x)", "print"));
    }

    #[test]
    fn the_empty_source_holds_no_code_no_literal_and_no_interpolation() {
        shows("", "");
        assert!(literals("").is_empty());
        assert!(interpolations("").is_empty());
    }

    #[test]
    fn a_slash_or_a_star_alone_is_code() {
        for code in ["a / b * c", "x /= 2", "a */ b", "(a)/(b)", "a /", "a *"] {
            shows(code, code);
        }
    }

    #[test]
    fn a_line_comment_ends_with_its_line() {
        shows("a // b /* c\nd", "a          \nd");
        shows("// \" ( #\nd", "        \nd");
        shows("a //", "a   ");
        assert!(literals("// \"a\"\n").is_empty());
    }

    #[test]
    fn block_comments_nest() {
        shows("/* a /* b */ c */ d", "                  d");
        shows("/*/*/**/*/*/ a", "             a");
        shows("/* a\n/* b\n*/ c\n*/ d", "    \n    \n    \n   d");
    }

    #[test]
    fn a_slash_or_a_star_alone_neither_opens_nor_closes_a_block_comment() {
        shows("/* a * b / c */ d", "                d");
        shows("/*/ a */ b", "         b");
        shows("/* a */* b", "       * b");
        shows("/* a /*/ b */ c */ d", "                   d");
    }

    #[test]
    fn a_block_comment_that_never_closes_reaches_the_end_of_the_source() {
        shows("a /* b\nc", "a     \n ");
        shows("/* /* */ a\nb", "          \n ");
        shows("a /*", "a   ");
        shows("/* *", "    ");
        shows("/* /", "    ");
    }

    #[test]
    fn a_quote_inside_a_comment_opens_no_literal() {
        shows("/* \" */ a", "        a");
        assert!(literals("/* \" */ a // \"b\"\n").is_empty());
    }

    #[test]
    fn comment_marks_inside_a_literal_are_text() {
        shows("\"a // b\" c", "\"      \" c");
        shows("\"/* a\" b", "\"    \" b");
        assert_eq!(
            literals("\"a // b\" + \"/* c\""),
            [literal(1, "a // b"), literal(1, "/* c")]
        );
    }

    #[test]
    fn a_literal_gives_its_line_and_its_text() {
        assert_eq!(
            literals("f(\"a\")\ng(\"\", \"b c\")\n"),
            [literal(1, "a"), literal(2, ""), literal(2, "b c")]
        );
        shows("\"\" + a", "\"\" + a");
    }

    #[test]
    fn an_escape_is_one_blank_of_the_text() {
        shows("\"a\\\"b\\\\\" c", "\"      \" c");
        assert_eq!(literals("\"a\\\"b\\\\\" c"), [literal(1, "a b ")]);
        assert_eq!(literals("\"line\\nbreak\""), [literal(1, "line break")]);
    }

    #[test]
    fn a_literal_that_never_closes_ends_with_its_line() {
        shows("let a = \"abc\nprint(x)\n", "let a = \"   \nprint(x)\n");
        assert_eq!(
            literals("let a = \"abc\nlet b = \"d\"\n"),
            [literal(1, "abc"), literal(2, "d")]
        );
        shows("\"a\\\nb", "\"  \nb");
        assert_eq!(literals("\"a\\\nb"), [literal(1, "a ")]);
    }

    #[test]
    fn a_literal_that_the_source_cuts_keeps_its_text() {
        assert_eq!(literals("\"abc"), [literal(1, "abc")]);
        assert_eq!(literals("\""), [literal(1, "")]);
        assert_eq!(literals("\"a\\"), [literal(1, "a ")]);
        shows("\"a\\", "\"  ");
        assert_eq!(literals("\"\"\"\nabc"), [literal(1, "\nabc")]);
        shows("a \\", "a \\");
    }

    #[test]
    fn a_literal_between_three_quotes_spans_lines_and_holds_quotes() {
        let source = "\"\"\"\nsay \"hi\" \"\"x\"\"\n\"\"\" + b";
        assert_eq!(literals(source), [literal(1, "\nsay \"hi\" \"\"x\"\"\n")]);
        shows(source, "\"\"\"\n              \n\"\"\" + b");
        assert_eq!(
            literals("\"\"\"\na\n\"\"\"\n\"b\""),
            [literal(1, "\na\n"), literal(4, "b")]
        );
        assert_eq!(
            literals("\"\"\"\n\\\"\"\"\n\"\"\""),
            [literal(1, "\n \"\"\n")]
        );
    }

    #[test]
    fn a_backslash_before_a_line_feed_keeps_the_line_feed() {
        let source = "\"\"\"\na\\\nb\n\"\"\"\nc";
        shows(source, "\"\"\"\n  \n \n\"\"\"\nc");
        assert_eq!(literals(source), [literal(1, "\na b\n")]);
    }

    #[test]
    fn a_literal_between_pound_signs_closes_with_the_same_pound_signs() {
        shows("#\"a\"b\\n\"# c", "#\"     \"# c");
        assert_eq!(literals("#\"a\"b\\n\"# c"), [literal(1, "a\"b\\n")]);
        assert_eq!(
            literals("#\"\\\"# + ##\"a\"#b\"## + ##\"\"##"),
            [literal(1, "\\"), literal(1, "a\"#b"), literal(1, "")]
        );
        assert_eq!(literals("#\"a\"#\"b\""), [literal(1, "a"), literal(1, "b")]);
        assert_eq!(literals("# \"a\"#"), [literal(1, "a")]);
        assert_eq!(literals("#if a\n\"b\"\n#endif\n"), [literal(2, "b")]);
    }

    #[test]
    fn three_quotes_between_pound_signs_open_a_literal_of_one_line_when_it_closes_on_that_line() {
        assert_eq!(literals("#\"\"\"# + a"), [literal(1, "\"")]);
        shows("let q = #\"\"\"# + a", "let q = #\" \"# + a");
        assert_eq!(literals("f(#\"\"\"\"#)"), [literal(1, "\"\"")]);
        let source = "#\"\"\"\nsay \"hi\"#\n\"\"\"# + a";
        assert_eq!(literals(source), [literal(1, "\nsay \"hi\"#\n")]);
        shows(source, "#\"\"\"\n         \n\"\"\"# + a");
        assert_eq!(
            literals("#\"\"\"\na\"\"\"b\n\"\"\"#"),
            [literal(1, "\na\"\"\"b\n")]
        );
    }

    #[test]
    fn an_interpolation_is_code_between_two_parts_of_the_text() {
        shows("\"a\\(b)c\" + d", "\" \\(b) \" + d");
        assert_eq!(literals("\"a\\(b)c\""), [literal(1, "ac")]);
        assert_eq!(
            interpolations("\n\"a\\(b)c\\(d.e)\""),
            [interpolation(2, "b"), interpolation(2, "d.e")]
        );
    }

    #[test]
    fn an_interpolation_ends_with_the_parenthesis_that_matches_its_first_one() {
        let source = "\"\\(f(x, (y))) z\"";
        assert_eq!(interpolations(source), [interpolation(1, "f(x, (y))")]);
        assert_eq!(literals(source), [literal(1, " z")]);
        assert_eq!(literals("\"\\(a))b\""), [literal(1, ")b")]);
        assert_eq!(literals("f((\")\"))"), [literal(1, ")")]);
    }

    #[test]
    fn a_literal_inside_an_interpolation_ends_before_the_literal_around_it() {
        let source = "\"a\\(\"b\\(c)d\")e\"";
        assert_eq!(literals(source), [literal(1, "bd"), literal(1, "ae")]);
        assert_eq!(
            interpolations(source),
            [interpolation(1, "c"), interpolation(1, "\" \\(c) \"")]
        );
        shows(source, "\" \\(\" \\(c) \") \"");
        assert_eq!(
            interpolations("\"\\(f(\")\"))\""),
            [interpolation(1, "f(\" \")")]
        );
    }

    #[test]
    fn a_literal_between_pound_signs_takes_them_in_its_interpolations_and_its_escapes() {
        let source = "#\"a\\#(b)c\\(d)\\#n\"#";
        assert_eq!(interpolations(source), [interpolation(1, "b")]);
        assert_eq!(literals(source), [literal(1, "ac\\(d) ")]);
        shows(source, "#\" \\#(b)        \"#");
        assert_eq!(
            interpolations("##\"\\#(a)\\##(b)\"##"),
            [interpolation(1, "b")]
        );
        assert_eq!(
            interpolations("#\"\\#(\"\\(a)\")\"#"),
            [interpolation(1, "a"), interpolation(1, "\"\\(a)\"")]
        );
    }

    #[test]
    fn a_comment_inside_an_interpolation_hides_its_parentheses_and_its_quotes() {
        let source = "\"v=\\(x /* ) \" */)\" + a";
        assert_eq!(interpolations(source), [interpolation(1, "x          ")]);
        assert_eq!(literals(source), [literal(1, "v=")]);
        let lines = "\"\"\"\n\\(x // ) \"\n)\n\"\"\"";
        assert_eq!(interpolations(lines), [interpolation(2, "x       \n")]);
        assert_eq!(literals(lines), [literal(1, "\n\n")]);
    }

    #[test]
    fn an_interpolation_of_a_literal_between_three_quotes_spans_lines() {
        let source = "\"\"\"\nv=\\(\n  x\n) w\n\"\"\"";
        assert_eq!(interpolations(source), [interpolation(2, "\n  x\n")]);
        assert_eq!(literals(source), [literal(1, "\nv= w\n")]);
    }

    #[test]
    fn an_interpolation_that_never_closes_ends_with_the_line_of_its_literal() {
        let source = "\"a\\(b\nprint(x)";
        assert_eq!(interpolations(source), [interpolation(1, "b")]);
        assert_eq!(literals(source), [literal(1, "a")]);
        shows("\"a\\(b\nc) d\"", "\" \\(b\nc) d\"");
        assert_eq!(
            literals("\"a\\(f(\"b\nc"),
            [literal(1, "b"), literal(1, "a")]
        );
        assert_eq!(
            interpolations("\"a\\(f(\"b\nc"),
            [interpolation(1, "f(\" ")]
        );
        assert_eq!(
            interpolations("\"a\\(b // c)\"\nd"),
            [interpolation(1, "b       ")]
        );
    }

    #[test]
    fn an_interpolation_that_the_source_cuts_keeps_its_code() {
        assert_eq!(interpolations("\"a\\(b + c"), [interpolation(1, "b + c")]);
        assert_eq!(literals("\"a\\(b + c"), [literal(1, "a")]);
        assert_eq!(interpolations("\"\\("), [interpolation(1, "")]);
    }

    #[test]
    fn a_line_feed_ends_a_literal_of_one_line_inside_an_interpolation_that_spans_lines() {
        let source = "\"\"\"\n\\(\"a\n) b\n\"\"\"";
        assert_eq!(literals(source), [literal(2, "a"), literal(1, "\n b\n")]);
        assert_eq!(interpolations(source), [interpolation(2, "\" \n")]);
    }

    #[test]
    fn a_regular_expression_between_pound_signs_holds_comment_marks_and_quotes() {
        shows("let r = #/a/*b\"/# + c", "let r = #/     /# + c");
        shows("#//# a", "#//# a");
        let source = "#/a\"b/# + #/\\(c)/#";
        assert!(literals(source).is_empty());
        assert!(interpolations(source).is_empty());
    }

    #[test]
    fn a_regular_expression_closes_only_with_its_own_pound_signs_and_not_after_a_backslash() {
        shows("##/a/#b/## c", "##/    /## c");
        shows("#/a\\/#b/# c", "#/     /# c");
        assert_eq!(literals("#/a/#\"b\""), [literal(1, "b")]);
        assert_eq!(literals("##/a/##\"b\""), [literal(1, "b")]);
    }

    #[test]
    fn a_regular_expression_between_pound_signs_that_never_closes_ends_with_its_line() {
        shows("#/* c */\nd", "#/      \nd");
        shows("#/a\\\nb", "#/  \nb");
        shows("#/ a\n/# b", "#/  \n/# b");
    }

    #[test]
    fn a_regular_expression_whose_delimiter_ends_its_line_spans_lines() {
        shows("#/ \t\n a /* b\n/#\nc", "#/  \n       \n/#\nc");
        shows("#/\na\\\n/# b", "#/\n  \n/# b");
    }

    /// Swift 6.4.2 finds the end of an interpolation by its parentheses and quotes alone.
    /// It accepts a regular expression literal there only when the parentheses and the quotes of the literal pair up.
    #[test]
    fn a_regular_expression_inside_an_interpolation_holds_its_parentheses_and_its_quotes() {
        let source = "\"\\(x.matches(#/(a)\"b\"/#)) c\"";
        assert_eq!(
            interpolations(source),
            [interpolation(1, "x.matches(#/      /#)")]
        );
        assert_eq!(literals(source), [literal(1, " c")]);
        let cut = "\"a\\(#/\nb\"";
        shows(cut, "\" \\(#/\nb\"");
        assert_eq!(literals(cut), [literal(1, "a"), literal(2, "")]);
    }

    #[test]
    fn a_comment_right_after_the_backslash_of_a_key_path_is_a_comment() {
        shows("let k = \\/* \" */.count", "let k = \\       .count");
        shows("let k = \\// \"\"\"\n.count", "let k = \\      \n.count");
        assert_eq!(
            literals("let k = \\/* \" */.count; let s = \"a\""),
            [literal(1, "a")]
        );
    }

    #[test]
    fn a_bare_regular_expression_holds_comment_marks_and_quotes() {
        shows("let r = /\\/*/ /* c */ d", "let r = /   /         d");
        shows("let r = /\\// d", "let r = /  / d");
        shows("let r = /\\/* \"\"\" */\nd", "let r = /         /\nd");
        assert!(literals("let r = /a\"b/\n").is_empty());
        let source = "\"\\(x.contains(/a\"b\"/)) c\"";
        assert_eq!(literals(source), [literal(1, " c")]);
        assert_eq!(
            interpolations(source),
            [interpolation(1, "x.contains(/    /)")]
        );
    }

    #[test]
    fn a_bare_regular_expression_opens_only_where_nothing_binds_its_slash_on_the_left() {
        for opened in [
            "/a/", " /a/", "\t/a/", "\n/a/", "(/a/", "[/a/", "{/a/", ",/a/", ";/a/", ":/a/",
        ] {
            shows(opened, &opened.replace("/a/", "/ /"));
        }
        for bound in ["x/a/b", "(x)/a/b", "[x]/a/b", "x!/a/b", "\\/a/b"] {
            shows(bound, bound);
        }
        shows("\"x\"/a/b", "\" \"/a/b");
    }

    /// Swift 6.4.2 reads a block comment before an operator as a blank, and it reads a literal at the first slash of a prefix operator such as `!/`.
    #[test]
    fn a_bare_regular_expression_opens_after_a_block_comment_and_inside_a_prefix_operator() {
        shows("let r = /**//a\"/; d", "let r =     /  /; d");
        shows("x/* c *//a/", "x       / /");
        shows("let r = !/a\"/; d", "let r = !/  /; d");
        shows("(-!/,a/)", "(-!/  /)");
        shows("let r = /**/!/a/", "let r =     !/ /");
        for bound in ["x!/a/b", "x*/a/b", "x!-/a/b", "x*a/b/c"] {
            shows(bound, bound);
        }
        shows("x /=/a/", "x / /a/");
    }

    /// Swift 6.4.2 refuses a bare literal that starts with a blank, a tab, or a line feed.
    /// Where an element starts, it reads a literal after a slash that a closing bracket or a separator follows, as in `f(/]a/)` and `f(1, /,a/)`, unless a closing parenthesis closes no group.
    /// The operator of the slash runs over the operator characters and stops before a comment, and Swift reads `/=/` as the literal of `let r = /=/=//x`.
    #[test]
    fn a_bare_regular_expression_reads_the_character_after_its_slash_and_after_its_operator() {
        for spaced in ["(/ a/)", "(/\ta/)", "(/\na/)", "(/=\ta/)", "let r = /"] {
            shows(spaced, spaced);
        }
        for (led, code) in [
            ("(/]a/)", "(/  /)"),
            ("(/}a/)", "(/  /)"),
            ("(/,a/)", "(/  /)"),
            ("(/;a/)", "(/  /)"),
            ("(/:a/)", "(/  /)"),
            ("f(1, /,a\"/)", "f(1, /   /)"),
            ("(/=]a/)", "(/   /)"),
        ] {
            shows(led, code);
        }
        shows("(/)a/)", "(/)a/)");
        shows("(/=)a/)", "(/=)a/)");
        shows("f(/, 0) / 2", "f(/, 0) / 2");
        shows("values.reduce(1, /)", "values.reduce(1, /)");
        shows("x /= y / z", "x /= y / z");
        shows("total / count/2", "total / count/2");
        shows("let r = /=a/ + /.a/", "let r = /  / + /  /");
        shows("let r = /=/=//x", "let r = / /=   ");
        shows("let r = /=//\"\"\"\nd", "let r = /=     \nd");
    }

    /// Swift 6.4.2 reads each parenthesis between the brackets of a character class as part of the class, and a class may hold another class.
    /// A closing bracket outside every class is a character of the pattern, and a slash ends the literal inside a class too.
    #[test]
    fn a_character_class_holds_the_parentheses_of_a_bare_regular_expression() {
        for opened in [
            "/[)]/",
            "/[)\"]/",
            "/[^)]/",
            "/[\\])]/",
            "/[\\\\)]/",
            "/[[a])]/",
            "/[[])]]/",
            "/[a)/",
            "/a](/",
            "/a](b)/",
        ] {
            let blanks = " ".repeat(opened.chars().count() - 2);
            shows(&format!("x = {opened}; d"), &format!("x = /{blanks}/; d"));
        }
        for operator in ["/[(])/", "/\\[)]/", "/[]a)]/", "/[\\\\])/", "/a]))/"] {
            let code = format!("x = {operator}; d");
            shows(&code, &code);
        }
        shows("x = /[a/]/; d", "x = /  /]/; d");
        assert_eq!(
            literals("let quote = #/\"/#\nlet closer = /[)\"]/; let s = \"a\"\n"),
            [literal(2, "a")]
        );
    }

    /// swift-syntax reads the operator after the keyword `func` or `operator` as the name of a declaration, never as a literal.
    /// Blanks, line feeds, and comments may stand between the keyword and the operator, and only the token right before the operator counts.
    /// A longer identifier that ends with the keyword, such as `my_func` or `éfunc`, is a name.
    #[test]
    fn a_slash_that_names_an_operator_in_its_declaration_opens_no_literal() {
        for declared in [
            "func /(a: S) -> S { b/c }",
            "static func /=(a: inout S, b: S) { a.v = a.v/b.v }",
            "func /<T>(a: T) -> T { b/c }",
            "prefix operator /^\nprefix func\t/^(w: Int) -> Int { w/2 }",
            "infix operator /: M; let h = m/2",
            "postfix operator /; let h = m/2",
        ] {
            shows(declared, declared);
        }
        shows(
            "func /* c */ /(a: S) -> S { b/c }",
            "func         /(a: S) -> S { b/c }",
        );
        shows(
            "func\n// c\n/(a: S) -> S { b/c }",
            "func\n    \n/(a: S) -> S { b/c }",
        );
        for opened in [
            "func f() {}; let r = /a/",
            "myfunc /a/",
            "my_func /a/",
            "éfunc /a/",
            "func2 /a/",
            "operators /a/",
            "a.func /a/",
        ] {
            shows(opened, &opened.replace("/a/", "/ /"));
        }
    }

    /// Swift 6.4.2 reads an operator that nothing binds on either side, such as `/=` before a blank or `/` before `]`, as a binary operator after an operand.
    /// It reads a literal there only where an expression starts, after `=`, `;`, `{`, `[`, a binary operator, a keyword such as `return`, or `try?`, and an unbalanced closing parenthesis doesn't stop that literal.
    /// Where an element starts after `(`, `,`, or `:` and a comma or a closing parenthesis follows the operator, the slash may stand for the operator itself, as in `reduce(1, /)`.
    /// An unbalanced closing parenthesis leaves no literal there.
    #[test]
    fn a_slash_free_on_both_sides_opens_a_literal_only_where_an_expression_starts() {
        for code in [
            "x /= y; z = a/b",
            "x! /= y; z = a/b",
            "self /= y; z = a/b",
            "value.default /= y; z = a/b",
            "f() /= y; z = a/b",
            "f(by: /)",
            "f(1, /)",
            "f(/)a/)",
        ] {
            shows(code, code);
        }
        shows("\"s\" /= y; z = a/b", "\" \" /= y; z = a/b");
        for (opened, code) in [
            ("let r = /= a/; d", "let r = /   /; d"),
            ("/= a/", "/   /"),
            ("return /= a/", "return /   /"),
            ("x = y + /= a/", "x = y + /   /"),
            ("let r = try? /= a/", "let r = try? /   /"),
            ("{ /]a/ }", "{ /  / }"),
            ("[/)a/]", "[/  /]"),
            ("f(/])/)", "f(/  /)"),
            ("(/= a/)", "(/   /)"),
            ("let r = /)\"/; d", "let r = /  /; d"),
            ("a; /)a/", "a; /  /"),
            ("return /)a/", "return /  /"),
        ] {
            shows(opened, code);
        }
    }

    /// Swift 6.4.2 reads a regular expression literal right after a keyword where an expression starts, as in `return/a/`, though the keyword binds the slash on its left.
    /// `tryLexRegexLiteral` in `lib/Parse/ParseExpr.cpp` reads an operator that both of its sides bind at the start of an expression as a literal without the test of the parentheses.
    /// It reads no literal at an operator that only its left side binds, as in `return/,a/`, and the compiler refuses that source.
    /// The mark of `try!` and `try?` ends no operand, so a slash right after it opens a literal too.
    /// A slash right after a name, a member, or an expression keyword such as `self` divides.
    #[test]
    fn a_slash_right_after_a_keyword_where_an_expression_starts_opens_a_literal() {
        for (opened, code) in [
            ("return/a\"/; d", "return/  /; d"),
            ("try/a\"/; d", "try/  /; d"),
            ("await/a\"/; d", "await/  /; d"),
            ("{ x in/a\"/ }; d", "{ x in/  / }; d"),
            ("return/a)\"/; d", "return/   /; d"),
            ("return/=a\"/; d", "return/   /; d"),
            ("try!/a)\"/; d", "try!/   /; d"),
            ("try?/a\"/; d", "try?/  /; d"),
        ] {
            shows(opened, code);
        }
        for code in [
            "let q = count/2; let r = q/3",
            "let q = x.return/2; let r = q/3",
            "let q = self/2; let r = q/3",
            "return/,a/; d",
            "return/ a/; d",
        ] {
            shows(code, code);
        }
        shows(
            "func g() -> R {\n  return/\\/*/\n}\n/* note */\nlet d = Date()\n",
            "func g() -> R {\n  return/   /\n}\n          \nlet d = Date()\n",
        );
    }

    /// The literal of `KEYWORD_SCREEN` opens right after `return` and ends on its line, and every later line stays code.
    #[test]
    fn a_regular_expression_right_after_return_hides_no_later_line() {
        let code = code_only(fixture::KEYWORD_SCREEN);
        let lines = code.lines().collect::<Vec<_>>();
        assert_eq!(
            lines[2],
            "  if strict { return/     / } else { return / / }"
        );
        assert_eq!(
            lines[7..],
            [
                "    let d = Date(); let s = URLSession.shared; print(s); let t = try? v.resourceValues(forKeys: [.contentModificationDateKey]); _ = (d, t)",
                "    return Text(\"       \").foregroundStyle(.blue)",
                "  }",
                "}",
            ]
        );
    }

    /// Swift 6.4.2 refuses anything but a line end right after the three quotes that open a literal spanning lines, as in `"""a`.
    /// The lexer opens such a literal only where blanks and tabs alone stand between the three quotes and a line feed or a carriage return.
    /// Elsewhere the first quote opens a literal of one line, so a quote that the lexer misreads never hides more than its line.
    #[test]
    fn three_quotes_open_a_literal_that_spans_lines_only_where_they_end_their_line() {
        for spanning in [
            "\"\"\"\na\n\"\"\" + b",
            "\"\"\" \t\na\n\"\"\" + b",
            "\"\"\"\r\na\r\n\"\"\" + b",
        ] {
            assert_eq!(literals(spanning).len(), 1, "{spanning:?}");
            assert!(code_only(spanning).ends_with("\"\"\" + b"), "{spanning:?}");
        }
        shows("\"\"\"a\"\nd", "\"\"\" \"\nd");
        assert_eq!(literals("\"\"\"a\"\nd"), [literal(1, ""), literal(1, "a")]);
        shows("let s = \"\"\" // c\nd", "let s = \"\"\"     \nd");
        assert_eq!(
            literals("#\"\"\"a\nb\n\"\"\"#"),
            [literal(1, "\"\"a"), literal(3, ""), literal(3, "#")]
        );
        assert_eq!(
            literals("x = /\"\"\"a\"/ + \"\"\"\nb\n\"\"\""),
            [literal(1, "\nb\n")]
        );
    }

    /// Swift reads a carriage return, a null character, and a no-break space between two tokens like a blank, as `isLeftBound` and `isRightBound` of swift-syntax state.
    /// A slash after one of them where an expression starts opens a literal, and a slash before one of them after an operand divides.
    /// None of them ends an operand or a word, so an operator after a name stays binary, and a word broken by a no-break space is no keyword.
    /// A carriage return ends a bare regular expression literal and the line of the delimiter of one between pound signs.
    #[test]
    fn a_carriage_return_a_null_character_and_a_no_break_space_stand_between_tokens_like_a_blank() {
        for space in ['\r', '\0', '\u{a0}'] {
            shows(
                &format!("import Foundation\nlet r ={space}/\"\"\"a\"/\nlet d = Date()\n"),
                &format!("import Foundation\nlet r ={space}/     /\nlet d = Date()\n"),
            );
            let divided = format!(
                "import Foundation\nlet a = 6\nlet b = 2\nlet c = 4\nlet q = a /{space}b; let d = Date(); let r = c/b\n"
            );
            shows(&divided, &divided);
            let operand = format!("x{space}/= y; z = a/b");
            shows(&operand, &operand);
        }
        shows("re\u{a0}turn/a/; d", "re\u{a0}turn/a/; d");
        shows("x = /a\rb/; d", "x = /a\rb/; d");
        shows("#/\r\na\n/# b", "#/ \n \n/# b");
    }

    /// Swift 6.4.2 refuses a binary operator that a closing bracket, a comma, a semicolon, or a colon follows, because none of them starts an operand.
    /// Such an operator free on both sides stands at the start of a statement, as on the line after `#endif` or after the body of a declaration.
    /// The parser reads it there as a literal without the test of the parentheses.
    /// After an operand, an operator that a blank or a line end follows is binary, as in `x /= y`.
    #[test]
    fn a_slash_free_on_both_sides_after_an_operand_opens_a_literal_where_no_operand_follows_it() {
        for (opened, code) in [
            ("func f() {}\n/,a\"/\nd", "func f() {}\n/   /\nd"),
            (
                "#if DEBUG\n#endif\n/)a\"/\nd",
                "#if DEBUG\n#endif\n/   /\nd",
            ),
            ("struct T {}\n/;a\"/; d", "struct T {}\n/   /; d"),
            ("if c {}\n/]a\"/; d", "if c {}\n/   /; d"),
            ("do {}\n/}a\"/; d", "do {}\n/   /; d"),
            ("class C {}\n/:a\"/; d", "class C {}\n/   /; d"),
            (
                "func f() {}\n/,\\/*/\n/* note */\nd",
                "func f() {}\n/    /\n          \nd",
            ),
        ] {
            shows(opened, code);
        }
        for code in ["x /= y; z = a/b", "x /=\ty; z = a/b", "x /\u{a0}y; z = a/b"] {
            shows(code, code);
        }
    }

    /// The Swift Programming Language lists operator characters outside ASCII, such as `±`, `×`, and `→`, and a regular expression literal opens after a prefix operator of them as it does after `!`.
    /// A slash that such an operator binds on its left divides, as after any postfix operator.
    #[test]
    fn an_operator_character_outside_ascii_reads_like_one_inside_ascii() {
        shows(
            "let r = ±/\\/*/\n/* note */\nlet d = Date()\n",
            "let r = ±/   /\n          \nlet d = Date()\n",
        );
        for (opened, code) in [
            ("let r = ×/a\"/; d", "let r = ×/  /; d"),
            ("let r = (÷/,a\"/); d", "let r = (÷/   /); d"),
            ("let r = →/a\"/ + ¬/b\"/; d", "let r = →/  / + ¬/  /; d"),
        ] {
            shows(opened, code);
        }
        for code in ["let q = x±/2; let r = q/3", "let q = ±x/2; let r = q/3"] {
            shows(code, code);
        }
    }

    /// A combining mark such as U+0301 may continue both a name and an operator.
    /// It continues the token right before it, as the grammar reads each token to its longest form.
    /// After `return` it makes the name `returń`, after which a slash divides, and after `±` it continues the operator, after which a literal may open.
    /// The variation selector U+FE0F may also start a name, and it continues an operator in the same way.
    #[test]
    fn a_combining_mark_continues_the_name_or_the_operator_before_it() {
        for code in [
            "let q = return\u{301}/2; let r = q/3",
            "let q = cafe\u{301}\u{302}/2; let r = q/3",
            "let q = in\u{fe0f}/2; let r = q/3",
        ] {
            shows(code, code);
        }
        assert_eq!(
            literals("let q = return\u{301}+/a\"/; d"),
            [literal(1, "/; d")]
        );
        for (opened, code) in [
            ("let r = ±\u{301}/a\"/; d", "let r = ±\u{301}/  /; d"),
            (
                "let r = ±\u{301}\u{302}/a\"/; d",
                "let r = ±\u{301}\u{302}/  /; d",
            ),
            ("let r = !\u{fe0f}/a\"/; d", "let r = !\u{fe0f}/  /; d"),
        ] {
            shows(opened, code);
        }
    }

    /// The Swift Programming Language counts the vertical tab and the form feed as whitespace, though `isLeftBound` of swift-syntax binds an operator after them.
    /// Where an expression starts, the parser of the compiler reads a slash after one of them as a literal all the same, as it does after `return`.
    /// After an operand, the slash divides, and neither of them ends the operand.
    #[test]
    fn a_slash_after_a_vertical_tab_or_a_form_feed_opens_a_literal_only_where_an_expression_starts()
    {
        for space in ['\u{b}', '\u{c}'] {
            shows(
                &format!("let r = {space}/a\"/; d"),
                &format!("let r = {space}/  /; d"),
            );
            shows(
                &format!("return{space}/a)\"/; d"),
                &format!("return{space}/   /; d"),
            );
            let divided = format!("let q = x{space}/2; let r = q/3");
            shows(&divided, &divided);
        }
    }

    /// The compiler skips a byte order mark at the start of a source, so nothing binds the slash after it.
    /// The code-only view shows a blank in its place.
    /// Elsewhere The Swift Programming Language lists the same character as an identifier head, so it binds the slash after it like a name.
    /// Swift 6.4.2 refuses the last source, where it reads the character as the name after `x`.
    #[test]
    fn a_byte_order_mark_stands_for_nothing_only_at_the_start_of_a_source() {
        shows("\u{feff}/\\/*/\n/* note */\nd", " /   /\n          \nd");
        shows("\u{feff}return/a\"/; d", " return/  /; d");
        let named = "let q = x \u{feff}/2; let r = q/3";
        shows(named, named);
    }

    /// A dollar sign starts a name, as in `$0` and in the projection `$in` of a property wrapper, and a digit, a dollar sign, or a combining mark continues one.
    /// The letters of such a name spell no keyword, so a slash after the name divides.
    #[test]
    fn a_name_that_a_dollar_sign_starts_or_that_a_digit_or_a_mark_continues_is_no_keyword() {
        for code in [
            "let q = $in/2; let r = q/3",
            "let q = $0/2; let r = q/3",
            "let q = a$return/2; let r = q/3",
            "let q = x1in/2; let r = q/3",
            "let q = x\u{301}in/2; let r = q/3",
        ] {
            shows(code, code);
        }
    }

    /// An operator may start with a period, as the dot operators of the lexical structure such as `.+` do.
    /// The compiler reads what binds such an operator from its period, so a literal opens after a prefix `.+` as it does after `!`.
    /// A dot operator that a name binds on its left divides, as in `x.+/2`.
    #[test]
    fn a_slash_inside_an_operator_that_starts_with_a_period_reads_what_binds_the_period() {
        for (opened, code) in [
            ("let r = .+/a\"/; d", "let r = .+/  /; d"),
            ("let r = ..+/a\"/; d", "let r = ..+/  /; d"),
            ("let r = (.+/,a\"/); d", "let r = (.+/   /); d"),
            ("let r = .+/)a\"/; d", "let r = .+/   /; d"),
            ("let r = x ?? .+/a\"/; d", "let r = x ?? .+/  /; d"),
        ] {
            shows(opened, code);
        }
        shows(
            "let r = .+/\\/*/\n/* note */\nd",
            "let r = .+/   /\n          \nd",
        );
        for code in ["let q = x.+/2; let r = q/3", "let q = x .+/ 2; let r = q/3"] {
            shows(code, code);
        }
    }

    /// A period starts an operator such as `...`, so an operator after it and a blank stands where an expression starts.
    /// There a slash that a blank follows opens a literal, as it does after any binary operator.
    #[test]
    fn a_slash_after_a_range_operator_starts_an_expression() {
        shows("let r = 0 ... /= a\"/; d", "let r = 0 ... /    /; d");
        shows("let r = 0 ..< /= a\"/; d", "let r = 0 ..< /    /; d");
    }

    /// Swift 6.4.2 refuses every control character but the null character inside a regular expression literal of one line, escaped or not, as `advance` of `DelimiterLexing.swift` states.
    /// The compiler refuses each of the first five sources as a whole too, because outside a literal such a character is invalid or splits the statement.
    #[test]
    fn a_control_character_but_the_null_character_keeps_a_bare_regular_expression_from_opening() {
        for code in [
            "x = /a\u{b}b/; d",
            "x = /a\u{c}b/; d",
            "x = /a\u{1}b/; d",
            "x = /a\u{7f}b/; d",
            "x = /\\\u{1f}b/; d",
        ] {
            shows(code, code);
        }
        shows("x = /a\0b/; d", "x = /   /; d");
    }

    /// The literal of `OPERATOR_SCREEN` opens right after `±` and ends on its line, so the comment after it closes and every later line stays code.
    #[test]
    fn a_regular_expression_right_after_an_operator_outside_ascii_hides_no_later_line() {
        let code = code_only(fixture::OPERATOR_SCREEN);
        let lines = code.lines().collect::<Vec<_>>();
        assert_eq!(lines[5], "    let r = ±/   /");
        assert_eq!(
            lines[7..],
            [
                "    let d = Date(); let s = URLSession.shared; print(s); let u = UserDefaults.standard; _ = (r, d, u)",
                "    return Text(\"       \").foregroundStyle(.blue)",
                "  }",
                "}",
            ]
        );
    }

    /// A raw identifier runs from a backtick to the next backtick on its line, and nothing opens between them.
    /// After its closing backtick, a comment, a literal, or a regular expression literal opens as it does after any name.
    /// The closing backtick opens nothing itself, so the code between two raw identifiers of one line stays code.
    #[test]
    fn a_raw_identifier_holds_slashes_quotes_and_comment_marks() {
        shows("f(`a`, \"b\", `c`)", "f(`a`, \" \", `c`)");
        assert_eq!(literals("f(`a`, \"b\", `c`)"), [literal(1, "b")]);
        for code in [
            "let `per /day` = 1; d = 4/2",
            "let `a #/b` = 1; d",
            "let `a\"` = 1; d",
            "let `a //` = 1; d",
            "let `a /*` = 1; d",
            "let `#\"a` = 1; d",
            "f(`a)`); d",
        ] {
            shows(code, code);
        }
        shows("let `a`\"b\" + c", "let `a`\" \" + c");
        shows("`a`// b", "`a`    ");
        shows("`a` /* b */ c", "`a`         c");
        shows("x = `a` + /b/; d", "x = `a` + / /; d");
        assert_eq!(literals("let `a\"` = \"b\""), [literal(1, "b")]);
        let source = "\"\\(`a /b`) c\" + /d\"/";
        assert_eq!(interpolations(source), [interpolation(1, "`a /b`")]);
        assert_eq!(literals(source), [literal(1, " c")]);
    }

    /// A backtick without a partner on its line is one character of the code, and the line feed ends the search for its partner.
    #[test]
    fn a_backtick_without_a_partner_on_its_line_is_one_character() {
        shows("` \"a\"", "` \" \"");
        shows("`a\n\"b\" `", "`a\n\" \" `");
        shows("a ` // b", "a `     ");
        assert_eq!(literals("`a\n\"b`\""), [literal(2, "b`")]);
    }

    /// A raw identifier is a name, so an operator after it reads as it does after any other name, whatever its letters spell.
    /// An operator free on both sides is binary there, and a slash that a letter binds on its right still tries a literal.
    #[test]
    fn a_raw_identifier_ends_an_operand_whatever_it_spells() {
        for name in ["`x`", "`return`", "`try`", "`func`", "`a /`"] {
            assert_eq!(
                literals(&format!("{name} /= a\"/; d")),
                [literal(1, "/; d")],
                "{name}"
            );
            assert!(literals(&format!("{name} /a\"/; d")).is_empty(), "{name}");
        }
        shows("`a`/b/c", "`a`/b/c");
    }

    /// The 53 keywords that the lexer of swift-syntax classifies, in `Sources/SwiftParser/generated/IsLexerClassified.swift` at commit c161c39 of October 19, 2026, `await`, and `yield`, each with what it says about an operator after it.
    /// `isInRegexLiteralPosition` in `Sources/SwiftParser/Lexer/RegexLiteralLexer.swift` reads a literal after each of these keywords but the seven that are expressions themselves, and `tryScanOperatorAsRegexLiteral` in the same file reads none after `func` and `operator`.
    /// The parser of the compiler reads an expression after `await` and after `yield` in an accessor such as `_read`, so both stand where an expression starts.
    /// Swift 6.4.2 agrees on each word in the sources of the keyword family, where the oracle of the scratch directory puts a slash right after the word.
    const KEYWORDS: [(&str, Before); 55] = [
        ("Any", Before::Operand),
        ("as", Before::Expression),
        ("associatedtype", Before::Expression),
        ("break", Before::Expression),
        ("case", Before::Expression),
        ("catch", Before::Expression),
        ("class", Before::Expression),
        ("continue", Before::Expression),
        ("default", Before::Expression),
        ("defer", Before::Expression),
        ("deinit", Before::Expression),
        ("do", Before::Expression),
        ("else", Before::Expression),
        ("enum", Before::Expression),
        ("extension", Before::Expression),
        ("fallthrough", Before::Expression),
        ("false", Before::Operand),
        ("fileprivate", Before::Expression),
        ("for", Before::Expression),
        ("func", Before::Declaration),
        ("guard", Before::Expression),
        ("if", Before::Expression),
        ("import", Before::Expression),
        ("in", Before::Expression),
        ("init", Before::Expression),
        ("inout", Before::Expression),
        ("internal", Before::Expression),
        ("is", Before::Expression),
        ("let", Before::Expression),
        ("nil", Before::Operand),
        ("operator", Before::Declaration),
        ("precedencegroup", Before::Expression),
        ("private", Before::Expression),
        ("protocol", Before::Expression),
        ("public", Before::Expression),
        ("repeat", Before::Expression),
        ("rethrows", Before::Expression),
        ("return", Before::Expression),
        ("self", Before::Operand),
        ("Self", Before::Operand),
        ("static", Before::Expression),
        ("struct", Before::Expression),
        ("subscript", Before::Expression),
        ("super", Before::Operand),
        ("switch", Before::Expression),
        ("throw", Before::Expression),
        ("throws", Before::Expression),
        ("true", Before::Operand),
        ("try", Before::Try),
        ("typealias", Before::Expression),
        ("var", Before::Expression),
        ("where", Before::Expression),
        ("while", Before::Expression),
        ("await", Before::Expression),
        ("yield", Before::Expression),
    ];

    /// Whether the quote of `source` stands inside a regular expression literal, which leaves `source` without a string literal.
    fn quote_in_a_pattern(source: &str) -> bool {
        literals(source).is_empty()
    }

    /// Each keyword reads as swift-syntax reads it before a slash, which three sources tell apart.
    /// In `KW /a"/; d`, a letter binds the slash on its right, which makes the slash a prefix operator, and `tryScanOperatorAsRegexLiteral` tries a literal there after every token but `func` and `operator`.
    /// In `KW /= a"/; d`, the operator is free on both sides, so `isInRegexLiteralPosition` decides, and it reads a literal only after a word where an expression starts.
    /// In `KW? /= a"/; d`, the question mark ends an operand after every word but `try`, where it belongs to `try?`.
    /// In `KW/"""a"/; d`, the keyword binds the slash, and the parser of the compiler reads a literal there only where an expression starts.
    /// Elsewhere the three quotes open literals of one line, so `d` stays code after every keyword.
    /// The enumerations of the other tests spell no keyword, so this table is what covers the keywords of the lexer.
    #[test]
    fn each_keyword_says_whether_a_regular_expression_literal_may_follow_it() {
        for (keyword, before) in KEYWORDS {
            let unspaced = format!("{keyword}/\"\"\"a\"/; d");
            assert_eq!(
                quote_in_a_pattern(&unspaced),
                matches!(before, Before::Expression | Before::Try),
                "{keyword}"
            );
            assert!(code_only(&unspaced).ends_with("; d"), "{keyword}");
            assert_eq!(
                quote_in_a_pattern(&format!("{keyword} /a\"/; d")),
                before != Before::Declaration,
                "{keyword}"
            );
            assert_eq!(
                quote_in_a_pattern(&format!("{keyword} /= a\"/; d")),
                matches!(before, Before::Expression | Before::Try),
                "{keyword}"
            );
            assert_eq!(
                quote_in_a_pattern(&format!("{keyword}? /= a\"/; d")),
                before == Before::Try,
                "{keyword}"
            );
        }
    }

    /// The text of each regular expression literal that the lexer reads in `source`, with its delimiters, as `swiftc -frontend -dump-parse` dumps it in a `regex_literal_expr`.
    fn regular_expressions(source: &str) -> Vec<String> {
        let (characters, marks) = lex(source);
        let mut found = Vec::new();
        let mut at = 0;
        while at < marks.len() {
            if marks[at].class != Class::Pattern {
                at += 1;
                continue;
            }
            let mut start = at.saturating_sub(1);
            let mut pounds = 0;
            while start > 0 && characters[start - 1] == '#' {
                start -= 1;
                pounds += 1;
            }
            let mut end = at;
            while marks
                .get(end)
                .is_some_and(|mark| mark.class == Class::Pattern)
            {
                end += 1;
            }
            if characters.get(end) == Some(&'/') {
                end += 1;
                let mut closing = 0;
                while closing < pounds && characters.get(end) == Some(&'#') {
                    end += 1;
                    closing += 1;
                }
            }
            found.push(characters[start..end].iter().collect());
            at = end;
        }
        found
    }

    /// Sources that Swift 6.4.2 parses without an error, each with the text of every `regex_literal_expr` that `swiftc -frontend -dump-parse -swift-version 6` dumps for it, in the order of the dump.
    /// `oracle verdicts` in `target/oracle/tool` of the scratch directory ran swiftc on each source alone and wrote these verdicts.
    /// The first sixteen put a slash right after a keyword where an expression starts, which opens a literal there, and two of them put `?` between `try` and the slash.
    /// The next eight put a slash right after an expression keyword or the name of a member, which divides.
    /// Two put a slash right after `func` and `operator`, where it names an operator.
    /// The last three put a slash after `yield` in a `_read` accessor, after the name `〡`, and after the operator `±〡`, which U+3021 continues.
    /// The verdicts come from the compiler and not from the tables of the lexer.
    /// Moving a word that stands before a slash here to another row of `after_word`, or dropping it, changes the reading of its source.
    /// No source here can show a move from the expression words to the row of `try`.
    /// Only `try?` and `try!` put a mark between the word and the slash.
    /// The other 32 expression words have no source here.
    /// The scratch directory puts a slash right after each of them in five places, such as a function, a type, and the top level.
    /// Swift refuses every one of those sources.
    /// No verdict of the compiler can then show their rows, and `KEYWORDS` pins them.
    const PARSED: [(&str, &[&str]); 29] = [
        (
            "func g() -> Regex<Substring> {\n  return/a\"/\n}\n",
            &["/a\"/"],
        ),
        (
            "func g() throws -> Regex<Substring> {\n  try/a\"/\n}\n",
            &["/a\"/"],
        ),
        ("let r = try? /= a\"/\n", &["/= a\"/"]),
        (
            "func g() -> Regex<Substring>? {\n  try?/a\"/\n}\n",
            &["/a\"/"],
        ),
        (
            "func g() async -> Regex<Substring> {\n  await/a\"/\n}\n",
            &["/a\"/"],
        ),
        (
            "let f: () -> Regex<Substring> = { () in/a\"/ }\n",
            &["/a\"/"],
        ),
        (
            "struct H {\n  var p: Regex<Substring> {\n    _read { yield/a\"/ }\n  }\n}\n",
            &["/a\"/"],
        ),
        ("func g() throws {\n  throw/a\"/\n}\n", &["/a\"/"]),
        (
            "func g(s: String) {\n  switch s {\n  case/a\"/: break\n  default: break\n  }\n}\n",
            &["/a\"/"],
        ),
        (
            "func g(s: String) {\n  if/a\"/.wholeMatch(in: s) != nil {}\n}\n",
            &["/a\"/"],
        ),
        (
            "func g(s: String) {\n  guard/a\"/.wholeMatch(in: s) != nil else { return }\n}\n",
            &["/a\"/"],
        ),
        (
            "func g(s: String) {\n  while/a\"/.wholeMatch(in: s) != nil {}\n}\n",
            &["/a\"/"],
        ),
        (
            "func g() {\n  switch/a\"/ {\n  default: break\n  }\n}\n",
            &["/a\"/"],
        ),
        (
            "func g(xs: [String]) {\n  for x in xs where/a\"/.wholeMatch(in: x) != nil {}\n}\n",
            &["/a\"/"],
        ),
        ("func g() {\n  do {} catch/a\"/ {}\n}\n", &["/a\"/"]),
        ("func g() {\n  repeat/a\"/\n}\n", &["/a\"/"]),
        ("let q = self/2; let r = q/3\n", &[]),
        ("let q = Self/2; let r = q/3\n", &[]),
        ("let q = true/2; let r = q/3\n", &[]),
        ("let q = false/2; let r = q/3\n", &[]),
        ("let q = nil/2; let r = q/3\n", &[]),
        ("let q = Any/2; let r = q/3\n", &[]),
        ("class C: B { func h() -> Int { super/2 } }\n", &[]),
        ("let q = x.return/2; let r = q/3\n", &[]),
        (
            "struct S { var v: Int }\nfunc /(a: S, b: S) -> S { S(v: a.v/b.v) }\n",
            &[],
        ),
        (
            "infix operator /: MultiplicationPrecedence; let h = m/2\n",
            &[],
        ),
        (
            "struct Holder {\n  var stored: Regex<Substring> = /a/\n  var pattern: Regex<Substring> {\n    _read { yield/\\/*/ }\n  }\n}\n/* note */\nlet d = 1\n",
            &["/a/", "/\\/*/"],
        ),
        ("let 〡 = 6; let q = 〡/2; let r = q/3\n", &[]),
        (
            "prefix operator ±〡\nprefix func ±〡(r: Regex<Substring>) -> Regex<Substring> { r }\nlet r = ±〡/\\/*/\n/* note */\nlet d = 1\n",
            &["/\\/*/"],
        ),
    ];

    /// Prefix operators outside ASCII: one character of each range of operator heads outside ASCII, both ends of the first range, and four that a character continues.
    /// U+3021 and U+302F continue `±`, and so do the combining mark U+0301 and the variation selector U+FE0F.
    /// For each operator `op`, Swift 6.4.2 parses `prefix operator op`, `prefix func op(r: Regex<Substring>) -> Regex<Substring> { r }`, and `let r = op/a"/` on three lines, and `swiftc -frontend -dump-parse -swift-version 6` dumps one `regex_literal_expr` with the text `/a"/`.
    const PREFIX_OPERATORS: [&str; 28] = [
        "±〡",
        "±\u{302f}",
        "±\u{301}",
        "!\u{fe0f}",
        "¡",
        "§",
        "©",
        "«",
        "¬",
        "®",
        "°",
        "¶",
        "»",
        "¿",
        "×",
        "÷",
        "‖",
        "†",
        "‰",
        "⁁",
        "⁕",
        "←",
        "─",
        "➔",
        "⸀",
        "、",
        "〈",
        "〰",
    ];

    /// The lexer reads each regular expression literal that Swift 6.4.2 reads in each source of `PARSED` and `PREFIX_OPERATORS`, and no other.
    /// The expected values are what swiftc dumps, so the test fails when a row of `after_word` or a set of operator characters drifts from the compiler.
    #[test]
    fn each_source_that_swift_parses_reads_its_regular_expression_literals_as_swift_does() {
        for (source, dumped) in PARSED {
            assert_eq!(regular_expressions(source), dumped, "{source:?}");
        }
        for operator in PREFIX_OPERATORS {
            let source = format!(
                "prefix operator {operator}\nprefix func {operator}(r: Regex<Substring>) -> Regex<Substring> {{ r }}\nlet r = {operator}/a\"/\n"
            );
            assert_eq!(regular_expressions(&source), ["/a\"/"], "{source:?}");
        }
    }

    /// The reviewer's e7 of /tmp/gymemo-mt/verify6-swift, which Swift 6.4.2 type-checks, opens a literal right after `yield` in a `_read` accessor, and `swiftc -frontend -dump-parse` dumps `/\/*/` as a `regex_literal_expr`.
    /// The literal ends on its line, so the comment after it closes and the last line stays code.
    /// The reviewer's e5 names a constant `yield`, and Swift divides after it.
    /// The lexer reads `yield` as the keyword before a slash wherever it stands, so it reads a literal from that slash to the last slash of the line.
    /// The module documentation names that reading as a known exception.
    /// The misread ends with its line, and the next line stays code.
    #[test]
    fn a_slash_right_after_yield_opens_a_literal_that_ends_with_its_line() {
        let screen = "import SwiftUI\nstruct Holder {\n  var stored: Regex<Substring> = /a/\n  var pattern: Regex<Substring> {\n    _read { yield/\\/*/ }\n  }\n}\n/* note */\nlet d = Date(); let s = URLSession.shared; print(s)\n";
        let code = code_only(screen);
        let lines = code.lines().collect::<Vec<_>>();
        assert_eq!(lines[4], "    _read { yield/   / }");
        assert_eq!(lines[7], "          ");
        assert_eq!(
            lines[8],
            "let d = Date(); let s = URLSession.shared; print(s)"
        );
        let hidden = "2; let d = Date(); let r = q";
        shows(
            &format!("import Foundation\nlet yield = 6\nlet q = yield/{hidden}/3\n_ = (d, r)\n"),
            &format!(
                "import Foundation\nlet yield = 6\nlet q = yield/{}/3\n_ = (d, r)\n",
                " ".repeat(hidden.len())
            ),
        );
    }

    /// Swift ends a line comment at a carriage return, and the lexer ends it only at a line feed, which the module documentation names as a known exception.
    /// Swift 6.4.2 parses `// c`, a carriage return, and `let r = /a"/` as a comment and a literal, and the lexer reads the whole line as a comment.
    /// A source that ends its lines with a carriage return and a line feed reads the same in both.
    #[test]
    fn a_carriage_return_alone_ends_no_line_comment() {
        assert!(regular_expressions("// c\rlet r = /a\"/\n").is_empty());
        let line = "// c\rlet d = Date()";
        shows(
            &format!("{line}\ne"),
            &format!("{}\ne", " ".repeat(line.len())),
        );
        shows("// c\r\nlet d = Date()\n", "     \nlet d = Date()\n");
    }

    /// Swift 6.4.2 refuses an opening `#/` that ends its line when no `/#` closes it later, and it reads the next line as code.
    /// The lexer then ends the literal with its line, as it does for a literal of one line that never closes.
    /// A closing slash with fewer pound signs than the opening one, or one that a backslash escapes, closes nothing, and one with more pound signs closes the literal.
    /// Two backslashes escape each other, so the slash after them closes the literal, and a slash without a pound sign after it closes nothing.
    #[test]
    fn a_regular_expression_whose_delimiter_ends_its_line_and_that_never_closes_ends_with_its_line()
    {
        shows(
            "let r = #/\nlet d = Date()\n",
            "let r = #/\nlet d = Date()\n",
        );
        shows("let r = ##/\na /# b\nd", "let r = ##/\na /# b\nd");
        shows("let r = #/\n\\/#\nd", "let r = #/\n\\/#\nd");
        shows("let r = #/ \t\na\n/# d", "let r = #/  \n \n/# d");
        shows("let r = #/\na\n/## d", "let r = #/\n \n/## d");
        shows("let r = #/\n\\\\/# d", "let r = #/\n  /# d");
        shows("let r = #/\nlet q = a/b\n", "let r = #/\nlet q = a/b\n");
    }

    /// Swift 6.4.2 refuses a tab inside a regular expression literal of one line, so a bare literal never holds one.
    #[test]
    fn a_tab_keeps_a_bare_regular_expression_from_opening() {
        for code in ["x = /a\tb/; d", "f(/\\\tb/)", "x = /\t/; d"] {
            shows(code, code);
        }
    }

    #[test]
    fn a_bare_regular_expression_closes_at_the_first_slash_on_its_line_that_no_backslash_escapes() {
        shows("let r = /a\\/b/ + c", "let r = /    / + c");
        shows("let r = /a\\\\/ + c", "let r = /   / + c");
        shows("let r = /a\nb/", "let r = /a\nb/");
        shows("let r = /a\\\nb/", "let r = /a\\\nb/");
        shows("g(/a\\/, b)", "g(/a\\/, b)");
        shows("let r = /a", "let r = /a");
        shows("let r = /a\\", "let r = /a\\");
    }

    /// Swift 6.4.2 reads an operator where the contents end with a blank or where a comment opens at the closing slash.
    /// It also reads an operator where a closing parenthesis outside the character classes has no opening one.
    /// It reads a literal where the parentheses match or a backslash escapes one, and the lexer reads both the same way.
    #[test]
    fn a_bare_regular_expression_is_no_literal_where_the_compiler_reads_an_operator() {
        shows("x = /a / b", "x = /a / b");
        shows("x = /a\t/ b", "x = /a\t/ b");
        shows("x = /a//c", "x = /a   ");
        shows("x = /a/* c */", "x = /a       ");
        shows("x = (/a) / b", "x = (/a) / b");
        shows("x = /a)(/", "x = /a)(/");
        shows("x = /(a)/ + /a\\)/ + /(a/", "x = /   / + /   / + /  /");
    }

    /// Swift 6.4.2 accepts a blank right before the closing slash when a backslash stands right before that blank, as in `/a\ /`, and it never accepts a tab there.
    /// It looks only at the character before the blank, so `/a\\ /` ends there too.
    #[test]
    fn a_blank_right_after_a_backslash_may_end_a_bare_regular_expression() {
        for (opened, code) in [
            ("x = /a\\ /; s = \"/\"", "x = /   /; s = \" \""),
            ("x = /\\ /; d", "x = /  /; d"),
            ("x = /a\\\\ /; d", "x = /    /; d"),
        ] {
            shows(opened, code);
        }
        for operator in ["x = /a\\  /; d", "x = /a\\\t/; d"] {
            shows(operator, operator);
        }
    }

    #[test]
    fn each_character_keeps_its_place_whatever_its_width() {
        shows("\"記録\" + ラベル // 注\n", "\"  \" + ラベル     \n");
    }

    /// Reads every source of up to `longest` characters over `alphabet` once, through the same steps as `code_only`, `literals`, and `interpolations`.
    /// The code-only view keeps each place and each line feed, each span lies inside the source, and each literal and interpolation shows what the source holds.
    /// A source without a span holds no literal and no interpolation, so the checks of those pass for it without the work of reading them.
    fn every_source_keeps_each_place_and_each_line_feed(alphabet: &[char], longest: u32) {
        for length in 0..=longest {
            for number in 0..alphabet.len().pow(length) {
                let source = (0..length)
                    .map(|place| alphabet[number / alphabet.len().pow(place) % alphabet.len()])
                    .collect::<Vec<_>>();
                let marks = classify(&source);
                assert_eq!(marks.len(), source.len(), "{source:?}");
                let shown = view(&source, &marks);
                assert_eq!(shown.len(), source.len(), "{source:?}");
                for (shown, character) in shown.iter().zip(&source) {
                    assert!(
                        shown == character || (*shown == ' ' && *character != '\n'),
                        "{source:?}"
                    );
                }
                let spans = spans(&source, &marks);
                if spans.is_empty() {
                    continue;
                }
                let count = |character| source.iter().filter(|next| **next == character).count();
                let lines = 1..=1 + count('\n');
                for span in &spans {
                    assert!(span.from < span.to, "{source:?}");
                    assert!(span.to <= source.len(), "{source:?}");
                    assert!(lines.contains(&span.line), "{source:?}");
                }
                let code = shown.iter().collect::<String>();
                let literals = literals_in(&spans, &source, &marks);
                let interpolations = interpolations_in(&spans, &shown);
                assert!(literals.len() <= count('"'), "{source:?}");
                assert!(interpolations.len() <= count('\\'), "{source:?}");
                for literal in &literals {
                    assert!(lines.contains(&literal.line), "{source:?}");
                    assert!(stands_in_order(&literal.text, &source), "{source:?}");
                }
                for interpolation in &interpolations {
                    assert!(lines.contains(&interpolation.line), "{source:?}");
                    assert!(code.contains(&interpolation.code), "{source:?}");
                }
            }
        }
    }

    /// Runs each of the 954,305 sources of up to four characters over `ALPHABET`, one length beyond the three characters that the Kani proofs reach.
    /// The other characters that the lexer names read like their stand-ins in `ALPHABET`, which `each_character_that_the_lexer_names_outside_the_alphabet_reads_like_its_stand_in` checks.
    #[test]
    fn every_source_of_up_to_four_characters_keeps_each_place_and_each_line_feed() {
        every_source_keeps_each_place_and_each_line_feed(&ALPHABET, 4);
    }

    /// Runs each of the 1,508,598 sources of up to five characters over `STRUCTURE`, two lengths beyond the Kani proofs.
    /// The literals, the interpolations, and the comments need more characters than the operators do.
    #[test]
    fn every_source_of_up_to_five_structural_characters_keeps_each_place_and_each_line_feed() {
        every_source_keeps_each_place_and_each_line_feed(&STRUCTURE, 5);
    }

    #[test]
    fn swift_files_are_read_in_path_order_with_their_paths_from_the_root() -> Result<()> {
        let tree = Tree::new(
            "source-order",
            &[
                ("Sources/b.swift", "b\n"),
                ("Sources/a/c.swift", "c\n"),
                ("Sources/notes.md", "n\n"),
                ("App/z.swift", "z\n"),
            ],
        )?;
        let source = |file: &str, text: &str| Source {
            file: file.to_owned(),
            text: text.to_owned(),
        };
        assert_eq!(
            read(tree.root(), &["Sources", "App"]),
            Ok(vec![
                source("App/z.swift", "z\n"),
                source("Sources/a/c.swift", "c\n"),
                source("Sources/b.swift", "b\n"),
            ])
        );
        Ok(())
    }

    #[test]
    fn a_tree_without_swift_files_or_without_a_directory_is_refused() -> Result<()> {
        let tree = Tree::new("source-empty", &[("Sources/notes.md", "n\n")])?;
        assert_eq!(
            read(tree.root(), &["Sources"]),
            Err(Failure::new("Found no Swift files under Sources"))
        );
        let missing = read(tree.root(), &["Sources", "App"]).map_err(|failure| failure.to_string());
        assert!(
            missing
                .as_ref()
                .is_err_and(|message| message.starts_with("Read ") && message.contains("App: ")),
            "{missing:?}"
        );
        Ok(())
    }
}
