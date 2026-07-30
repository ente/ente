use regex::Regex;
use std::sync::LazyLock;

const FILLER_WORDS: &[&str] = &[
    "uh", "um", "uhm", "umm", "uhh", "uhhh", "ah", "eh", "hmm", "hm", "mmm", "mm", "mh", "ha",
    "ehh",
];

static MULTI_SPACE_PATTERN: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s{2,}").unwrap());
static FILLER_PATTERNS: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    FILLER_WORDS
        .iter()
        .map(|word| Regex::new(&format!(r"(?i)\b{}\b[,.]?", regex::escape(word))).unwrap())
        .collect()
});

pub fn filter_transcription_output(text: &str) -> String {
    let mut filtered = text.to_string();

    for pattern in FILLER_PATTERNS.iter() {
        filtered = pattern.replace_all(&filtered, "").to_string();
    }

    filtered = collapse_stutters(&filtered);
    filtered = MULTI_SPACE_PATTERN.replace_all(&filtered, " ").to_string();
    filtered.trim().to_string()
}

fn collapse_stutters(text: &str) -> String {
    let words = text.split_whitespace().collect::<Vec<_>>();
    if words.is_empty() {
        return text.to_string();
    }

    let mut result = Vec::new();
    let mut i = 0;

    while i < words.len() {
        let word = words[i];
        let word_lower = word.to_lowercase();

        if word_lower.len() <= 2 && word_lower.chars().all(|c| c.is_alphabetic()) {
            let mut count = 1;
            while i + count < words.len() && words[i + count].to_lowercase() == word_lower {
                count += 1;
            }

            result.push(word);
            i += if count >= 3 { count } else { 1 };
        } else {
            result.push(word);
            i += 1;
        }
    }

    result.join(" ")
}

#[cfg(test)]
mod tests {
    use super::filter_transcription_output;

    #[test]
    fn removes_filler_words() {
        assert_eq!(
            filter_transcription_output("um hello uh world"),
            "hello world"
        );
    }

    #[test]
    fn collapses_repeated_short_stutters() {
        assert_eq!(filter_transcription_output("I I I think"), "I think");
    }
}
