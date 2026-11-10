//! Reads JSON text as RFC 8259 describes it, so a command can read the report of a tool without a dependency.
//!
//! The reader refuses what the RFC leaves open: a repeated name in one object, a lone surrogate in a string, and nesting deeper than a fixed limit.

use std::{fmt, iter::Peekable, str::CharIndices};

/// The deepest nesting of arrays and objects that the reader accepts, which bounds its recursion.
pub const DEPTH: usize = 64;

/// One JSON value.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Value {
    Null,
    Bool(bool),
    /// The number as the text wrote it, which the grammar of the RFC has checked.
    Number(String),
    String(String),
    Array(Vec<Value>),
    /// The members in the order of the text, each name once.
    Object(Vec<(String, Value)>),
}

/// The reason that a text isn't JSON, at the byte where the reader found it.
#[derive(Debug, PartialEq, Eq)]
pub struct Error {
    pub offset: usize,
    pub reason: &'static str,
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{} at byte {}", self.reason, self.offset)
    }
}

impl Value {
    /// The member called `name` of an object.
    pub fn get(&self, name: &str) -> Option<&Value> {
        self.as_object()?
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value)
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(text) => Some(text),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(items) => Some(items),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&[(String, Value)]> {
        match self {
            Value::Object(members) => Some(members),
            _ => None,
        }
    }

    /// The number as a whole number, when it has no sign, fraction, or exponent and fits 64 bits.
    /// The parser of `u64` refuses each of those, so the number's text decides alone.
    pub fn as_u64(&self) -> Option<u64> {
        match self {
            Value::Number(text) => text.parse().ok(),
            _ => None,
        }
    }
}

/// The value that `text` holds, with nothing but whitespace around it.
pub fn parse(text: &str) -> Result<Value, Error> {
    let mut reader = Reader {
        text,
        characters: text.char_indices().peekable(),
    };
    let value = reader.value(0)?;
    reader.whitespace();
    match reader.characters.peek() {
        Some(&(offset, _)) => fail(offset, "text after the value"),
        None => Ok(value),
    }
}

fn fail<T>(offset: usize, reason: &'static str) -> Result<T, Error> {
    Err(Error { offset, reason })
}

/// The text, and the characters that the reader hasn't consumed yet.
/// Every loop of the reader consumes a character in each turn, so no changed number can make a loop run without end.
struct Reader<'a> {
    text: &'a str,
    characters: Peekable<CharIndices<'a>>,
}

impl Reader<'_> {
    /// The byte where the next character starts, or the end of the text.
    fn offset(&mut self) -> usize {
        self.characters
            .peek()
            .map_or(self.text.len(), |&(offset, _)| offset)
    }

    fn peek(&mut self) -> Option<char> {
        self.characters.peek().map(|&(_, character)| character)
    }

    /// Consumes the next character when it matches `expected`, and says whether it matched.
    fn take(&mut self, expected: char) -> bool {
        self.characters
            .next_if(|&(_, character)| character == expected)
            .is_some()
    }

    fn whitespace(&mut self) {
        while self
            .characters
            .next_if(|&(_, character)| matches!(character, ' ' | '\t' | '\n' | '\r'))
            .is_some()
        {}
    }

    /// The value after any whitespace, inside `depth` arrays and objects.
    fn value(&mut self, depth: usize) -> Result<Value, Error> {
        self.whitespace();
        match self.peek() {
            Some('{') => self.object(depth + 1),
            Some('[') => self.array(depth + 1),
            Some('"') => self.string().map(Value::String),
            Some('t') => self.literal("true", Value::Bool(true)),
            Some('f') => self.literal("false", Value::Bool(false)),
            Some('n') => self.literal("null", Value::Null),
            Some('-' | '0'..='9') => self.number(),
            _ => fail(self.offset(), "expected a value"),
        }
    }

    /// Refuses an array or an object at `depth` beyond the limit, at its opening bracket.
    fn nest(&mut self, depth: usize) -> Result<(), Error> {
        if depth > DEPTH {
            return fail(self.offset(), "nesting deeper than the limit");
        }
        Ok(())
    }

    fn literal(&mut self, word: &str, value: Value) -> Result<Value, Error> {
        let start = self.offset();
        for expected in word.chars() {
            if !self.take(expected) {
                return fail(start, "expected a value");
            }
        }
        Ok(value)
    }

    /// Consumes the digits where the reader stands, and says whether there was one.
    fn digits(&mut self) -> bool {
        let start = self.offset();
        while self
            .characters
            .next_if(|&(_, character)| character.is_ascii_digit())
            .is_some()
        {}
        self.offset() > start
    }

    fn required_digits(&mut self) -> Result<(), Error> {
        if !self.digits() {
            return fail(self.offset(), "expected a digit");
        }
        Ok(())
    }

    fn number(&mut self) -> Result<Value, Error> {
        let start = self.offset();
        self.take('-');
        // A whole part of zero takes no further digit, so the reader leaves a digit after the zero as text after the value.
        if !self.take('0') {
            self.required_digits()?;
        }
        if self.take('.') {
            self.required_digits()?;
        }
        if self.take('e') || self.take('E') {
            if !self.take('+') {
                self.take('-');
            }
            self.required_digits()?;
        }
        Ok(Value::Number(self.text[start..self.offset()].to_owned()))
    }

    /// The string whose opening quote is the next character.
    fn string(&mut self) -> Result<String, Error> {
        self.characters.next();
        let mut read = String::new();
        loop {
            match self.characters.next() {
                None => return fail(self.text.len(), "unterminated string"),
                Some((_, '"')) => return Ok(read),
                Some((offset, '\\')) => read.push(self.escape(offset)?),
                Some((offset, control)) if control < ' ' => {
                    return fail(offset, "control character in a string");
                }
                Some((_, character)) => read.push(character),
            }
        }
    }

    /// The character of the escape whose backslash, which the reader consumed, stands at `start`.
    fn escape(&mut self, start: usize) -> Result<char, Error> {
        match self.characters.next().map(|(_, character)| character) {
            Some('"') => Ok('"'),
            Some('\\') => Ok('\\'),
            Some('/') => Ok('/'),
            Some('b') => Ok('\u{8}'),
            Some('f') => Ok('\u{c}'),
            Some('n') => Ok('\n'),
            Some('r') => Ok('\r'),
            Some('t') => Ok('\t'),
            Some('u') => self.unicode(start),
            _ => fail(start, "invalid escape"),
        }
    }

    /// The four hexadecimal digits of a `\u` escape, where a fault counts at the backslash `start`.
    fn code_unit(&mut self, start: usize) -> Result<u32, Error> {
        let mut unit = 0;
        for _ in 0..4 {
            let digit = self
                .characters
                .next()
                .and_then(|(_, character)| character.to_digit(16));
            let Some(digit) = digit else {
                return fail(start, "invalid \\u escape");
            };
            unit = unit * 16 + digit;
        }
        Ok(unit)
    }

    /// The character of one `\u` escape, or of two such escapes that form a surrogate pair, whose first backslash stands at `start`.
    fn unicode(&mut self, start: usize) -> Result<char, Error> {
        let first = self.code_unit(start)?;
        let scalar = if (0xd800..=0xdbff).contains(&first) {
            if !(self.take('\\') && self.take('u')) {
                return fail(start, "unpaired surrogate");
            }
            let second = self.code_unit(start)?;
            if !(0xdc00..=0xdfff).contains(&second) {
                return fail(start, "unpaired surrogate");
            }
            0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00)
        } else {
            first
        };
        // A lone low surrogate is no scalar value, so `from_u32` refuses it.
        char::from_u32(scalar).map_or_else(|| fail(start, "unpaired surrogate"), Ok)
    }

    /// The array whose opening bracket is the next character.
    fn array(&mut self, depth: usize) -> Result<Value, Error> {
        self.nest(depth)?;
        self.characters.next();
        let mut items = Vec::new();
        self.whitespace();
        if self.take(']') {
            return Ok(Value::Array(items));
        }
        loop {
            items.push(self.value(depth)?);
            self.whitespace();
            let offset = self.offset();
            match self.characters.next().map(|(_, character)| character) {
                Some(',') => {}
                Some(']') => return Ok(Value::Array(items)),
                _ => return fail(offset, "expected `,` or `]`"),
            }
        }
    }

    /// The object whose opening brace is the next character.
    fn object(&mut self, depth: usize) -> Result<Value, Error> {
        self.nest(depth)?;
        self.characters.next();
        let mut members: Vec<(String, Value)> = Vec::new();
        self.whitespace();
        if self.take('}') {
            return Ok(Value::Object(members));
        }
        loop {
            self.whitespace();
            let start = self.offset();
            if self.peek() != Some('"') {
                return fail(start, "expected a name");
            }
            let name = self.string()?;
            if members.iter().any(|(known, _)| *known == name) {
                return fail(start, "repeated name");
            }
            self.whitespace();
            let colon = self.offset();
            if !self.take(':') {
                return fail(colon, "expected `:`");
            }
            let value = self.value(depth)?;
            members.push((name, value));
            self.whitespace();
            let offset = self.offset();
            match self.characters.next().map(|(_, character)| character) {
                Some(',') => {}
                Some('}') => return Ok(Value::Object(members)),
                _ => return fail(offset, "expected `,` or `}`"),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn number(text: &str) -> Value {
        Value::Number(text.to_owned())
    }

    fn string(text: &str) -> Value {
        Value::String(text.to_owned())
    }

    fn refused(text: &str) -> Option<(usize, &'static str)> {
        parse(text).err().map(|error| (error.offset, error.reason))
    }

    #[test]
    fn every_kind_of_value_is_read() {
        for (text, value) in [
            ("null", Value::Null),
            ("true", Value::Bool(true)),
            ("false", Value::Bool(false)),
            (" \t\n\r0 \n", number("0")),
            ("-0", number("-0")),
            ("12", number("12")),
            ("-12.5e+3", number("-12.5e+3")),
            ("1E-2", number("1E-2")),
            ("7e-0", number("7e-0")),
            ("1e5", number("1e5")),
            ("0.25", number("0.25")),
            ("\"\"", string("")),
            (
                "\"\u{e9}\u{1f600} \u{7f}\"",
                string("\u{e9}\u{1f600} \u{7f}"),
            ),
            ("[]", Value::Array(vec![])),
            ("{}", Value::Object(vec![])),
            (
                " [ 1 , [ ] , { } ] ",
                Value::Array(vec![
                    number("1"),
                    Value::Array(vec![]),
                    Value::Object(vec![]),
                ]),
            ),
            (
                "{\"a\" : 1 ,\n \"b\":{\"c\":[null,true]}}",
                Value::Object(vec![
                    ("a".to_owned(), number("1")),
                    (
                        "b".to_owned(),
                        Value::Object(vec![(
                            "c".to_owned(),
                            Value::Array(vec![Value::Null, Value::Bool(true)]),
                        )]),
                    ),
                ]),
            ),
        ] {
            assert_eq!(parse(text), Ok(value), "{text:?}");
        }
    }

    /// The texts write each backslash of a JSON escape as `\x5c`, so no tool that edits this file mistakes an escape for its character.
    #[test]
    fn every_escape_of_a_string_is_read() {
        for (text, read) in [
            (r#""a\"b\\c\/d\b\f\n\r\t""#, "a\"b\\c/d\u{8}\u{c}\n\r\t"),
            (
                "\"\x5cu0041\x5cu00e9\x5cu4E2D\x5cu0000\x5cuFFFF\"",
                "A\u{e9}\u{4e2d}\0\u{ffff}",
            ),
            (
                "\"\x5cud83d\x5cude00\x5cuD83D\x5cuDE00\"",
                "\u{1f600}\u{1f600}",
            ),
            ("\"\x5cudbff\x5cudfff\"", "\u{10ffff}"),
            ("\"\x5cud800\x5cudc00\"", "\u{10000}"),
            ("\"\x5cud7ff\x5cue000\"", "\u{d7ff}\u{e000}"),
            ("\"x\x5cu0020y\"", "x y"),
        ] {
            assert_eq!(parse(text), Ok(string(read)), "{text}");
        }
    }

    #[test]
    fn every_malformed_text_is_refused_at_the_byte_of_its_fault() {
        for (text, offset, reason) in [
            ("", 0, "expected a value"),
            ("   ", 3, "expected a value"),
            ("nul", 0, "expected a value"),
            ("tru", 0, "expected a value"),
            ("nulL", 0, "expected a value"),
            ("NaN", 0, "expected a value"),
            ("'a'", 0, "expected a value"),
            ("+1", 0, "expected a value"),
            (".5", 0, "expected a value"),
            ("\u{feff}1", 0, "expected a value"),
            ("truex", 4, "text after the value"),
            ("[1]x", 3, "text after the value"),
            ("1 2", 2, "text after the value"),
            ("01", 1, "text after the value"),
            ("1e+-2", 3, "expected a digit"),
            ("-", 1, "expected a digit"),
            ("-a", 1, "expected a digit"),
            ("1.", 2, "expected a digit"),
            ("1.e5", 2, "expected a digit"),
            ("1e", 2, "expected a digit"),
            ("1e+", 3, "expected a digit"),
            ("[1,]", 3, "expected a value"),
            ("[1 2]", 3, "expected `,` or `]`"),
            ("[1", 2, "expected `,` or `]`"),
            ("{a:1}", 1, "expected a name"),
            ("{\"a\":1,}", 7, "expected a name"),
            ("{\"a\" 1}", 5, "expected `:`"),
            ("{\"a\":1 \"b\":2}", 7, "expected `,` or `}`"),
            ("{\"a\":1", 6, "expected `,` or `}`"),
            ("{\"a\":1,\"a\":2}", 7, "repeated name"),
            ("\"abc", 4, "unterminated string"),
            ("\"a\nb\"", 2, "control character in a string"),
            ("\"\t\"", 1, "control character in a string"),
            ("\"\u{1f}\"", 1, "control character in a string"),
            ("\"\x5cx\"", 1, "invalid escape"),
            ("\"a\x5c", 2, "invalid escape"),
            ("\"\x5cu12\"", 1, "invalid \\u escape"),
            ("\"\x5cu12", 1, "invalid \\u escape"),
            ("\"\x5cu12G4\"", 1, "invalid \\u escape"),
            ("\"\x5cu+123\"", 1, "invalid \\u escape"),
            ("\"\x5cud83d\"", 1, "unpaired surrogate"),
            ("\"\x5cud83d", 1, "unpaired surrogate"),
            ("\"\x5cud83dx\"", 1, "unpaired surrogate"),
            ("\"\x5cud83d\x5cu0041\"", 1, "unpaired surrogate"),
            ("\"\x5cud83d\x5cn\"", 1, "unpaired surrogate"),
            ("\"\x5cud83d\x5cud83d\"", 1, "unpaired surrogate"),
            ("\"\x5cud7ff\x5cudc00\"", 7, "unpaired surrogate"),
            ("\"\x5cude00\"", 1, "unpaired surrogate"),
            ("\"\x5cudc00\"", 1, "unpaired surrogate"),
            ("\"\x5cudfff\"", 1, "unpaired surrogate"),
            ("\"\x5cud83d\x5cu12\"", 1, "invalid \\u escape"),
        ] {
            assert_eq!(refused(text), Some((offset, reason)), "{text:?}");
        }
        assert_eq!(
            parse("[1,]").map_err(|error| error.to_string()),
            Err("expected a value at byte 3".to_owned())
        );
    }

    #[test]
    fn nesting_stops_at_the_depth_limit() {
        let deepest = format!("{}{}", "[".repeat(DEPTH), "]".repeat(DEPTH));
        assert!(parse(&deepest).is_ok());
        let objects = format!("{}1{}", "{\"a\":".repeat(DEPTH), "}".repeat(DEPTH));
        assert!(parse(&objects).is_ok());
        let deeper = format!("{}{}", "[".repeat(DEPTH + 1), "]".repeat(DEPTH + 1));
        assert_eq!(
            refused(&deeper),
            Some((DEPTH, "nesting deeper than the limit"))
        );
        let mixed = format!("{}{{}}{}", "[".repeat(DEPTH), "]".repeat(DEPTH));
        assert_eq!(
            refused(&mixed),
            Some((DEPTH, "nesting deeper than the limit"))
        );
        assert_eq!(DEPTH, 64);
    }

    #[test]
    fn the_accessors_reach_only_their_own_kind() {
        let value = parse(r#"{"s":"t","n":12,"a":[1],"o":{"k":null},"f":1.5,"m":-1,"e":1e3,"big":18446744073709551616}"#)
            .unwrap_or(Value::Null);
        assert_eq!(value.get("s").and_then(Value::as_str), Some("t"));
        assert_eq!(value.get("n").and_then(Value::as_u64), Some(12));
        assert_eq!(
            value.get("a").and_then(Value::as_array),
            Some(&[number("1")][..])
        );
        assert_eq!(
            value.get("o").and_then(Value::as_object),
            Some(&[("k".to_owned(), Value::Null)][..])
        );
        assert_eq!(value.get("o").and_then(|o| o.get("k")), Some(&Value::Null));
        for name in ["f", "m", "e", "big", "s", "missing"] {
            assert_eq!(value.get(name).and_then(Value::as_u64), None, "{name}");
        }
        assert_eq!(value.get("n").and_then(Value::as_str), None);
        assert_eq!(value.get("s").and_then(Value::as_array), None);
        assert_eq!(value.get("a").and_then(Value::as_object), None);
        assert_eq!(value.get("a").and_then(|a| a.get("0")), None);
        assert_eq!(number("18446744073709551615").as_u64(), Some(u64::MAX));
        assert_eq!(number("0").as_u64(), Some(0));
        assert_eq!(Value::Null.as_str(), None);
    }
}
