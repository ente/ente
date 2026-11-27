use std::borrow::Cow;
use std::collections::{HashMap, HashSet};

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
    tokens: HashMap<char, Vec<String>>,
    separator: Option<char>,
    use_angle_quote: bool,
}

impl Specials {
    pub(crate) fn new(tokens: impl IntoIterator<Item = String>) -> Self {
        let mut specials = Self::default();
        let mut chars = HashSet::new();
        for text in tokens
            .into_iter()
            .chain(MARKERS.iter().map(|s| (*s).into()))
        {
            if let Some(first) = text.chars().next()
                && text != "<__media__>"
            {
                chars.extend(text.chars());
                specials.tokens.entry(first).or_default().push(text);
            }
        }
        for tokens in specials.tokens.values_mut() {
            tokens.sort_unstable_by_key(String::len);
        }
        specials.use_angle_quote = !chars.contains(&'‹');
        specials.separator = std::iter::once('\u{200b}')
            .chain(('\u{e000}'..='\u{f8ff}').chain('\u{f0000}'..='\u{ffffd}'))
            .find(|c| !chars.contains(c));
        specials
    }

    pub(crate) fn plain<'a>(&self, text: &'a str) -> Cow<'a, str> {
        if self.tokens.is_empty() {
            return Cow::Borrowed(text);
        }
        let mut plain = None;
        let mut copied = 0;
        for (at, first) in text.char_indices() {
            let Some(token) = self.tokens.get(&first).and_then(|tokens| {
                tokens
                    .iter()
                    .find(|token| text[at..].starts_with(token.as_str()))
            }) else {
                continue;
            };
            let Some(separator) = self.separator else {
                return Cow::Borrowed("");
            };
            let output = plain.get_or_insert_with(|| String::with_capacity(text.len()));
            output.push_str(&text[copied..at]);
            copied = at + first.len_utf8();
            if first == '<' && self.use_angle_quote {
                output.push('‹');
            } else {
                if first != '<' && first.len_utf8() < token.len() {
                    output.push(first);
                }
                output.push(separator);
            }
        }
        match plain {
            Some(mut output) => {
                output.push_str(&text[copied..]);
                Cow::Owned(output)
            }
            None => Cow::Borrowed(text),
        }
    }
}
