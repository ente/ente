use super::format::{Syntax, TextSyntax};
use super::{
    Format, MAX_QUOTE_WORDS, MAX_TEXT_ARGUMENT_CHARS, ParameterKind, ToolParameter, ToolRequest,
};
use crate::llm::Error;

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

pub(super) fn integer_range(max: u32) -> String {
    let digits: Vec<u8> = max.to_string().bytes().map(|b| b - b'0').collect();
    let any = |count: usize| match count {
        0 => String::new(),
        1 => " [0-9]".to_owned(),
        count => format!(" [0-9]{{{count}}}"),
    };
    let mut alternatives = Vec::new();
    match digits.len() {
        1 => {}
        2 => alternatives.push("[1-9]".to_owned()),
        n => alternatives.push(format!("[1-9] [0-9]{{0,{}}}", n - 2)),
    }
    let mut prefix = String::new();
    for (i, &digit) in digits.iter().enumerate() {
        let low = u8::from(i == 0);
        if digit > low {
            let rest = any(digits.len() - i - 1);
            alternatives.push(format!("{prefix}[{low}-{}]{rest}", digit - 1));
        }
        prefix.push_str(&format!("\"{digit}\" "));
    }
    alternatives.push(prefix.trim_end().to_owned());
    format!("({})", alternatives.join(" | "))
}

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
    syntax: &'static Syntax,
    request: &'a ToolRequest,
    rules: Vec<String>,
    quote_token: String,
    has_quote: bool,
}

impl Builder<'_> {
    fn text_rule(&self) -> String {
        let n = MAX_TEXT_ARGUMENT_CHARS;
        match self.syntax.text {
            TextSyntax::Delimited(_) => {
                format!("{q} [^<\\x00-\\x1F]{{1,{n}}} {q}", q = self.quote_token)
            }
            TextSyntax::Json => {
                format!("\"\\\"\" ([^\"\\\\\\x00-\\x1F] | \"\\\\\" [\"\\\\]){{1,{n}}} \"\\\"\"")
            }
            TextSyntax::Bare => format!("[^<\\n\\x00-\\x1F]{{1,{n}}}"),
        }
    }

    fn string(&self, inner: &str) -> String {
        match self.syntax.text {
            TextSyntax::Delimited(_) => format!("{q} {inner} {q}", q = self.quote_token),
            TextSyntax::Json => format!("\"\\\"\" {inner} \"\\\"\""),
            TextSyntax::Bare => inner.to_owned(),
        }
    }

    fn piece(&self, text: &str) -> String {
        match self.syntax.text {
            TextSyntax::Json => literal(&json_inner(text)),
            TextSyntax::Delimited(_) | TextSyntax::Bare => literal(text),
        }
    }

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
            ParameterKind::Integer { max } => integer_range(*max),
        }
    }

    fn item(&self, parameter: &ToolParameter) -> String {
        let [before, after, end] = self.syntax.argument;
        let key = literal(&format!("{before}{}{after}", parameter.name));
        let value = self.value(parameter);
        if end.is_empty() {
            format!("{key} {value}")
        } else {
            format!("{key} {value} {}", literal(end))
        }
    }

    fn arguments(&mut self, tool: usize) -> String {
        let spec = &self.request.tools[tool];
        let mut parameters: Vec<_> = spec
            .parameters
            .iter()
            .filter(|parameter| self.has_quote || parameter.kind != ParameterKind::Quote)
            .collect();
        parameters.sort_by(|a, b| a.name.cmp(&b.name));
        let separator = match self.syntax.argument_separator {
            "" => String::new(),
            separator => format!("{} ", literal(separator)),
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
    let syntax = format.syntax();
    let open = token_rule(syntax.open)?;
    let close = token_rule(syntax.close)?;
    let quote_token = match syntax.text {
        TextSyntax::Delimited(quote) => token_rule(quote)?,
        TextSyntax::Json | TextSyntax::Bare => String::new(),
    };
    let mut builder = Builder {
        syntax,
        request,
        rules: Vec::new(),
        quote_token,
        has_quote: false,
    };
    let has_quote = builder.add_quote();
    builder.has_quote = has_quote;
    let [before_name, after_name, end] = syntax.call;
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
        calls.push(format!(
            "{} {arguments} {}",
            literal(&format!("{before_name}{}{after_name}", tool.name)),
            literal(end)
        ));
    }
    if calls.is_empty() {
        return Err(Error::InvalidInput(
            "No tool can be called with this request".into(),
        ));
    }
    let more = request.max_calls() - 1;
    let root = match syntax.list {
        Some([start, separator, end]) => format!(
            "root ::= {open} {} call ({} call){{0,{more}}} {} {close}",
            literal(start),
            literal(separator),
            literal(end)
        ),
        None => {
            let between = match syntax.between {
                "" => String::new(),
                between => format!("{} ", literal(between)),
            };
            format!("root ::= {open} call {close} ({between}{open} call {close}){{0,{more}}}")
        }
    };
    let mut lines = vec![root, format!("call ::= {}", calls.join(" | "))];
    lines.extend(builder.rules);
    Ok(lines.join("\n"))
}
