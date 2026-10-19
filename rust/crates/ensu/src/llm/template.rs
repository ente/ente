use llama_cpp_2::model::{LlamaChatMessage, LlamaChatTemplate, LlamaModel};

use super::{ChatMessage, Error, format_error};

const LFM_SHA256: [u8; 32] = [
    0x01, 0x3e, 0xed, 0x60, 0x54, 0x64, 0x34, 0xb6, 0x96, 0x7e, 0x34, 0x83, 0x15, 0x3d, 0x8c, 0x5c,
    0x37, 0xab, 0xcb, 0x1d, 0x66, 0x7f, 0x8b, 0x1f, 0x91, 0x46, 0x83, 0xf2, 0xa9, 0x41, 0x15, 0x31,
];
const GEMMA_SHA256: [u8; 32] = [
    0x24, 0x1c, 0x50, 0xd8, 0x6b, 0xdf, 0xe5, 0xe4, 0x33, 0x07, 0xda, 0x87, 0xf5, 0x59, 0xcd, 0x24,
    0x16, 0xaa, 0xcd, 0x67, 0xa8, 0xde, 0x46, 0xc1, 0x5a, 0xcc, 0x01, 0x05, 0xef, 0x22, 0x00, 0xb7,
];
const QWEN_SHA256: [u8; 32] = [
    0x7f, 0x0e, 0x52, 0x90, 0x32, 0xc2, 0x51, 0x83, 0xbc, 0xd6, 0x6c, 0x7f, 0x23, 0x8d, 0xa2, 0xd3,
    0x77, 0xf4, 0x3b, 0xe7, 0x54, 0xa9, 0x4e, 0x27, 0x25, 0xa5, 0x8c, 0x4e, 0x16, 0xd2, 0xed, 0x67,
];

pub(super) fn build_chat_prompt(
    model: &LlamaModel,
    messages: Vec<ChatMessage>,
    template_override: Option<String>,
    add_assistant: bool,
) -> Result<String, Error> {
    let source = match template_override {
        Some(template) => template,
        None => model
            .chat_template(None)
            .ok()
            .and_then(|template| template.to_string().ok())
            .unwrap_or_else(|| "chatml".to_owned()),
    };
    if !source.is_empty()
        && source != "chatml"
        && source
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"-._".contains(&byte))
    {
        let template = LlamaChatTemplate::new(&source)
            .map_err(|err| Error::InvalidInput(format_error("Invalid template", err)))?;
        let chat = messages
            .iter()
            .map(|message| LlamaChatMessage::new(message.role.clone(), message.content.clone()))
            .collect::<Result<Vec<_>, _>>()
            .map_err(|err| Error::InvalidInput(format_error("Invalid chat message", err)))?;
        if let Ok(prompt) = model.apply_chat_template(&template, &chat, add_assistant) {
            return Ok(prompt);
        }
    }
    let vocab = model.vocab();
    let special_token = |token: llama_cpp_2::token::LlamaToken| {
        if token.0 < 0 {
            return Ok(String::new());
        }
        String::from_utf8(vocab.token_to_piece(token, true, None))
            .map_err(|err| Error::InvalidInput(format_error("Invalid special token", err)))
    };
    render(
        &source,
        &special_token(vocab.bos())?,
        &special_token(vocab.eos())?,
        &messages,
        add_assistant,
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Template {
    ChatMl,
    Lfm,
    Gemma,
    Qwen,
}

impl Template {
    fn identify(source: &str) -> Result<Self, Error> {
        if source.is_empty() || source == "chatml" {
            return Ok(Self::ChatMl);
        }
        match ente_ensu_crypto::sha256(source.as_bytes()) {
            LFM_SHA256 => Ok(Self::Lfm),
            GEMMA_SHA256 => Ok(Self::Gemma),
            QWEN_SHA256 => Ok(Self::Qwen),
            _ => Err(Error::Unsupported(
                "This model's chat template is not supported by this version of Ensu",
            )),
        }
    }
}

fn render(
    source: &str,
    bos: &str,
    eos: &str,
    messages: &[ChatMessage],
    add_assistant: bool,
) -> Result<String, Error> {
    if [source, bos, eos].iter().any(|value| value.contains('\0')) {
        return Err(Error::InvalidInput(
            "Invalid template input: embedded NUL".to_owned(),
        ));
    }
    match Template::identify(source)? {
        Template::ChatMl => {
            let mut prompt = String::new();
            for message in messages {
                chatml_turn(&mut prompt, role(message), &message.content);
            }
            if add_assistant {
                prompt.push_str("<|im_start|>assistant\n");
            }
            Ok(prompt)
        }
        Template::Lfm => Ok(render_lfm(bos, messages, add_assistant)),
        Template::Gemma => Ok(render_gemma(bos, messages, add_assistant)),
        Template::Qwen => render_qwen(messages, add_assistant),
    }
}

fn role(message: &ChatMessage) -> &str {
    if message.role == "developer" {
        "system"
    } else {
        &message.role
    }
}

fn trim(text: &str) -> &str {
    text.trim_matches([' ', '\t', '\n', '\r', '\u{b}', '\u{c}'])
}

fn chatml_turn(prompt: &mut String, role: &str, content: &str) {
    prompt.push_str("<|im_start|>");
    prompt.push_str(role);
    prompt.push('\n');
    prompt.push_str(content);
    prompt.push_str("<|im_end|>\n");
}

fn template_error(message: &str) -> Error {
    Error::Llama {
        op: "Failed to apply chat template",
        message: message.to_owned(),
    }
}

fn render_lfm(bos: &str, mut messages: &[ChatMessage], add_assistant: bool) -> String {
    let mut prompt = bos.to_owned();
    if let Some(first) = messages.first()
        && role(first) == "system"
    {
        if !first.content.is_empty() {
            chatml_turn(&mut prompt, "system", &first.content);
        }
        messages = &messages[1..];
    }
    let last_assistant = messages
        .iter()
        .rposition(|message| role(message) == "assistant");
    for (index, message) in messages.iter().enumerate() {
        let content = if role(message) == "assistant" && Some(index) != last_assistant {
            message
                .content
                .rsplit_once("</think>")
                .map_or(message.content.as_str(), |(_, tail)| trim(tail))
        } else {
            &message.content
        };
        chatml_turn(&mut prompt, role(message), content);
    }
    if add_assistant {
        prompt.push_str("<|im_start|>assistant\n");
    }
    prompt
}

fn render_gemma(bos: &str, mut messages: &[ChatMessage], add_assistant: bool) -> String {
    let mut prompt = bos.to_owned();
    if let Some(first) = messages.first()
        && role(first) == "system"
    {
        prompt.push_str("<|turn>system\n");
        prompt.push_str(trim(&first.content));
        prompt.push_str("<turn|>\n");
        messages = &messages[1..];
    }
    let mut previous_role = None;
    let mut turns = messages
        .iter()
        .filter(|message| role(message) != "tool")
        .peekable();
    while let Some(message) = turns.next() {
        let current_role = role(message);
        let rendered_role = if current_role == "assistant" {
            "model"
        } else {
            current_role
        };
        if rendered_role != "model" || previous_role != Some("assistant") {
            prompt.push_str("<|turn>");
            prompt.push_str(rendered_role);
            prompt.push('\n');
        }
        if rendered_role == "model" {
            let content: String = message
                .content
                .split("<channel|>")
                .map(|part| part.split_once("<|channel>").map_or(part, |(text, _)| text))
                .collect();
            prompt.push_str(trim(&content));
        } else {
            prompt.push_str(trim(&message.content));
        }
        if rendered_role != "model" || turns.peek().is_none_or(|next| role(next) != "assistant") {
            prompt.push_str("<turn|>\n");
        }
        previous_role = Some(current_role);
    }
    if add_assistant {
        prompt.push_str("<|turn>model\n");
    }
    prompt
}

fn render_qwen(messages: &[ChatMessage], add_assistant: bool) -> Result<String, Error> {
    if messages.is_empty() {
        return Err(template_error("No messages provided."));
    }
    let last_query = messages
        .iter()
        .rposition(|message| {
            let content = trim(&message.content);
            role(message) == "user"
                && !(content.starts_with("<tool_response>")
                    && content.ends_with("</tool_response>"))
        })
        .ok_or_else(|| template_error("No user query found in messages."))?;
    let mut prompt = String::new();
    for (index, message) in messages.iter().enumerate() {
        let content = trim(&message.content);
        match role(message) {
            "system" if index == 0 => chatml_turn(&mut prompt, "system", content),
            "system" => return Err(template_error("System message must be at the beginning.")),
            "user" => chatml_turn(&mut prompt, "user", content),
            "assistant" => {
                let (thinking, answer) = if let Some((before, _)) = content.split_once("</think>") {
                    let before = before.trim_end_matches('\n');
                    let thinking = before
                        .rsplit_once("<think>")
                        .map_or(before, |(_, text)| text)
                        .trim_start_matches('\n');
                    let answer = content
                        .rsplit_once("</think>")
                        .map_or(content, |(_, text)| text)
                        .trim_start_matches('\n');
                    (trim(thinking), answer)
                } else {
                    ("", content)
                };
                prompt.push_str("<|im_start|>assistant\n");
                if index > last_query {
                    prompt.push_str("<think>\n");
                    prompt.push_str(thinking);
                    prompt.push_str("\n</think>\n\n");
                }
                prompt.push_str(answer);
                prompt.push_str("<|im_end|>\n");
            }
            "tool" => {
                if index > 0 && role(&messages[index - 1]) != "tool" {
                    prompt.push_str("<|im_start|>user");
                }
                prompt.push_str("\n<tool_response>\n");
                prompt.push_str(content);
                prompt.push_str("\n</tool_response>");
                if messages
                    .get(index + 1)
                    .is_none_or(|next| role(next) != "tool")
                {
                    prompt.push_str("<|im_end|>\n");
                }
            }
            _ => return Err(template_error("Unexpected message role.")),
        }
    }
    if add_assistant {
        prompt.push_str("<|im_start|>assistant\n<think>\n\n</think>\n\n");
    }
    Ok(prompt)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn messages(turns: &[(&str, &str)]) -> Vec<ChatMessage> {
        turns
            .iter()
            .map(|(role, content)| ChatMessage {
                role: (*role).to_owned(),
                content: (*content).to_owned(),
            })
            .collect()
    }

    #[test]
    fn message_boundaries_and_assistant_prefixes() {
        let messages = messages(&[
            ("system", "Be concise."),
            ("user", "नमस्ते 🐈\n<__media__>"),
            ("assistant", "A cat."),
            ("user", "What colour?"),
        ]);
        let chatml = concat!(
            "<|im_start|>system\nBe concise.<|im_end|>\n",
            "<|im_start|>user\nनमस्ते 🐈\n<__media__><|im_end|>\n",
            "<|im_start|>assistant\nA cat.<|im_end|>\n",
            "<|im_start|>user\nWhat colour?<|im_end|>\n",
        );
        let gemma = concat!(
            "<bos><|turn>system\nBe concise.<turn|>\n",
            "<|turn>user\nनमस्ते 🐈\n<__media__><turn|>\n",
            "<|turn>model\nA cat.<turn|>\n",
            "<|turn>user\nWhat colour?<turn|>\n",
        );
        for add_assistant in [false, true] {
            let suffix = if add_assistant {
                "<|im_start|>assistant\n"
            } else {
                ""
            };
            assert_eq!(
                render("chatml", "<bos>", "<eos>", &messages, add_assistant).unwrap(),
                format!("{chatml}{suffix}")
            );
            assert_eq!(
                render_lfm("<|startoftext|>", &messages, add_assistant),
                format!("<|startoftext|>{chatml}{suffix}")
            );
            let suffix = if add_assistant { "<|turn>model\n" } else { "" };
            assert_eq!(
                render_gemma("<bos>", &messages, add_assistant),
                format!("{gemma}{suffix}")
            );
            let suffix = if add_assistant {
                "<|im_start|>assistant\n<think>\n\n</think>\n\n"
            } else {
                ""
            };
            assert_eq!(
                render_qwen(&messages, add_assistant).unwrap(),
                format!("{chatml}{suffix}")
            );
        }
    }

    #[test]
    fn lfm_and_qwen_preserve_their_thinking_history_rules() {
        let messages = messages(&[
            ("user", " First \n"),
            ("assistant", "<think>private</think>\n  Answer  "),
            ("user", "Next"),
            ("assistant", "<think>recent</think>Visible"),
            ("user", "Last"),
        ]);
        assert_eq!(
            render_lfm("<|startoftext|>", &messages, false),
            concat!(
                "<|startoftext|><|im_start|>user\n First \n<|im_end|>\n",
                "<|im_start|>assistant\nAnswer<|im_end|>\n",
                "<|im_start|>user\nNext<|im_end|>\n",
                "<|im_start|>assistant\n<think>recent</think>Visible<|im_end|>\n",
                "<|im_start|>user\nLast<|im_end|>\n",
            )
        );
        assert_eq!(
            render_qwen(&messages, false).unwrap(),
            concat!(
                "<|im_start|>user\nFirst<|im_end|>\n",
                "<|im_start|>assistant\n  Answer<|im_end|>\n",
                "<|im_start|>user\nNext<|im_end|>\n",
                "<|im_start|>assistant\nVisible<|im_end|>\n",
                "<|im_start|>user\nLast<|im_end|>\n",
            )
        );
    }

    #[test]
    fn qwen_preserves_thinking_after_the_last_query() {
        let messages = messages(&[
            ("user", "Hi"),
            ("assistant", "<think> private </think>\n\n Answer "),
        ]);
        assert_eq!(
            render_qwen(&messages, false).unwrap(),
            concat!(
                "<|im_start|>user\nHi<|im_end|>\n",
                "<|im_start|>assistant\n<think>\nprivate\n</think>\n\n Answer<|im_end|>\n",
            )
        );
    }

    #[test]
    fn gemma_removes_thinking_channels_and_merges_assistant_turns() {
        let channels = messages(&[
            ("user", "Hi"),
            (
                "assistant",
                "before<|channel>thought\nhidden<channel|>after<|channel>thought\nsecret<channel|>end",
            ),
            ("user", "Next"),
            ("assistant", "<|channel>thought\nhidden"),
        ]);
        assert_eq!(
            render_gemma("<bos>", &channels, false),
            concat!(
                "<bos><|turn>user\nHi<turn|>\n",
                "<|turn>model\nbeforeafterend<turn|>\n",
                "<|turn>user\nNext<turn|>\n",
                "<|turn>model\n<turn|>\n",
            )
        );
        let consecutive = messages(&[
            ("user", "Hi"),
            ("assistant", " First "),
            ("assistant", " Second "),
            ("assistant", " Third "),
        ]);
        assert_eq!(
            render_gemma("<bos>", &consecutive, false),
            "<bos><|turn>user\nHi<turn|>\n<|turn>model\nFirstSecondThird<turn|>\n"
        );
    }

    #[test]
    fn qwen_rejects_invalid_histories() {
        for turns in [
            vec![],
            vec![("system", "Be concise.")],
            vec![("user", "Hello"), ("system", "Late")],
            vec![("user", "Hello"), ("unknown", "Invalid")],
        ] {
            assert!(render_qwen(&messages(&turns), true).is_err(), "{turns:?}");
        }
    }

    #[test]
    fn unknown_templates_fail_explicitly() {
        for source in [
            "{{ messages[0].content }}",
            "qwen-new",
            "{% if %}",
            "chatml\n",
        ] {
            assert!(matches!(
                Template::identify(source),
                Err(Error::Unsupported(_))
            ));
        }
        assert!(render("bad\0template", "", "", &[], true).is_err());
        assert!(render("chatml", "bad\0bos", "", &[], true).is_err());
        assert!(render("chatml", "", "bad\0eos", &[], true).is_err());
        for source in ["", "chatml"] {
            assert_eq!(
                render(source, "", "", &[], true).unwrap(),
                "<|im_start|>assistant\n"
            );
        }
    }

    #[test]
    #[ignore = "requires ENSU_TEST_MODEL"]
    fn named_templates_still_use_the_safe_llama_api() {
        let model = LlamaModel::load_from_file(
            crate::llm::backend().unwrap(),
            std::env::var("ENSU_TEST_MODEL").unwrap(),
            &llama_cpp_2::model::params::LlamaModelParams::default().with_n_gpu_layers(0),
        )
        .unwrap();
        let messages = |content: &str| {
            vec![ChatMessage {
                role: "user".to_owned(),
                content: content.to_owned(),
            }]
        };
        assert_eq!(
            build_chat_prompt(&model, messages("Hi"), Some("llama2".to_owned()), true).unwrap(),
            "[INST] Hi [/INST]"
        );
        assert!(
            build_chat_prompt(
                &model,
                messages("Hi\0there"),
                Some("llama2".to_owned()),
                true
            )
            .is_err()
        );
        assert!(
            build_chat_prompt(
                &model,
                messages("Hi"),
                Some("new-template".to_owned()),
                true
            )
            .is_err()
        );
    }
}
