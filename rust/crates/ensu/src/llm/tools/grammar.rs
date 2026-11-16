//! GBNF for native tool calls. The grammar starts at the format's call token,
//! which generation samples before switching to constrained decoding.

use super::format::GEMMA_QUOTE;
use super::{
    Format, MAX_QUOTE_WORDS, MAX_TEXT_ARGUMENT_CHARS, ParameterKind, ToolParameter, ToolRequest,
};
use crate::llm::Error;

/// A GBNF string literal.
fn literal(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\x{:02X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Text inside a JSON string, as LFM writes Python-style string arguments.
fn json_inner(text: &str) -> String {
    let encoded = serde_json::Value::from(text).to_string();
    encoded[1..encoded.len() - 1].to_owned()
}

fn quote_words(source: &str) -> Vec<&str> {
    let source = source.trim();
    let unspaced = !source.is_ascii() && !source.contains(char::is_whitespace);
    if unspaced {
        source
            .char_indices()
            .map(|(i, c)| &source[i..i + c.len_utf8()])
            .take(MAX_QUOTE_WORDS)
            .collect()
    } else {
        source.split_whitespace().take(MAX_QUOTE_WORDS).collect()
    }
}

struct Builder<'a> {
    format: Format,
    request: &'a ToolRequest,
    rules: Vec<String>,
    quote_token: String,
    has_quote: bool,
}

impl Builder<'_> {
    fn text_rule(&self) -> String {
        let n = MAX_TEXT_ARGUMENT_CHARS;
        match self.format {
            Format::Gemma => format!("{q} [^<\\x00-\\x1F]{{1,{n}}} {q}", q = self.quote_token),
            Format::Lfm => {
                format!("\"\\\"\" ([^\"\\\\\\x00-\\x1F] | \"\\\\\" [\"\\\\]){{1,{n}}} \"\\\"\"")
            }
            Format::Qwen => format!("[^<\\n\\x00-\\x1F]{{1,{n}}}"),
        }
    }

    /// Wraps an inner rule in the format's string delimiters.
    fn string(&self, inner: &str) -> String {
        match self.format {
            Format::Gemma => format!("{q} {inner} {q}", q = self.quote_token),
            Format::Lfm => format!("\"\\\"\" {inner} \"\\\"\""),
            Format::Qwen => inner.to_owned(),
        }
    }

    fn piece(&self, text: &str) -> String {
        match self.format {
            Format::Lfm => literal(&json_inner(text)),
            Format::Gemma | Format::Qwen => literal(text),
        }
    }

    /// Adds `quote ::= ...`: any contiguous run of source words, optionally
    /// without the last word's trailing punctuation. Returns false when the
    /// source has no words.
    fn add_quote(&mut self) -> bool {
        let words = quote_words(&self.request.quote_source);
        if words.is_empty() {
            return false;
        }
        let unspaced = !self.request.quote_source.is_ascii()
            && !self
                .request
                .quote_source
                .trim()
                .contains(char::is_whitespace);
        let separator = if unspaced {
            String::new()
        } else {
            format!("{} ", literal(" "))
        };
        let starts = (0..words.len())
            .map(|i| format!("w{i}"))
            .collect::<Vec<_>>()
            .join(" | ");
        self.rules.push(format!("quote ::= {starts}"));
        for (i, word) in words.iter().enumerate() {
            let mut alternatives = Vec::new();
            if i + 1 < words.len() {
                alternatives.push(format!("{} ({separator}w{})?", self.piece(word), i + 1));
            } else {
                alternatives.push(self.piece(word));
            }
            let trimmed = word
                .trim_end_matches(|c: char| c.is_ascii_punctuation() || "。！？、，".contains(c));
            if !trimmed.is_empty() && trimmed != *word {
                alternatives.push(self.piece(trimmed));
            }
            self.rules
                .push(format!("w{i} ::= {}", alternatives.join(" | ")));
        }
        true
    }

    fn value(&self, parameter: &ToolParameter) -> String {
        match &parameter.kind {
            ParameterKind::Text => self.text_rule(),
            ParameterKind::Quote => self.string("quote"),
            ParameterKind::Choice { values } => {
                let choices = values
                    .iter()
                    .map(|value| self.piece(value))
                    .collect::<Vec<_>>()
                    .join(" | ");
                self.string(&format!("({choices})"))
            }
            ParameterKind::Integer { max } => {
                let digits = max.to_string().len().saturating_sub(1);
                format!("[1-9] [0-9]{{0,{digits}}}")
            }
        }
    }

    fn item(&self, parameter: &ToolParameter) -> String {
        let value = self.value(parameter);
        match self.format {
            Format::Gemma => format!("{} {value}", literal(&format!("{}:", parameter.name))),
            Format::Lfm => format!("{} {value}", literal(&format!("{}=", parameter.name))),
            Format::Qwen => format!(
                "{} {value} {}",
                literal(&format!("<parameter={}>\n", parameter.name)),
                literal("\n</parameter>\n")
            ),
        }
    }

    /// Arguments in name order, as the formats' templates sort them. Optional
    /// arguments may be omitted.
    fn arguments(&mut self, tool: usize) -> String {
        let spec = &self.request.tools[tool];
        let mut parameters: Vec<_> = spec
            .parameters
            .iter()
            .filter(|parameter| self.has_quote || parameter.kind != ParameterKind::Quote)
            .collect();
        parameters.sort_by(|a, b| a.name.cmp(&b.name));
        let separator = match self.format {
            Format::Gemma => format!("{} ", literal(",")),
            Format::Lfm => format!("{} ", literal(", ")),
            Format::Qwen => String::new(),
        };
        let n = parameters.len();
        let rest = |i: usize| format!("t{tool}r{i}");
        let first = |i: usize| format!("t{tool}f{i}");
        self.rules.push(format!("{} ::= \"\"", rest(n)));
        self.rules.push(format!("{} ::= \"\"", first(n)));
        for (i, parameter) in parameters.iter().enumerate().rev() {
            let item = self.item(parameter);
            let present = format!("{separator}{item} {}", rest(i + 1));
            let starting = format!("{item} {}", rest(i + 1));
            if parameter.required {
                self.rules.push(format!("{} ::= {present}", rest(i)));
                self.rules.push(format!("{} ::= {starting}", first(i)));
            } else {
                self.rules
                    .push(format!("{} ::= {present} | {}", rest(i), rest(i + 1)));
                self.rules
                    .push(format!("{} ::= {starting} | {}", first(i), first(i + 1)));
            }
        }
        first(0)
    }
}

pub(crate) fn grammar(
    format: Format,
    request: &ToolRequest,
    token: &dyn Fn(&str) -> Option<i32>,
) -> Result<String, Error> {
    let token_rule = |text: &str| {
        token(text)
            .map(|id| format!("<[{id}]>"))
            .ok_or(Error::Unsupported(
                "This model lacks its native tool-call tokens",
            ))
    };
    let open = token_rule(format.open())?;
    let close = token_rule(format.close())?;
    let quote_token = if format == Format::Gemma {
        token_rule(GEMMA_QUOTE)?
    } else {
        String::new()
    };
    let mut builder = Builder {
        format,
        request,
        rules: Vec::new(),
        quote_token,
        has_quote: false,
    };
    let has_quote = builder.add_quote();
    builder.has_quote = has_quote;
    let mut calls = Vec::new();
    for (index, tool) in request.tools.iter().enumerate() {
        let needs_quote = tool
            .parameters
            .iter()
            .any(|parameter| parameter.required && parameter.kind == ParameterKind::Quote);
        if needs_quote && !has_quote {
            continue;
        }
        let arguments = builder.arguments(index);
        let call = match format {
            Format::Gemma => format!(
                "{} {arguments} {}",
                literal(&format!("call:{}{{", tool.name)),
                literal("}")
            ),
            Format::Lfm => format!(
                "{} {arguments} {}",
                literal(&format!("{}(", tool.name)),
                literal(")")
            ),
            Format::Qwen => format!(
                "{} {arguments} {}",
                literal(&format!("\n<function={}>\n", tool.name)),
                literal("</function>\n")
            ),
        };
        calls.push(call);
    }
    if calls.is_empty() {
        return Err(Error::InvalidInput(
            "No tool can be called with this request".into(),
        ));
    }
    let more = request.max_calls() - 1;
    let root = match format {
        Format::Gemma => format!("root ::= {open} call {close} ({open} call {close}){{0,{more}}}"),
        Format::Lfm => format!(
            "root ::= {open} {} call ({} call){{0,{more}}} {} {close}",
            literal("["),
            literal(", "),
            literal("]")
        ),
        Format::Qwen => format!(
            "root ::= {open} call {close} ({} {open} call {close}){{0,{more}}}",
            literal("\n")
        ),
    };
    let mut lines = vec![root, format!("call ::= {}", calls.join(" | "))];
    lines.extend(builder.rules);
    Ok(lines.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn literals_escape_grammar_metacharacters() {
        assert_eq!(literal("a\"b\\c\nd"), r#""a\"b\\c\nd""#);
        assert_eq!(json_inner("say \"hi\""), r#"say \"hi\""#);
    }

    #[test]
    fn quote_words_split_spaced_and_unspaced_text() {
        assert_eq!(
            quote_words(" Buy  milk\ttomorrow "),
            ["Buy", "milk", "tomorrow"]
        );
        assert_eq!(quote_words("明日牛乳"), ["明", "日", "牛", "乳"]);
        assert!(quote_words("   ").is_empty());
    }
}
