//! Native tool calling for local models.
//!
//! Callers describe tools with [`ToolSpec`] and attach a [`ToolRequest`] to a
//! [`super::ChatRequest`]. Generation then decides between a normal reply and a
//! tool call from the first token, constrains any call to the model's own
//! tool-call syntax, and reports parsed [`ToolCall`]s in the summary. Tool
//! turns in history are rendered through the model's tool-response format.

mod format;
mod grammar;

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub(super) use format::Format;

/// Upper bound on calls in one assistant turn.
pub const MAX_TOOL_CALLS: u8 = 4;
/// Longest free-text argument the grammar allows, in characters.
pub const MAX_TEXT_ARGUMENT_CHARS: usize = 128;
/// Longest source text whose words can be quoted.
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
    /// Free text, up to [`MAX_TEXT_ARGUMENT_CHARS`].
    Text,
    /// A contiguous span of [`ToolRequest::quote_source`]'s words.
    Quote,
    /// One of a fixed set of values.
    Choice { values: Vec<String> },
    /// A positive integer up to `max`.
    Integer { max: u32 },
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolChoice {
    /// The model may reply or call tools.
    #[default]
    Auto,
    /// The model must call a tool.
    Required,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolRequest {
    pub tools: Vec<ToolSpec>,
    #[serde(default)]
    pub choice: ToolChoice,
    /// Text that [`ParameterKind::Quote`] arguments must quote from, usually
    /// the current user message.
    #[serde(default)]
    pub quote_source: String,
    /// Maximum calls in one turn, capped at [`MAX_TOOL_CALLS`].
    pub max_calls: u8,
    /// With [`ToolChoice::Auto`], the minimum probability of the tool-call
    /// token at the first position for the model to call a tool.
    pub min_call_probability: f32,
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

/// Result of the reply-or-call decision for one generation.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ToolOutcome {
    /// Parsed calls, empty when the model replied.
    pub calls: Vec<ToolCall>,
    /// Probability of the tool-call token at the first position, when the
    /// model supports native tool calls.
    pub call_probability: Option<f32>,
    /// False when the model's chat format has no native tool calls, in which
    /// case the request ran as a plain reply.
    pub supported: bool,
}

/// The token for `text` when the vocabulary has it as a single entry.
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

pub(crate) fn grammar(
    format: Format,
    request: &ToolRequest,
    model: &llama_cpp_2::model::LlamaModel,
) -> Result<String, super::Error> {
    grammar::grammar(format, request, &|text| {
        single_token(model, text).map(|token| token.0)
    })
}

/// Rewrites tool declarations, assistant tool calls and tool results into
/// plain role and content messages for `format`. Without a format, calls are
/// dropped and results become assistant text, so history stays readable for
/// models without native tool calls.
pub(crate) fn adapt_messages(
    format: Option<Format>,
    messages: Vec<super::ChatMessage>,
    tools: Option<&ToolRequest>,
    has_token: &dyn Fn(&str) -> bool,
) -> Vec<super::ChatMessage> {
    let mut output = Vec::with_capacity(messages.len() + 1);
    if let (Some(format), Some(tools)) = (format, tools) {
        let declarations = format.declarations(&tools.tools, has_token);
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
    let mut last_call = None::<String>;
    for message in messages.into_iter().skip(skip) {
        if message.role == "assistant" && !message.tool_calls.is_empty() {
            last_call = message.tool_calls.last().map(|call| call.name.clone());
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
            let name = last_call.as_deref().unwrap_or("tool");
            output.push(match format {
                Some(format) => super::ChatMessage::new(
                    "tool",
                    format.render_response(name, &message.content, has_token),
                ),
                None => super::ChatMessage::new("assistant", message.content),
            });
            continue;
        }
        output.push(super::ChatMessage::new(message.role, message.content));
    }
    output
}

#[cfg(test)]
mod tests;
