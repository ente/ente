use std::borrow::Cow;
use std::collections::{BTreeMap, HashSet};

const MARKERS: &[&str] = &[
    "<|im_start|>",
    "<|im_end|>",
    "<think>",
    "</think>",
    "<tool_call>",
    "</tool_call>",
    "<tool_response>",
    "</tool_response>",
    "<tools>",
    "</tools>",
    "<|turn>",
    "<turn|>",
    "<|tool>",
    "<tool|>",
    "<|tool_call>",
    "<tool_call|>",
    "<|tool_response>",
    "<tool_response|>",
    "<|\"|>",
    "<|channel>",
    "<channel|>",
    "<|think|>",
    "<|tool_call_start|>",
    "<|tool_call_end|>",
    "<|tool_list_start|>",
    "<|tool_list_end|>",
    "<|tool_response_start|>",
    "<|tool_response_end|>",
];

#[derive(Default)]
pub(crate) struct Specials {
    tokens: BTreeMap<usize, HashSet<String>>,
    separator: Option<char>,
}

impl Specials {
    pub(crate) fn new(tokens: impl IntoIterator<Item = String>) -> Self {
        let mut specials = Self::default();
        let mut chars = HashSet::new();
        for text in tokens
            .into_iter()
            .chain(MARKERS.iter().map(|s| (*s).into()))
        {
            if !text.is_empty() && text != "<__media__>" {
                chars.extend(text.chars());
                specials.tokens.entry(text.len()).or_default().insert(text);
            }
        }
        specials.separator = std::iter::once('\u{200b}')
            .chain(('\u{e000}'..='\u{f8ff}').chain('\u{f0000}'..='\u{ffffd}'))
            .find(|c| !chars.contains(c));
        specials
    }

    pub(crate) fn plain<'a>(&self, text: &'a str) -> Cow<'a, str> {
        let mut plain = Cow::Borrowed(text);
        if self.tokens.is_empty() {
            return plain;
        }
        while let Some((at, first, len)) = self.first_match(&plain) {
            if first == '<' {
                plain.to_mut().replace_range(at..at + 1, "‹");
            } else if first.len_utf8() < len
                && let Some(separator) = self.separator
            {
                plain.to_mut().insert(at + first.len_utf8(), separator);
            } else {
                plain.to_mut().remove(at);
            }
        }
        plain
    }

    fn first_match(&self, text: &str) -> Option<(usize, char, usize)> {
        for (at, first) in text.char_indices() {
            for (&len, tokens) in self.tokens.iter().rev() {
                if text
                    .get(at..at + len)
                    .is_some_and(|part| tokens.contains(part))
                {
                    return Some((at, first, len));
                }
            }
        }
        None
    }
}
