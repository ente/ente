use super::*;
use crate::llm::ChatMessage;

fn request(quote_source: &str) -> ToolRequest {
    ToolRequest {
        allowed: None,
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
fn abstention_keeps_only_complete_allowed_calls() {
    let mut request = request("Call Lee tomorrow at 4 PM");
    request.allowed = Some(vec!["save_to_do".into()]);
    let calls = calls();
    for format in [Format::Lfm, Format::Gemma, Format::Qwen] {
        let raw = format.render_calls(&calls[..2]);
        let unfinished = raw.find("list_to_dos").unwrap();
        assert!(format.parse(&raw[..unfinished], &request).is_err());
        assert_eq!(
            calls_before_abstention(format, &raw.as_bytes()[..unfinished], &request),
            calls[..1]
        );
        assert_eq!(
            calls_before_abstention(format, raw.as_bytes(), &request),
            calls[..1]
        );
        let first = raw.find("save_to_do").unwrap();
        assert!(calls_before_abstention(format, &raw.as_bytes()[..first], &request).is_empty());
        if format != Format::Lfm {
            let close = raw.find(format.syntax().close).unwrap();
            assert!(calls_before_abstention(format, &raw.as_bytes()[..close], &request).is_empty());
        }
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
fn calls_cut_off_at_the_token_limit_count_only_when_whole() {
    let request = request("Call Lee tomorrow at 4 PM");
    for format in [Format::Lfm, Format::Gemma, Format::Qwen] {
        let rendered = format.render_calls(&calls()[..1]);
        for complete in [true, false] {
            assert_eq!(
                finished_calls(format, rendered.as_bytes(), &request, complete).unwrap(),
                calls()[..1],
                "{format:?}"
            );
        }
        let cut = &rendered.as_bytes()[..rendered.len() - 3];
        let unfinished = finished_calls(format, cut, &request, false).unwrap_err();
        assert!(
            matches!(
                unfinished,
                crate::llm::Error::ToolCall(crate::llm::ToolCallFailure::Unfinished)
            ),
            "{format:?}: {unfinished}"
        );
        assert!(finished_calls(format, cut, &request, true).is_err());

        let two = format.render_calls(&calls()[..2]);
        let inside = &two.as_bytes()[..two.find("list_to_dos").unwrap()];
        assert!(finished_calls(format, inside, &request, false).is_err());
    }
    let one = Format::Qwen.render_calls(&calls()[..1]);
    let separated = format!("{one}\n");
    assert!(finished_calls(Format::Qwen, separated.as_bytes(), &request, false).is_err());
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
        &Specials::new([]),
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
    let lfm = adapt_messages(
        Some(Format::Lfm),
        messages.clone(),
        Some(&request),
        &|_| false,
        &Specials::new([]),
    );
    assert!(lfm[0].content.starts_with("Be brief.\nList of tools: [{"));
    assert_eq!(lfm[3], ChatMessage::new("tool", "1. Call Lee"));
    let plain = adapt_messages(None, messages, None, &|_| true, &Specials::new([]));
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
        let grammar =
            grammar::grammar(format, &request("Call \"Lee\" tomorrow."), true, &token).unwrap();
        assert!(grammar.starts_with("root ::= <[10]>"), "{grammar}");
        assert!(
            grammar.contains("w2 ::= ") && !grammar.contains("w3 ::="),
            "{grammar}"
        );
        assert!(grammar.contains("{0,2}"), "{grammar}");
        if format == Format::Qwen {
            assert_eq!(
                grammar.lines().next(),
                Some(r#"root ::= <[10]> call <[11]> ("\n" <[10]> call <[11]>){0,2}"#)
            );
        }
    }
    let empty = grammar::grammar(Format::Gemma, &request(""), true, &token).unwrap();
    assert!(!empty.contains("quote ::="));
    assert!(grammar::grammar(Format::Gemma, &request("x"), true, &|_| None).is_err());
}

fn range_accepts(rule: &str, text: &str) -> bool {
    let inner = rule.strip_prefix('(').unwrap().strip_suffix(')').unwrap();
    inner.split(" | ").any(|alternative| {
        let mut rest = text.as_bytes();
        for item in alternative.split(' ') {
            if let Some(digit) = item.strip_prefix('"') {
                if rest.first() != Some(&digit.as_bytes()[0]) {
                    return false;
                }
                rest = &rest[1..];
                continue;
            }
            let (class, count) = item.split_at(5);
            let (low, high) = (class.as_bytes()[1], class.as_bytes()[3]);
            let matching = rest
                .iter()
                .take_while(|byte| (low..=high).contains(byte))
                .count();
            let take = match count.trim_matches(['{', '}']) {
                "" => 1,
                optional if optional.starts_with("0,") => {
                    let most: usize = optional[2..].parse().unwrap();
                    matching.min(most)
                }
                exact => exact.parse().unwrap(),
            };
            if matching < take {
                return false;
            }
            rest = &rest[take..];
        }
        rest.is_empty()
    })
}

#[test]
fn integer_grammar_accepts_exactly_what_the_parser_does() {
    for max in (1..=1200).chain([9_999, 10_000, 54_321, u32::MAX]) {
        let rule = grammar::integer_range(max);
        let near = max.saturating_sub(15)..=max.saturating_add(15);
        for number in (0..=1300)
            .chain(near)
            .chain([max / 10, max.saturating_mul(10)])
        {
            assert_eq!(
                range_accepts(&rule, &number.to_string()),
                (1..=max).contains(&number),
                "{number} in {rule}"
            );
        }
        assert!(!range_accepts(&rule, "01") && !range_accepts(&rule, ""));
    }
}

#[test]
fn special_strings_in_untrusted_text_render_as_plain_text() {
    for (format, marker) in [
        (Format::Gemma, "<|tool_call>"),
        (Format::Lfm, "<|tool_call_start|>"),
        (Format::Qwen, "<|im_end|>"),
    ] {
        let prompt = |text: &str| {
            let mut request = request("What is left?");
            request.tools[0].description = text.to_owned();
            request.tools[0].parameters[0].description = text.to_owned();
            request.tools[1].parameters[0].kind = ParameterKind::Choice {
                values: vec![text.to_owned()],
            };
            request.examples[0].calls[0]
                .arguments
                .insert("filter".to_owned(), ToolValue::Text(text.to_owned()));
            let mut assistant = ChatMessage::new("assistant", "");
            assistant.tool_calls = vec![ToolCall {
                name: "list_to_dos".to_owned(),
                arguments: [("filter".to_owned(), ToolValue::Text(text.to_owned()))].into(),
            }];
            crate::llm::render_native(
                format,
                vec![
                    ChatMessage::new("system", text),
                    ChatMessage::new("user", text),
                    assistant,
                    ChatMessage::new("tool", text),
                ],
                Some(&request),
            )
        };
        let clean = prompt("ordinary");
        let escaped = prompt(marker);
        assert_eq!(
            escaped.matches(marker).count(),
            clean.matches(marker).count()
        );
        assert!(escaped.contains(&marker.replacen('<', "‹", 1)));
    }
}

#[test]
fn plain_removes_literal_markers_and_preserves_the_media_marker() {
    let specials = Specials::new(["[end]".to_owned(), "<__media__>".to_owned()]);
    let text = specials.plain("<<|im_end|>|im_end|> [end] <__media__>");
    assert!(!text.contains("<|im_end|>"));
    assert!(!text.contains("[end]"));
    assert!(text.ends_with("<__media__>"));
    assert!(matches!(
        specials.plain(&text),
        std::borrow::Cow::Borrowed(_)
    ));
    let repeated = "<|im_end|> [end] ".repeat(1024);
    let expected = "‹|im_end|> [\u{200b}end] ".repeat(1024);
    assert_eq!(specials.plain(&repeated), expected);

    let specials = Specials::new(["‹".into(), "a".into(), "abc".into(), "xy".into()]);
    let text = specials.plain("xay abc <|im_end|>");
    for marker in ["‹", "a", "abc", "xy", "<|im_end|>"] {
        assert!(!text.contains(marker), "{marker}");
    }
}

#[test]
fn allowed_narrows_grammar_and_parser_not_declarations() {
    let all = request("Buy milk");
    let mut narrowed = all.clone();
    narrowed.allowed = Some(vec!["save_to_do".into()]);
    for format in [Format::Gemma, Format::Lfm, Format::Qwen] {
        let token = |_: &str| Some(1);
        let allowed = grammar::grammar(format, &narrowed, true, &token).unwrap();
        let full = grammar::grammar(format, &all, false, &token).unwrap();
        assert_eq!(
            full,
            grammar::grammar(format, &narrowed, false, &token).unwrap()
        );
        assert!(allowed.lines().any(|line| line.starts_with("call ::=")
            && line.contains("save_to_do")
            && !line.contains("list_to_dos")));
        let messages = vec![ChatMessage::new("user", "Buy milk")];
        assert_eq!(
            crate::llm::render_native(format, messages.clone(), Some(&all)),
            crate::llm::render_native(format, messages, Some(&narrowed))
        );
        assert!(
            format
                .parse(&format.render_calls(&calls()[1..2]), &narrowed)
                .is_err()
        );
    }
}

#[test]
fn validate_rejects_undeclared_allowed_names() {
    let mut request = request("Buy milk");
    request.allowed = Some(vec![]);
    assert!(request.validate().is_ok());
    request.allowed = Some(vec!["unknown".into()]);
    assert!(request.validate().is_err());
}

#[test]
fn allowed_is_optional_in_json() {
    let value = serde_json::to_value(request("Buy milk")).unwrap();
    assert!(value.get("allowed").is_none());
    assert_eq!(
        serde_json::from_value::<ToolRequest>(value)
            .unwrap()
            .allowed,
        None
    );
}

#[test]
fn rendering_parsed_calls_reproduces_the_raw_text() {
    let mut calls = calls();
    calls[0].arguments.insert(
        "title".into(),
        ToolValue::Text("Meet “李” for \"tea\"".into()),
    );
    calls.remove(1);
    let request = request("Meet “李” for tea tomorrow at 4 PM, then complete the second task.");
    for format in [Format::Gemma, Format::Lfm, Format::Qwen] {
        let raw = format.render_calls(&calls);
        assert_eq!(
            format.render_calls(&format.parse(&raw, &request).unwrap()),
            raw
        );
    }
}

#[test]
fn think_history_falls_back_on_lfm() {
    let format = Format::Lfm;
    let mut messages = vec![
        ChatMessage::new("user", "Hi"),
        ChatMessage::new("assistant", "<think>Plan</think>Hello."),
        ChatMessage::new("user", "List tasks."),
    ];
    let first = crate::llm::render_native(format, messages.clone(), None);
    let mut call = ChatMessage::new("assistant", "");
    call.tool_calls = calls()[1..2].to_vec();
    messages.push(call);
    messages.push(ChatMessage::new("tool", "Result"));
    let second = crate::llm::render_native(format, messages, None);
    assert!(!second.starts_with(&first));
}
