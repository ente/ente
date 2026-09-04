use std::path::Path;

use crate::error::{MlError, MlResult};

const BLANK_TOKEN: &str = "blank";
const SPACE_TOKEN: &str = " ";

pub(crate) fn load_dictionary(path: &Path, expected_size: usize) -> MlResult<Vec<String>> {
    let contents = std::fs::read_to_string(path).map_err(|error| {
        MlError::CorruptModel(format!(
            "cannot read OCR dictionary {}: {error}",
            path.display()
        ))
    })?;
    let mut entries = Vec::with_capacity(expected_size);
    entries.push(BLANK_TOKEN.to_string());
    entries.extend(contents.lines().map(str::to_string));
    entries.push(SPACE_TOKEN.to_string());
    if entries.len() != expected_size {
        return Err(MlError::CorruptModel(format!(
            "OCR dictionary {} has {} entries, recognizer expects {expected_size}",
            path.display(),
            entries.len()
        )));
    }
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use std::io::Write;

    use super::*;

    fn temp_dictionary(contents: &[u8]) -> tempfile::NamedTempFile {
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(contents).unwrap();
        file.flush().unwrap();
        file
    }

    #[test]
    fn wraps_lines_with_blank_and_space() {
        let file = temp_dictionary("\u{3000}\r\na\n \nb\n".as_bytes());
        let entries = load_dictionary(file.path(), 6).unwrap();
        assert_eq!(entries, ["blank", "\u{3000}", "a", " ", "b", " "]);
    }

    #[test]
    fn rejects_unexpected_entry_count() {
        let file = temp_dictionary(b"a\nb\nc\n");
        let error = load_dictionary(file.path(), 6).unwrap_err();
        assert!(matches!(error, MlError::CorruptModel(_)), "{error}");
        assert!(error.to_string().contains("has 5 entries"), "{error}");
    }
}
