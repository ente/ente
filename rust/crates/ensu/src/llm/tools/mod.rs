mod format;
mod grammar;

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub(super) use format::Format;

pub const MAX_TOOL_CALLS: u8 = 4;
pub(crate) const MAX_TEXT_ARGUMENT_CHARS: usize = 128;
pub(super) const MAX_QUOTE_WORDS: usize = 192;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Vec<ToolParameter>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolParameter {
    pub name: String,
    pub description: String,
    pub kind: ParameterKind,
    pub required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ParameterKind {
    Text,
    Quote,
    Choice { values: Vec<String> },
    Integer { max: u32 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolRequest {
    pub tools: Vec<ToolSpec>,
    #[serde(default)]
    pub quote_source: String,
    pub max_calls: u8,
    pub min_call_probability: f32,
    #[serde(default)]
    pub examples: Vec<ToolExample>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolExample {
    pub user: String,
    #[serde(default)]
    pub calls: Vec<ToolCall>,
    #[serde(default)]
    pub reply: String,
}

impl ToolRequest {
    pub(super) fn validate(&self) -> Result<(), super::Error> {
        let invalid = |message: &str| Err(super::Error::InvalidInput(message.to_owned()));
        if self.tools.is_empty() {
            return invalid("A tool request needs at least one tool");
        }
        if !(0.0..=1.0).contains(&self.min_call_probability) {
            return invalid("Tool call probability must be between 0 and 1");
        }
        let identifier = |name: &str| {
            !name.is_empty() && name.bytes().all(|b| b.is_ascii_lowercase() || b == b'_')
        };
        let mut names = std::collections::BTreeSet::new();
        for tool in &self.tools {
            if !identifier(&tool.name) || !names.insert(tool.name.as_str()) {
                return invalid("Tool names must be unique lowercase identifiers");
            }
            let mut parameters = std::collections::BTreeSet::new();
            for parameter in &tool.parameters {
                if !identifier(&parameter.name) || !parameters.insert(parameter.name.as_str()) {
                    return invalid("Tool parameter names must be unique lowercase identifiers");
                }
                if let ParameterKind::Choice { values } = &parameter.kind
                    && (values.is_empty()
                        || values
                            .iter()
                            .any(|v| v.is_empty() || v.chars().any(|c| c.is_control() || c == '<')))
                {
                    return invalid("Tool choices must be non-empty plain text");
                }
                if parameter.kind == (ParameterKind::Integer { max: 0 }) {
                    return invalid("Tool integers must allow at least 1");
                }
            }
        }
        Ok(())
    }

    pub(super) fn max_calls(&self) -> usize {
        usize::from(self.max_calls.clamp(1, MAX_TOOL_CALLS))
    }

    fn spec(&self, name: &str) -> Option<&ToolSpec> {
        self.tools.iter().find(|tool| tool.name == name)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ToolValue {
    Integer(i64),
    Text(String),
}

impl ToolValue {
    pub fn as_text(&self) -> Option<&str> {
        match self {
            Self::Text(text) => Some(text),
            Self::Integer(_) => None,
        }
    }

    pub fn as_integer(&self) -> Option<i64> {
        match self {
            Self::Integer(value) => Some(*value),
            Self::Text(_) => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCall {
    pub name: String,
    #[serde(default)]
    pub arguments: BTreeMap<String, ToolValue>,
}

impl ToolCall {
    pub fn text(&self, name: &str) -> Option<&str> {
        self.arguments.get(name).and_then(ToolValue::as_text)
    }

    pub fn integer(&self, name: &str) -> Option<i64> {
        self.arguments.get(name).and_then(ToolValue::as_integer)
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ToolOutcome {
    pub calls: Vec<ToolCall>,
    pub call_probability: Option<f32>,
}

#[derive(Debug)]
pub struct ToolExchange {
    request: ToolRequest,
    outcome: std::sync::Mutex<Option<ToolOutcome>>,
    pub(crate) continuation: Option<std::sync::Arc<dyn ToolContinuation>>,
}

pub(crate) trait ToolContinuation: std::fmt::Debug + Send + Sync {
    fn follow_up(
        &self,
        request: &super::ChatRequest,
        outcome: &ToolOutcome,
    ) -> Option<super::ChatRequest>;

    fn can_finish(&self, outcome: &ToolOutcome, now_ms: i64) -> bool;
}

impl ToolExchange {
    pub fn new(request: ToolRequest) -> Self {
        Self {
            request,
            outcome: std::sync::Mutex::new(None),
            continuation: None,
        }
    }

    pub(crate) fn with_continuation(
        mut self,
        continuation: impl ToolContinuation + 'static,
    ) -> Self {
        self.continuation = Some(std::sync::Arc::new(continuation));
        self
    }

    pub fn request(&self) -> &ToolRequest {
        &self.request
    }

    pub(crate) fn record(&self, outcome: Option<ToolOutcome>) {
        *self
            .outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = outcome;
    }

    pub fn outcome(&self) -> Option<ToolOutcome> {
        self.outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
}

pub(crate) fn single_token(
    model: &llama_cpp_2::model::LlamaModel,
    text: &str,
) -> Option<llama_cpp_2::token::LlamaToken> {
    let vocab = model.vocab();
    match vocab.tokenize(text.as_bytes(), false, true).as_slice() {
        [token] if vocab.token_to_piece(*token, true, None) == text.as_bytes() => Some(*token),
        _ => None,
    }
}

pub(crate) fn finished_calls(
    format: Format,
    raw: &[u8],
    request: &ToolRequest,
    complete: bool,
) -> Result<Vec<ToolCall>, super::Error> {
    format
        .parse(&String::from_utf8_lossy(raw), request)
        .map_err(|error| {
            if complete {
                error
            } else {
                super::ToolCallFailure::Unfinished.into()
            }
        })
}

pub(crate) fn grammar(
    format: Format,
    request: &ToolRequest,
    model: &llama_cpp_2::model::LlamaModel,
) -> Result<String, super::Error> {
    grammar::grammar(format, request, &|text| {
        single_token(model, text).map(|token| token.0)
    })
}

pub(crate) fn adapt_messages(
    format: Option<Format>,
    messages: Vec<super::ChatMessage>,
    tools: Option<&ToolRequest>,
    has_token: &dyn Fn(&str) -> bool,
) -> Vec<super::ChatMessage> {
    let mut output = Vec::with_capacity(messages.len() + 1);
    if let (Some(format), Some(tools)) = (format, tools) {
        let declarations = format.declarations(&tools.tools, &tools.examples, has_token);
        let system = messages
            .first()
            .filter(|message| message.role == "system")
            .map(|message| message.content.as_str());
        let content = match (format, system) {
            (_, None) | (_, Some("")) => declarations,
            (Format::Gemma, Some(system)) => format!("{}{declarations}", system.trim()),
            (Format::Lfm, Some(system)) => format!("{system}\n{declarations}"),
            (Format::Qwen, Some(system)) => format!("{system}\n\n{declarations}"),
        };
        output.push(super::ChatMessage::new("system", content));
    }
    let skip =
        usize::from(!output.is_empty() && messages.first().is_some_and(|m| m.role == "system"));
    let mut pending_calls = std::collections::VecDeque::new();
    for message in messages.into_iter().skip(skip) {
        if message.role == "assistant" && !message.tool_calls.is_empty() {
            pending_calls = message
                .tool_calls
                .iter()
                .map(|call| call.name.clone())
                .collect();
            let content = match format {
                None => message.content,
                Some(Format::Qwen) if !message.content.trim().is_empty() => {
                    format!(
                        "{}\n\n{}",
                        message.content,
                        Format::Qwen.render_calls(&message.tool_calls)
                    )
                }
                Some(format) => format!(
                    "{}{}",
                    format.render_calls(&message.tool_calls),
                    message.content
                ),
            };
            if !content.is_empty() {
                output.push(super::ChatMessage::new("assistant", content));
            }
            continue;
        }
        if message.role == "tool" {
            let name = pending_calls.pop_front();
            output.push(match format {
                Some(format) => super::ChatMessage::new(
                    "tool",
                    format.render_response(
                        name.as_deref().unwrap_or("tool"),
                        &message.content,
                        has_token,
                    ),
                ),
                None => super::ChatMessage::new("assistant", message.content),
            });
            continue;
        }
        pending_calls.clear();
        output.push(super::ChatMessage::new(message.role, message.content));
    }
    output
}

#[cfg(test)]
mod tests;
