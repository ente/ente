use std::collections::HashMap;
use std::sync::LazyLock;

use crate::error::{Error, Result};

const MAX_REACTION_BYTES: usize = 128;
const CATALOG: &str = include_str!("../data/reaction-emoji.txt");
static REACTIONS: LazyLock<HashMap<String, &'static str>> =
    LazyLock::new(|| CATALOG.lines().map(|emoji| (key(emoji), emoji)).collect());

fn key(emoji: &str) -> String {
    emoji.chars().filter(|c| *c != '\u{fe0f}').collect()
}

pub(crate) fn canonical_reaction(emoji: &str) -> Result<&'static str> {
    validate_received_reaction(emoji)?;
    REACTIONS
        .get(&key(emoji))
        .copied()
        .ok_or_else(|| Error::InvalidInput("invalid message reaction".into()))
}

pub(crate) fn validate_received_reaction(emoji: &str) -> Result<()> {
    if emoji.trim().is_empty()
        || emoji.len() > MAX_REACTION_BYTES
        || emoji.chars().any(char::is_control)
    {
        return Err(Error::InvalidInput("invalid message reaction".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_accepts_fully_qualified_sequences_and_optional_emoji_selectors() {
        assert_eq!(CATALOG.lines().count(), 3944);
        for emoji in CATALOG.lines() {
            assert_eq!(canonical_reaction(emoji).unwrap(), emoji);
            assert_eq!(canonical_reaction(&key(emoji)).unwrap(), emoji);
        }
        assert_eq!(canonical_reaction("👍️").unwrap(), "👍");
        assert_eq!(canonical_reaction("❤").unwrap(), "❤️");
    }

    #[test]
    fn rejects_text_multiple_emoji_and_incomplete_sequences_for_sending() {
        for invalid in ["", "hello", "😂😂", " 😂", "🏽", "🇮", "👩\u{200d}"] {
            assert!(canonical_reaction(invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn preserves_future_values_with_bounded_input() {
        assert!(canonical_reaction("\u{1faff}").is_err());
        assert!(validate_received_reaction("\u{1faff}").is_ok());
        for invalid in ["", " ", "😂\n", &"a".repeat(MAX_REACTION_BYTES + 1)] {
            assert!(validate_received_reaction(invalid).is_err());
        }
    }
}
