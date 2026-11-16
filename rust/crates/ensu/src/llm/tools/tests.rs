use super::*;
use crate::llm::ChatMessage;

fn request(quote_source: &str) -> ToolRequest {
    ToolRequest {
        tools: vec![
            ToolSpec {
                name: "save_to_do".into(),
                description: "Save a task.".into(),
                parameters: vec![
                    ToolParameter {
                        name: "title".into(),
                        description: "Task title.".into(),
                        kind: ParameterKind::Text,
                        required: true,
                    },
                    ToolParameter {
                        name: "when".into(),
                        description: "Deadline quoted from the user.".into(),
                        kind: ParameterKind::Quote,
                        required: false,
                    },
                ],
            },
            ToolSpec {
                name: "list_to_dos".into(),
                description: "List tasks.".into(),
                parameters: vec![ToolParameter {
                    name: "filter".into(),
                    description: "Which tasks.".into(),
                    kind: ParameterKind::Choice {
                        values: vec!["open".into(), "completed".into()],
                    },
                    required: true,
                }],
            },
            ToolSpec {
                name: "complete_to_do".into(),
                description: "Complete a task.".into(),
                parameters: vec![ToolParameter {
                    name: "number".into(),
                    description: "Displayed number.".into(),
                    kind: ParameterKind::Integer { max: 20 },
                    required: true,
                }],
            },
        ],
        choice: ToolChoice::Auto,
        quote_source: quote_source.into(),
        max_calls: 3,
        min_call_probability: 0.5,
        examples: vec![
            ToolExample {
                user: "Anything left?".into(),
                calls: vec![ToolCall {
                    name: "list_to_dos".into(),
                    arguments: [("filter".to_owned(), ToolValue::Text("open".into()))].into(),
                }],
                reply: String::new(),
            },
            ToolExample {
                user: "Hi".into(),
                calls: vec![],
                reply: "Hello!".into(),
            },
        ],
    }
}

#[test]
fn every_format_gets_the_same_guidance_in_its_own_syntax() {
    let request = request("x");
    let guidance = |call: &str, example: &str| {
        format!(
            "\nWhen a tool fits the user's request, call it instead of describing it, in this format with nothing else: {call}\n\nExamples:\nUser: Anything left?\nAssistant: {example}\nUser: Hi\nAssistant: Hello!"
        )
    };
    let lfm = Format::Lfm.declarations(&request.tools, &request.examples, &|_| false);
    assert!(lfm.starts_with("List of tools: [{"));
    assert!(lfm.ends_with(&guidance(
        "<|tool_call_start|>[tool_name(parameter=\"value\")]<|tool_call_end|>",
        "<|tool_call_start|>[list_to_dos(filter=\"open\")]<|tool_call_end|>",
    )));
    let gemma = Format::Gemma.declarations(&request.tools, &request.examples, &|_| true);
    assert!(gemma.ends_with(&guidance(
        "<|tool_call>call:tool_name{parameter:<|\"|>value<|\"|>}<tool_call|>",
        "<|tool_call>call:list_to_dos{filter:<|\"|>open<|\"|>}<tool_call|>",
    )));
    let qwen = Format::Qwen.declarations(&request.tools, &request.examples, &|_| true);
    assert!(qwen.contains("\n\nExamples:\nUser: Anything left?\nAssistant: <tool_call>"));
}

fn calls() -> Vec<ToolCall> {
    vec![
        ToolCall {
            name: "save_to_do".into(),
            arguments: [
                ("title".to_owned(), ToolValue::Text("Call \"Lee\"".into())),
                (
                    "when".to_owned(),
                    ToolValue::Text("tomorrow at 4 PM".into()),
                ),
            ]
            .into(),
        },
        ToolCall {
            name: "list_to_dos".into(),
            arguments: [("filter".to_owned(), ToolValue::Text("open".into()))].into(),
        },
        ToolCall {
            name: "complete_to_do".into(),
            arguments: [("number".to_owned(), ToolValue::Integer(2))].into(),
        },
    ]
}

#[test]
fn every_format_parses_what_it_renders() {
    let request = request("Call Lee tomorrow at 4 PM");
    for format in [Format::Lfm, Format::Gemma, Format::Qwen] {
        let rendered = format.render_calls(&calls());
        assert_eq!(
            format.parse(&rendered, &request).unwrap(),
            calls(),
            "{format:?}"
        );
    }
}

#[test]
fn parsing_rejects_unknown_tools_bad_types_and_missing_arguments() {
    let request = request("x");
    for (format, raw) in [
        (Format::Gemma, "<|tool_call>call:delete_all{}<tool_call|>"),
        (
            Format::Gemma,
            "<|tool_call>call:complete_to_do{number:0}<tool_call|>",
        ),
        (
            Format::Gemma,
            "<|tool_call>call:complete_to_do{number:21}<tool_call|>",
        ),
        (Format::Gemma, "<|tool_call>call:save_to_do{}<tool_call|>"),
        (
            Format::Lfm,
            "<|tool_call_start|>[list_to_dos(filter=2)]<|tool_call_end|>",
        ),
        (
            Format::Lfm,
            "<|tool_call_start|>[list_to_dos(filter=\"open\")]<|tool_call_end|>x",
        ),
        (
            Format::Qwen,
            "<tool_call>\n<function=complete_to_do>\n<parameter=number>\ntwo\n</parameter>\n</function>\n</tool_call>",
        ),
    ] {
        assert!(format.parse(raw, &request).is_err(), "{raw}");
    }
    let mut limited = request;
    limited.max_calls = 1;
    let two = Format::Gemma.render_calls(&calls()[1..]);
    assert!(Format::Gemma.parse(&two, &limited).is_err());
}

#[test]
fn gemma_declarations_follow_the_model_template() {
    let declarations = Format::Gemma.declarations(&request("x").tools[1..2], &[], &|_| true);
    assert_eq!(
        declarations.split('\n').next().unwrap(),
        concat!(
            "<|tool>declaration:list_to_dos{description:<|\"|>List tasks.<|\"|>,parameters:{",
            "properties:{filter:{description:<|\"|>Which tasks.<|\"|>,enum:[<|\"|>open<|\"|>,<|\"|>completed<|\"|>],",
            "type:<|\"|>STRING<|\"|>}},required:[<|\"|>filter<|\"|>],type:<|\"|>OBJECT<|\"|>}}<tool|>"
        )
    );
}

#[test]
fn history_renders_native_calls_and_results_and_falls_back_to_text() {
    let mut assistant = ChatMessage::new("assistant", "");
    assistant.tool_calls = calls()[1..2].to_vec();
    let messages = vec![
        ChatMessage::new("system", "Be brief."),
        ChatMessage::new("user", "What is open?"),
        assistant,
        ChatMessage::new("tool", "1. Call Lee"),
        ChatMessage::new("user", "Thanks"),
    ];
    let request = request("Thanks");
    let gemma = adapt_messages(
        Some(Format::Gemma),
        messages.clone(),
        Some(&request),
        &|_| true,
    );
    assert!(
        gemma[0]
            .content
            .starts_with("Be brief.<|tool>declaration:save_to_do")
    );
    assert_eq!(
        gemma[2].content,
        "<|tool_call>call:list_to_dos{filter:<|\"|>open<|\"|>}<tool_call|>"
    );
    assert_eq!(
        gemma[3],
        ChatMessage::new(
            "tool",
            "<|tool_response>response:list_to_dos{value:<|\"|>1. Call Lee<|\"|>}<tool_response|>"
        )
    );
    let lfm = adapt_messages(Some(Format::Lfm), messages.clone(), Some(&request), &|_| {
        false
    });
    assert!(lfm[0].content.starts_with("Be brief.\nList of tools: [{"));
    assert_eq!(lfm[3], ChatMessage::new("tool", "1. Call Lee"));
    let plain = adapt_messages(None, messages, None, &|_| true);
    assert_eq!(
        plain
            .iter()
            .map(|m| (m.role.as_str(), m.content.as_str()))
            .collect::<Vec<_>>(),
        [
            ("system", "Be brief."),
            ("user", "What is open?"),
            ("assistant", "1. Call Lee"),
            ("user", "Thanks"),
        ]
    );
    assert!(plain.iter().all(|m| m.tool_calls.is_empty()));
}

#[test]
fn grammar_builds_for_every_format_and_quotes_only_source_spans() {
    let token = |text: &str| -> Option<i32> {
        Some(match text {
            "<|tool_call_start|>" | "<|tool_call>" | "<tool_call>" => 10,
            "<|tool_call_end|>" | "<tool_call|>" | "</tool_call>" => 11,
            "<|\"|>" => 12,
            _ => return None,
        })
    };
    for format in [Format::Lfm, Format::Gemma, Format::Qwen] {
        let grammar = grammar::grammar(format, &request("Call \"Lee\" tomorrow."), &token).unwrap();
        assert!(grammar.starts_with("root ::= <[10]>"), "{grammar}");
        assert!(
            grammar.contains("w2 ::= ") && !grammar.contains("w3 ::="),
            "{grammar}"
        );
        assert!(grammar.contains("{0,2}"), "{grammar}");
    }
    let empty = grammar::grammar(Format::Gemma, &request(""), &token).unwrap();
    assert!(!empty.contains("quote ::="));
    assert!(grammar::grammar(Format::Gemma, &request("x"), &|_| None).is_err());
}

#[test]
fn requests_are_validated() {
    let mut bad = request("x");
    bad.tools[1].name = "List".into();
    assert!(bad.validate().is_err());
    let mut bad = request("x");
    bad.min_call_probability = 1.5;
    assert!(bad.validate().is_err());
    let mut bad = request("x");
    bad.tools.push(bad.tools[0].clone());
    assert!(bad.validate().is_err());
    assert!(request("x").validate().is_ok());
}

/// Compiles every format's grammar against a real vocabulary and checks that
/// rendered calls are accepted token by token while ungrounded quotes are not.
/// Point `ENSU_TEST_TOOL_VOCAB` at any GGUF, including vocab-only files.
#[test]
#[ignore = "requires ENSU_TEST_TOOL_VOCAB"]
fn grammars_accept_rendered_calls_with_a_real_vocabulary() {
    use llama_cpp_2::model::{LlamaModel, params::LlamaModelParams};
    use llama_cpp_2::sampling::LlamaSampler;
    use llama_cpp_2::token::{data::LlamaTokenData, data_array::LlamaTokenDataArray};

    let model = LlamaModel::load_from_file(
        crate::llm::backend().unwrap(),
        std::env::var("ENSU_TEST_TOOL_VOCAB").unwrap(),
        &LlamaModelParams::default().with_vocab_only(true),
    )
    .unwrap();
    let accepts = |grammar: &str, text: &str| -> bool {
        let mut sampler = LlamaSampler::grammar(&model, grammar, "root").unwrap();
        let vocab = model.vocab();
        for token in vocab.tokenize(text.as_bytes(), false, true) {
            let mut one =
                LlamaTokenDataArray::new(vec![LlamaTokenData::new(token, 0.0, 0.0)], false);
            sampler.apply(&mut one);
            if !one.data[0].logit().is_finite() {
                return false;
            }
            sampler.accept(token);
        }
        let mut eos =
            LlamaTokenDataArray::new(vec![LlamaTokenData::new(vocab.eos(), 0.0, 0.0)], false);
        sampler.apply(&mut eos);
        eos.data[0].logit().is_finite()
    };
    let formats: Vec<_> = [Format::Lfm, Format::Gemma, Format::Qwen]
        .into_iter()
        .filter(|format| {
            format
                .required_tokens()
                .iter()
                .all(|t| single_token(&model, t).is_some())
        })
        .collect();
    assert!(
        !formats.is_empty(),
        "the vocabulary has no native tool tokens"
    );
    let request = request("Call \"Lee\" tomorrow at 4 PM");
    for format in formats {
        let grammar = super::grammar(format, &request, &model).unwrap();
        assert!(
            accepts(&grammar, &format.render_calls(&calls())),
            "{format:?}"
        );
        let mut ungrounded = calls();
        ungrounded[0]
            .arguments
            .insert("when".into(), ToolValue::Text("next week".into()));
        assert!(
            !accepts(&grammar, &format.render_calls(&ungrounded)),
            "{format:?}"
        );
        let mut unsorted = format.render_calls(&calls()[..1]);
        if format == Format::Gemma {
            unsorted = unsorted.replace(
                "title:<|\"|>Call \"Lee\"<|\"|>,when:<|\"|>tomorrow at 4 PM<|\"|>",
                "when:<|\"|>tomorrow at 4 PM<|\"|>,title:<|\"|>Call \"Lee\"<|\"|>",
            );
            assert!(!accepts(&grammar, &unsorted));
        }
    }
}
