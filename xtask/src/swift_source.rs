//! Reads the repository's Swift files as code, without comments or string contents.

use crate::failure::{Context, Result, ensure};
use std::{
    fs,
    path::{Path, PathBuf},
};

/// The directories whose Swift code ships in the app or its packages.
pub const SHIPPED: [&str; 2] = ["App", "Sources"];

/// One Swift file with its path relative to the repository root.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Source {
    pub file: String,
    pub text: String,
}

/// The code of a Swift file with comments removed and string contents blanked.
/// Line numbers stay the same, so a finding can name its line.
pub fn code_only(source: &str) -> String {
    let mut code = String::with_capacity(source.len());
    let mut characters = source.chars().peekable();
    while let Some(character) = characters.next() {
        match character {
            '/' if characters.peek() == Some(&'/') => {
                for next in characters.by_ref() {
                    if next == '\n' {
                        code.push('\n');
                        break;
                    }
                }
            }
            '/' if characters.peek() == Some(&'*') => {
                characters.next();
                let mut previous = ' ';
                for next in characters.by_ref() {
                    if next == '\n' {
                        code.push('\n');
                    }
                    if previous == '*' && next == '/' {
                        break;
                    }
                    previous = next;
                }
            }
            '"' => {
                code.push('"');
                while let Some(next) = characters.next() {
                    match next {
                        '\\' => {
                            characters.next();
                            code.push(' ');
                        }
                        '"' => break,
                        '\n' => code.push('\n'),
                        _ => code.push(' '),
                    }
                }
                code.push('"');
            }
            _ => code.push(character),
        }
    }
    code
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn comments_and_string_contents_are_blanked_and_lines_are_kept() {
        assert_eq!(code_only("a // b\nc"), "a \nc");
        assert_eq!(code_only("a /* b\nc */ d"), "a \n d");
        assert_eq!(code_only("let x = \"print(y)\""), "let x = \"        \"");
        assert_eq!(code_only("\"a\\\"b\""), "\"   \"");
    }

    #[test]
    fn only_whole_identifiers_count_as_names() {
        assert!(names("_ = stat(path, &info)", "stat"));
        assert!(!names("let status = state", "stat"));
        assert!(!names("blueprint(x)", "print"));
    }
}
