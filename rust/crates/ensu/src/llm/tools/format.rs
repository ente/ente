use std::collections::BTreeMap;

use serde_json::{Map, Value, json};

use super::{ParameterKind, ToolCall, ToolExample, ToolRequest, ToolSpec, ToolValue};
use crate::llm::Error;

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
    crate::llm::ToolCallFailure::Invalid.into()
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TextSyntax {
    Delimited(&'static str),
    Json,
    Bare,
}

pub(super) struct Syntax {
    pub(super) open: &'static str,
    pub(super) close: &'static str,
    pub(super) list: Option<[&'static str; 3]>,
    pub(super) between: &'static str,
    pub(super) call: [&'static str; 3],
    pub(super) argument: [&'static str; 3],
    pub(super) argument_separator: &'static str,
    pub(super) text: TextSyntax,
}

const LFM: Syntax = Syntax {
    open: "<|tool_call_start|>",
    close: "<|tool_call_end|>",
    list: Some(["[", ", ", "]"]),
    between: "",
    call: ["", "(", ")"],
    argument: ["", "=", ""],
    argument_separator: ", ",
    text: TextSyntax::Json,
};

const GEMMA: Syntax = Syntax {
    open: "<|tool_call>",
    close: "<tool_call|>",
    list: None,
    between: "",
    call: ["call:", "{", "}"],
    argument: ["", ":", ""],
    argument_separator: ",",
    text: TextSyntax::Delimited(GEMMA_QUOTE),
};

const QWEN: Syntax = Syntax {
    open: "<tool_call>",
    close: "</tool_call>",
    list: None,
    between: "\n",
    call: ["\n<function=", ">\n", "</function>\n"],
    argument: ["<parameter=", ">\n", "\n</parameter>\n"],
    argument_separator: "",
    text: TextSyntax::Bare,
};

impl Format {
    pub(super) fn syntax(self) -> &'static Syntax {
        match self {
            Self::Lfm => &LFM,
            Self::Gemma => &GEMMA,
            Self::Qwen => &QWEN,
        }
    }

    pub(crate) fn open(self) -> &'static str {
        self.syntax().open
    }

    pub(crate) fn required_tokens(self) -> Vec<&'static str> {
        let syntax = self.syntax();
        let mut tokens = vec![syntax.open, syntax.close];
        if let TextSyntax::Delimited(quote) = syntax.text {
            tokens.push(quote);
        }
        tokens
    }

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

    pub(crate) fn render_calls(self, calls: &[ToolCall]) -> String {
        let syntax = self.syntax();
        let [before_key, after_key, after_value] = syntax.argument;
        let [before_name, after_name, end] = syntax.call;
        let rendered = calls.iter().map(|call| {
            let arguments = call
                .arguments
                .iter()
                .map(|(key, value)| {
                    let value = match (value, syntax.text) {
                        (ToolValue::Integer(number), _) => number.to_string(),
                        (ToolValue::Text(text), TextSyntax::Delimited(q)) => {
                            format!("{q}{text}{q}")
                        }
                        (ToolValue::Text(text), TextSyntax::Json) => {
                            Value::from(text.as_str()).to_string()
                        }
                        (ToolValue::Text(text), TextSyntax::Bare) => text.clone(),
                    };
                    format!("{before_key}{key}{after_key}{value}{after_value}")
                })
                .collect::<Vec<_>>()
                .join(syntax.argument_separator);
            format!("{before_name}{}{after_name}{arguments}{end}", call.name)
        });
        match syntax.list {
            Some([start, separator, end]) => format!(
                "{}{start}{}{end}{}",
                syntax.open,
                rendered.collect::<Vec<_>>().join(separator),
                syntax.close
            ),
            None => rendered
                .map(|call| format!("{}{call}{}", syntax.open, syntax.close))
                .collect::<Vec<_>>()
                .join(syntax.between),
        }
    }

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

    pub(crate) fn parse(self, raw: &str, request: &ToolRequest) -> Result<Vec<ToolCall>, Error> {
        let mut calls = Vec::new();
        self.read_calls(raw, request, &mut calls)?;
        Ok(calls)
    }

    pub(super) fn completed_calls(self, raw: &str, request: &ToolRequest) -> Vec<ToolCall> {
        let mut calls = Vec::new();
        let _ = self.read_calls(raw, request, &mut calls);
        calls
    }

    fn read_calls(
        self,
        raw: &str,
        request: &ToolRequest,
        calls: &mut Vec<ToolCall>,
    ) -> Result<(), Error> {
        let syntax = self.syntax();
        let [before_key, after_key, after_value] = syntax.argument;
        let [before_name, after_name, end] = syntax.call;
        let mut reader = Reader(raw);
        loop {
            reader.expect(syntax.open)?;
            if let Some([start, ..]) = syntax.list {
                reader.expect(start)?;
            }
            loop {
                if calls.len() == request.max_calls() {
                    return Err(invalid());
                }
                reader.expect(before_name)?;
                let name = reader.word()?;
                reader.expect(after_name)?;
                let mut raw_args = Vec::new();
                while !reader.take(end) {
                    if !raw_args.is_empty() {
                        reader.expect(syntax.argument_separator)?;
                    }
                    reader.expect(before_key)?;
                    let key = reader.word()?;
                    reader.expect(after_key)?;
                    let value = match syntax.text {
                        TextSyntax::Bare => RawValue::Text(reader.until(after_value)?.to_owned()),
                        TextSyntax::Delimited(q) if reader.take(q) => {
                            RawValue::Text(reader.until(q)?.to_owned())
                        }
                        TextSyntax::Json if reader.0.starts_with('"') => {
                            RawValue::Text(reader.json_string()?)
                        }
                        _ => RawValue::Number(reader.digits()?),
                    };
                    if syntax.text != TextSyntax::Bare {
                        reader.expect(after_value)?;
                    }
                    raw_args.push((key, value));
                }
                let call = typed_call(request, name, raw_args)?;
                match syntax.list {
                    Some([_, separator, end]) => {
                        calls.push(call);
                        if reader.take(end) {
                            reader.expect(syntax.close)?;
                            break;
                        }
                        reader.expect(separator)?;
                    }
                    None => {
                        reader.expect(syntax.close)?;
                        calls.push(call);
                        break;
                    }
                }
            }
            if reader.0.is_empty() {
                break;
            }
            if syntax.list.is_some() {
                return Err(invalid());
            }
            reader.expect(syntax.between)?;
            if reader.0.is_empty() {
                return Err(invalid());
            }
        }
        Ok(())
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
    let spec = request
        .spec(name)
        .filter(|_| request.allows(name))
        .ok_or_else(invalid)?;
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
