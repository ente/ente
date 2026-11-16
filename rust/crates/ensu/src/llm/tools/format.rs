use std::collections::BTreeMap;

use serde_json::{Map, Value, json};

use super::{ParameterKind, ToolCall, ToolExample, ToolRequest, ToolSpec, ToolValue};
use crate::llm::Error;

/// A chat format with native tool calls.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Format {
    Lfm,
    Gemma,
    Qwen,
}

pub(super) const GEMMA_QUOTE: &str = "<|\"|>";
const LFM_LIST_START: &str = "<|tool_list_start|>";
const LFM_LIST_END: &str = "<|tool_list_end|>";
const LFM_RESPONSE_START: &str = "<|tool_response_start|>";
const LFM_RESPONSE_END: &str = "<|tool_response_end|>";

fn invalid() -> Error {
    Error::InvalidInput("The model produced an invalid tool call".into())
}

impl Format {
    pub(crate) fn open(self) -> &'static str {
        match self {
            Self::Lfm => "<|tool_call_start|>",
            Self::Gemma => "<|tool_call>",
            Self::Qwen => "<tool_call>",
        }
    }

    pub(crate) fn close(self) -> &'static str {
        match self {
            Self::Lfm => "<|tool_call_end|>",
            Self::Gemma => "<tool_call|>",
            Self::Qwen => "</tool_call>",
        }
    }

    /// Special tokens the format needs as single vocabulary entries.
    pub(crate) fn required_tokens(self) -> &'static [&'static str] {
        match self {
            Self::Lfm => &["<|tool_call_start|>", "<|tool_call_end|>"],
            Self::Gemma => &["<|tool_call>", "<tool_call|>", GEMMA_QUOTE],
            Self::Qwen => &["<tool_call>", "</tool_call>"],
        }
    }

    /// Tool declarations appended to the system turn: the tool list in the
    /// model's own format, then the same guidance for every model.
    pub(crate) fn declarations(
        self,
        tools: &[ToolSpec],
        examples: &[ToolExample],
        has_token: &dyn Fn(&str) -> bool,
    ) -> String {
        let mut text = self.tool_list(tools, has_token);
        text.push_str(&self.guidance(examples));
        text
    }

    /// The tools as the model's chat template lists them.
    fn tool_list(self, tools: &[ToolSpec], has_token: &dyn Fn(&str) -> bool) -> String {
        match self {
            Self::Gemma => tools
                .iter()
                .map(|tool| format!("<|tool>{}<tool|>", gemma_declaration(tool)))
                .collect(),
            Self::Lfm => {
                let list = tools
                    .iter()
                    .map(|tool| json_declaration(tool).to_string())
                    .collect::<Vec<_>>()
                    .join(", ");
                let (start, end) = if has_token(LFM_LIST_START) && has_token(LFM_LIST_END) {
                    (LFM_LIST_START, LFM_LIST_END)
                } else {
                    ("", "")
                };
                format!("List of tools: {start}[{list}]{end}")
            }
            Self::Qwen => {
                let list = tools
                    .iter()
                    .map(|tool| {
                        json!({"type": "function", "function": json_declaration(tool)}).to_string()
                    })
                    .collect::<Vec<_>>()
                    .join("\n");
                format!(
                    "# Tools\n\nYou have access to the following functions:\n\n<tools>\n{list}\n</tools>\n\nIf you choose to call a function ONLY reply in the following format with NO suffix:\n\n<tool_call>\n<function=example_function_name>\n<parameter=example_parameter_1>\nvalue_1\n</parameter>\n</function>\n</tool_call>"
                )
            }
        }
    }

    /// The same guidance for every model, in its own call syntax: call
    /// instead of describing a call, and examples of when a tool fits. Small
    /// models otherwise describe calls in prose and rarely tell when a tool
    /// fits (the To Do eval's routing for LFM2.5-VL-1.6B goes from 41% to
    /// 86% with it).
    fn guidance(self, examples: &[ToolExample]) -> String {
        let syntax = self.render_calls(&[ToolCall {
            name: "tool_name".into(),
            arguments: [("parameter".to_owned(), ToolValue::Text("value".into()))].into(),
        }]);
        let mut text = format!(
            "\nWhen a tool fits the user's request, call it instead of describing it, in this format with nothing else: {syntax}"
        );
        if !examples.is_empty() {
            text.push_str("\n\nExamples:");
            for example in examples {
                let response = if example.calls.is_empty() {
                    example.reply.clone()
                } else {
                    self.render_calls(&example.calls)
                };
                text.push_str(&format!("\nUser: {}\nAssistant: {response}", example.user));
            }
        }
        text
    }

    /// Calls as the model writes them, for history and tests.
    pub(crate) fn render_calls(self, calls: &[ToolCall]) -> String {
        match self {
            Self::Gemma => calls
                .iter()
                .map(|call| {
                    let args = call
                        .arguments
                        .iter()
                        .map(|(key, value)| format!("{key}:{}", gemma_value(value)))
                        .collect::<Vec<_>>()
                        .join(",");
                    format!(
                        "{}call:{}{{{args}}}{}",
                        self.open(),
                        call.name,
                        self.close()
                    )
                })
                .collect(),
            Self::Lfm => {
                let calls = calls
                    .iter()
                    .map(|call| {
                        let args = call
                            .arguments
                            .iter()
                            .map(|(key, value)| format!("{key}={}", json_value(value)))
                            .collect::<Vec<_>>()
                            .join(", ");
                        format!("{}({args})", call.name)
                    })
                    .collect::<Vec<_>>()
                    .join(", ");
                format!("{}[{calls}]{}", self.open(), self.close())
            }
            Self::Qwen => calls
                .iter()
                .map(|call| {
                    let args: String = call
                        .arguments
                        .iter()
                        .map(|(key, value)| {
                            let value = match value {
                                ToolValue::Text(text) => text.clone(),
                                ToolValue::Integer(number) => number.to_string(),
                            };
                            format!("<parameter={key}>\n{value}\n</parameter>\n")
                        })
                        .collect();
                    format!(
                        "{}\n<function={}>\n{args}</function>\n{}",
                        self.open(),
                        call.name,
                        self.close()
                    )
                })
                .collect::<Vec<_>>()
                .join("\n"),
        }
    }

    /// A tool result in the format's response wrapper. Qwen's wrapper is added
    /// by its chat renderer.
    pub(crate) fn render_response(
        self,
        name: &str,
        content: &str,
        has_token: &dyn Fn(&str) -> bool,
    ) -> String {
        match self {
            Self::Gemma => format!(
                "<|tool_response>response:{name}{{value:{GEMMA_QUOTE}{content}{GEMMA_QUOTE}}}<tool_response|>"
            ),
            Self::Lfm if has_token(LFM_RESPONSE_START) && has_token(LFM_RESPONSE_END) => {
                format!("{LFM_RESPONSE_START}{content}{LFM_RESPONSE_END}")
            }
            Self::Lfm | Self::Qwen => content.to_owned(),
        }
    }

    /// Parses grammar-constrained output, starting with the call token.
    pub(crate) fn parse(self, raw: &str, request: &ToolRequest) -> Result<Vec<ToolCall>, Error> {
        let mut reader = Reader(raw);
        let mut calls = Vec::new();
        match self {
            Self::Gemma => {
                while !reader.0.is_empty() {
                    reader.expect(self.open())?;
                    reader.expect("call:")?;
                    let name = reader.word()?;
                    reader.expect("{")?;
                    let mut raw_args = Vec::new();
                    if !reader.take("}") {
                        loop {
                            let key = reader.word()?;
                            reader.expect(":")?;
                            let value = if reader.take(GEMMA_QUOTE) {
                                RawValue::Text(reader.until(GEMMA_QUOTE)?.to_owned())
                            } else {
                                RawValue::Number(reader.digits()?)
                            };
                            raw_args.push((key, value));
                            if reader.take("}") {
                                break;
                            }
                            reader.expect(",")?;
                        }
                    }
                    reader.expect(self.close())?;
                    calls.push(typed_call(request, name, raw_args)?);
                }
            }
            Self::Lfm => {
                reader.expect(self.open())?;
                reader.expect("[")?;
                loop {
                    let name = reader.word()?;
                    reader.expect("(")?;
                    let mut raw_args = Vec::new();
                    if !reader.take(")") {
                        loop {
                            let key = reader.word()?;
                            reader.expect("=")?;
                            let value = if reader.0.starts_with('"') {
                                RawValue::Text(reader.json_string()?)
                            } else {
                                RawValue::Number(reader.digits()?)
                            };
                            raw_args.push((key, value));
                            if reader.take(")") {
                                break;
                            }
                            reader.expect(",")?;
                            reader.take(" ");
                        }
                    }
                    calls.push(typed_call(request, name, raw_args)?);
                    if reader.take("]") {
                        break;
                    }
                    reader.expect(",")?;
                    reader.take(" ");
                }
                reader.expect(self.close())?;
                if !reader.0.is_empty() {
                    return Err(invalid());
                }
            }
            Self::Qwen => {
                while !reader.0.is_empty() {
                    reader.expect(self.open())?;
                    reader.expect("\n<function=")?;
                    let name = reader.word()?;
                    reader.expect(">\n")?;
                    let mut raw_args = Vec::new();
                    while reader.take("<parameter=") {
                        let key = reader.word()?;
                        reader.expect(">\n")?;
                        raw_args.push((
                            key,
                            RawValue::Text(reader.until("\n</parameter>\n")?.to_owned()),
                        ));
                    }
                    reader.expect("</function>\n")?;
                    reader.expect(self.close())?;
                    calls.push(typed_call(request, name, raw_args)?);
                    reader.take("\n");
                }
            }
        }
        if calls.is_empty() || calls.len() > request.max_calls() {
            return Err(invalid());
        }
        Ok(calls)
    }
}

enum RawValue {
    Text(String),
    Number(i64),
}

fn typed_call(
    request: &ToolRequest,
    name: &str,
    raw: Vec<(&str, RawValue)>,
) -> Result<ToolCall, Error> {
    let spec = request.spec(name).ok_or_else(invalid)?;
    let mut arguments = BTreeMap::new();
    for (key, value) in raw {
        let parameter = spec
            .parameters
            .iter()
            .find(|parameter| parameter.name == key)
            .ok_or_else(invalid)?;
        let value = match (&parameter.kind, value) {
            (ParameterKind::Integer { max }, RawValue::Number(number)) => {
                if number < 1 || number > i64::from(*max) {
                    return Err(invalid());
                }
                ToolValue::Integer(number)
            }
            (ParameterKind::Integer { max }, RawValue::Text(text)) => {
                let number: i64 = text.trim().parse().map_err(|_| invalid())?;
                if number < 1 || number > i64::from(*max) {
                    return Err(invalid());
                }
                ToolValue::Integer(number)
            }
            (_, RawValue::Text(text)) => ToolValue::Text(text),
            (_, RawValue::Number(_)) => return Err(invalid()),
        };
        if arguments.insert(key.to_owned(), value).is_some() {
            return Err(invalid());
        }
    }
    if spec
        .parameters
        .iter()
        .any(|parameter| parameter.required && !arguments.contains_key(&parameter.name))
    {
        return Err(invalid());
    }
    Ok(ToolCall {
        name: name.to_owned(),
        arguments,
    })
}

struct Reader<'a>(&'a str);

impl<'a> Reader<'a> {
    fn take(&mut self, prefix: &str) -> bool {
        match self.0.strip_prefix(prefix) {
            Some(rest) => {
                self.0 = rest;
                true
            }
            None => false,
        }
    }

    fn expect(&mut self, prefix: &str) -> Result<(), Error> {
        if self.take(prefix) {
            Ok(())
        } else {
            Err(invalid())
        }
    }

    fn until(&mut self, end: &str) -> Result<&'a str, Error> {
        let (value, rest) = self.0.split_once(end).ok_or_else(invalid)?;
        self.0 = rest;
        Ok(value)
    }

    fn word(&mut self) -> Result<&'a str, Error> {
        let end = self
            .0
            .find(|c: char| !(c.is_ascii_lowercase() || c == '_'))
            .unwrap_or(self.0.len());
        if end == 0 {
            return Err(invalid());
        }
        let (word, rest) = self.0.split_at(end);
        self.0 = rest;
        Ok(word)
    }

    fn digits(&mut self) -> Result<i64, Error> {
        let end = self
            .0
            .find(|c: char| !c.is_ascii_digit())
            .unwrap_or(self.0.len());
        let (digits, rest) = self.0.split_at(end);
        self.0 = rest;
        digits.parse().map_err(|_| invalid())
    }

    fn json_string(&mut self) -> Result<String, Error> {
        let mut values = serde_json::Deserializer::from_str(self.0).into_iter::<String>();
        let value = values.next().ok_or_else(invalid)?.map_err(|_| invalid())?;
        self.0 = &self.0[values.byte_offset()..];
        Ok(value)
    }
}

fn json_value(value: &ToolValue) -> String {
    match value {
        ToolValue::Text(text) => Value::from(text.as_str()).to_string(),
        ToolValue::Integer(number) => number.to_string(),
    }
}

fn gemma_value(value: &ToolValue) -> String {
    match value {
        ToolValue::Text(text) => format!("{GEMMA_QUOTE}{text}{GEMMA_QUOTE}"),
        ToolValue::Integer(number) => number.to_string(),
    }
}

fn json_declaration(tool: &ToolSpec) -> Value {
    let mut properties = Map::new();
    for parameter in &tool.parameters {
        let mut property = json!({"description": parameter.description});
        match &parameter.kind {
            ParameterKind::Text | ParameterKind::Quote => property["type"] = json!("string"),
            ParameterKind::Choice { values } => {
                property["type"] = json!("string");
                property["enum"] = json!(values);
            }
            ParameterKind::Integer { .. } => property["type"] = json!("integer"),
        }
        properties.insert(parameter.name.clone(), property);
    }
    let required: Vec<_> = tool
        .parameters
        .iter()
        .filter(|parameter| parameter.required)
        .map(|parameter| parameter.name.as_str())
        .collect();
    json!({
        "name": tool.name,
        "description": tool.description,
        "parameters": {"type": "object", "properties": properties, "required": required},
    })
}

/// Matches Gemma 4's `format_function_declaration` macro.
fn gemma_declaration(tool: &ToolSpec) -> String {
    let q = GEMMA_QUOTE;
    let mut parameters: Vec<_> = tool.parameters.iter().collect();
    parameters.sort_by(|a, b| a.name.cmp(&b.name));
    let properties = parameters
        .iter()
        .map(|parameter| {
            let mut fields = Vec::new();
            if !parameter.description.is_empty() {
                fields.push(format!("description:{q}{}{q}", parameter.description));
            }
            let kind = match &parameter.kind {
                ParameterKind::Text | ParameterKind::Quote => "STRING",
                ParameterKind::Choice { values } => {
                    let values = values
                        .iter()
                        .map(|value| format!("{q}{value}{q}"))
                        .collect::<Vec<_>>()
                        .join(",");
                    fields.push(format!("enum:[{values}]"));
                    "STRING"
                }
                ParameterKind::Integer { .. } => "INTEGER",
            };
            fields.push(format!("type:{q}{kind}{q}"));
            format!("{}:{{{}}}", parameter.name, fields.join(","))
        })
        .collect::<Vec<_>>()
        .join(",");
    let required = tool
        .parameters
        .iter()
        .filter(|parameter| parameter.required)
        .map(|parameter| format!("{q}{}{q}", parameter.name))
        .collect::<Vec<_>>();
    let mut declaration = format!(
        "declaration:{}{{description:{q}{}{q}",
        tool.name, tool.description
    );
    if !tool.parameters.is_empty() {
        declaration.push_str(",parameters:{");
        declaration.push_str(&format!("properties:{{{properties}}},"));
        if !required.is_empty() {
            declaration.push_str(&format!("required:[{}],", required.join(",")));
        }
        declaration.push_str(&format!("type:{q}OBJECT{q}}}"));
    }
    declaration.push('}');
    declaration
}
