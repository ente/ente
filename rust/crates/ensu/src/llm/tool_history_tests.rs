use super::*;
use crate::conversation::{ConversationState, Effects, PrepareError, TurnInput, prepare_turn};
use crate::db::ChatDb;
use crate::llm::{FinishReason, ToolCall, ToolOutcome, ToolValue};
use crate::todo::{LIST_TOOL, SAVE_TOOL};

struct NoGeneration;

impl Effects for NoGeneration {
    fn check_current(&mut self) -> Result<(), PrepareError> {
        Ok(())
    }

    fn measure(
        &mut self,
        messages: &[ChatMessage],
        _tools: Option<&ToolRequest>,
    ) -> Result<usize, PrepareError> {
        Ok(messages.iter().map(|message| message.content.len()).sum())
    }

    fn summarize(
        &mut self,
        _messages: Vec<ChatMessage>,
        _output: usize,
    ) -> Result<(String, FinishReason), PrepareError> {
        panic!("this short history should not need summarization")
    }

    fn checkpoint(&mut self, _state: &ConversationState) -> Result<(), PrepareError> {
        panic!("this short history should not need a checkpoint")
    }
}

#[test]
fn stored_multi_call_turns_render_each_gemma_response_with_its_own_call() {
    let call = |name: &str, key: &str, value: &str| ToolCall {
        name: name.into(),
        arguments: [(key.to_owned(), ToolValue::Text(value.into()))].into(),
    };
    let calls = vec![
        call(SAVE_TOOL, "title", "Buy milk"),
        call(LIST_TOOL, "filter", "open"),
        call(SAVE_TOOL, "title", "Buy tea"),
    ];
    for confidence in [1.0, 0.6] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("chat.db");
        let (session, reply, ids) = {
            let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
            let session = db.create_session("Tools").unwrap().uuid;
            let user = db
                .insert_message(
                    session,
                    "self",
                    "Buy milk, list my tasks, then buy tea",
                    None,
                    vec![],
                )
                .unwrap();
            let snapshot = db.conversation_snapshot(session, &[user.uuid]).unwrap();
            let reply = db
                .finish_reply(
                    &snapshot,
                    "",
                    vec![],
                    Some(&ToolOutcome {
                        calls: calls.clone(),
                        call_probability: Some(confidence),
                        ..Default::default()
                    }),
                )
                .unwrap()
                .message;
            let next = db
                .insert_message(session, "self", "Thanks", Some(reply.uuid), vec![])
                .unwrap();
            (session, reply.uuid, vec![user.uuid, reply.uuid, next.uuid])
        };
        let db = ChatDb::open_sqlite_with_defaults(&path, vec![7; 32]).unwrap();
        for stage in 0..3 {
            if stage == 1 && confidence < 0.9 {
                db.confirm_tool_turn(reply).unwrap();
            } else if stage == 2 {
                db.undo_tool_turn(reply).unwrap();
            }
            let snapshot = db.conversation_snapshot(session, &ids).unwrap();
            let tools = db.turn_tools(&snapshot, "Thanks").unwrap();
            let input = TurnInput {
                session,
                messages: snapshot.messages().to_vec(),
                expected_user_text: "Thanks".into(),
                system: "Be brief.".into(),
                current: "Thanks".into(),
                history_query: None,
                context: 8192,
                output: Some(512),
                state: None,
                candidates: crate::conversation::GroundingCandidates::new(vec![], vec![], 6000)
                    .unwrap(),
                tools,
            };
            let mut effects = NoGeneration;
            let mut prepared = prepare_turn(input, &mut effects).unwrap();
            let messages = prepared.preparation.run(&mut effects).unwrap().messages;
            let adapted = crate::llm::tools::adapt_messages(
                Some(Format::Gemma),
                messages,
                prepared.tools.as_ref(),
                &|_| true,
                &Specials::new([]),
            );
            let prompt = render_gemma("<bos>", &adapted, true);
            let mut suffix = String::new();
            if confidence < 0.9 {
                suffix.push_str(if stage == 0 {
                    "\n(The user hasn't confirmed these changes, so they weren't made.)"
                } else {
                    "\n(The user confirmed these changes.)"
                });
            }
            if stage == 2 {
                suffix.push_str("\n(The user undid these changes.)");
            }
            let results = if confidence < 0.9 {
                [
                    "Add “Buy milk” to your To Dos?",
                    "1. Buy milk — no due date",
                    "Add “Buy tea” to your To Dos?",
                ]
            } else {
                [
                    "Saved “Buy milk”.",
                    "1. Buy milk — no due date",
                    "Saved “Buy tea”.",
                ]
            };
            let expected: String = [SAVE_TOOL, LIST_TOOL, SAVE_TOOL]
                .into_iter()
                .zip(results)
                .map(|(name, result)| {
                    format!("<|tool_response>response:{name}{{value:<|\"|>{result}{suffix}<|\"|>}}<tool_response|>")
                })
                .collect();
            assert!(prompt.contains(&expected), "{prompt}");
            assert_eq!(prompt.matches("<|tool_response>").count(), 3);
            assert_eq!(
                adapted
                    .iter()
                    .filter(|message| message.role == "assistant")
                    .map(|message| message.content.matches("<|tool_call>call:").count())
                    .sum::<usize>(),
                3
            );
        }
    }
}

const FORMATS: [Format; 3] = [Format::Gemma, Format::Lfm, Format::Qwen];

fn render_for(format: Format, messages: &[ChatMessage], add: bool) -> String {
    match format {
        Format::Gemma => render_gemma("<bos>", messages, add),
        Format::Lfm => render_lfm("<bos>", messages, add),
        Format::Qwen => render_qwen(messages, add).unwrap(),
    }
}

struct Rendered {
    messages: Vec<ChatMessage>,
    tools: ToolRequest,
    system: String,
    stable: String,
    full: String,
}

impl Rendered {
    fn without_choices(&self, format: Format, add: bool) -> String {
        let mut tools = self.tools.clone();
        tools
            .tools
            .iter_mut()
            .find(|tool| tool.name == crate::todo::COMPLETE_TOOL)
            .unwrap()
            .parameters[0]
            .kind = crate::llm::ParameterKind::Quote;
        let adapted = crate::llm::tools::adapt_messages(
            Some(format),
            self.messages.clone(),
            Some(&tools),
            &|_| true,
            &Specials::new([]),
        );
        render_for(format, &adapted, add)
    }
}

fn turn(
    db: &ChatDb<crate::db::SqliteBackend>,
    session: uuid::Uuid,
    path: &[uuid::Uuid],
    user: &str,
    format: Format,
) -> Rendered {
    let snapshot = db.conversation_snapshot(session, path).unwrap();
    let mut effects = NoGeneration;
    let mut prepared = prepare_turn(
        TurnInput {
            session,
            messages: snapshot.messages().to_vec(),
            expected_user_text: user.into(),
            system: "Be brief.".into(),
            current: user.into(),
            history_query: None,
            context: 4096,
            output: Some(128),
            state: None,
            candidates: crate::conversation::GroundingCandidates::new(vec![], vec![], 0).unwrap(),
            tools: db.turn_tools(&snapshot, user).unwrap(),
        },
        &mut effects,
    )
    .unwrap();
    let messages = prepared.preparation.run(&mut effects).unwrap().messages;
    let tools = prepared.tools.unwrap();
    let adapted = crate::llm::tools::adapt_messages(
        Some(format),
        messages.clone(),
        Some(&tools),
        &|_| true,
        &Specials::new([]),
    );
    Rendered {
        messages,
        tools,
        system: adapted[0].content.clone(),
        stable: render_for(format, &adapted, false),
        full: render_for(format, &adapted, true),
    }
}

fn common(a: &str, b: &str) -> usize {
    a.bytes().zip(b.bytes()).take_while(|(a, b)| a == b).count()
}

fn prompt_pair(
    format: Format,
    first: &str,
    next: &str,
    before: &[&str],
    add: Option<&str>,
    undo: Option<bool>,
) -> (Rendered, Rendered) {
    let db = ChatDb::open_in_memory(vec![7; 32]).unwrap();
    for title in before {
        db.create_todo(title, None).unwrap();
    }
    let session = db.create_session("Tools").unwrap().uuid;
    let user = db
        .insert_message(session, "self", first, None, vec![])
        .unwrap();
    let prev = turn(&db, session, &[user.uuid], first, format);
    let snapshot = db.conversation_snapshot(session, &[user.uuid]).unwrap();
    let outcome = undo.map(|_| ToolOutcome {
        calls: vec![ToolCall {
            name: SAVE_TOOL.into(),
            arguments: [("title".to_owned(), ToolValue::Text("Buy milk".into()))].into(),
        }],
        call_probability: Some(1.0),
        ..Default::default()
    });
    let reply = db
        .finish_reply(&snapshot, "Hello.", vec![], outcome.as_ref())
        .unwrap()
        .message;
    if undo == Some(true) {
        db.undo_tool_turn(reply.uuid).unwrap();
    }
    if let Some(title) = add {
        db.create_todo(title, None).unwrap();
    }
    let next_user = db
        .insert_message(session, "self", next, Some(reply.uuid), vec![])
        .unwrap();
    let next = turn(
        &db,
        session,
        &[user.uuid, reply.uuid, next_user.uuid],
        next,
        format,
    );
    (prev, next)
}

#[test]
fn a_plain_follow_up_extends_the_previous_prompt() {
    for format in FORMATS {
        let (prev, next) = prompt_pair(format, "Hi", "Thanks", &[], None, None);
        assert!(next.full.starts_with(&prev.stable), "{format:?}");
        if format == Format::Qwen {
            assert_eq!(
                common(&prev.full, &next.full),
                prev.stable.len() + "<|im_start|>assistant\n".len()
            );
        } else {
            assert!(next.full.starts_with(&prev.full), "{format:?}");
        }
    }
}

#[test]
fn naming_a_task_leaves_the_system_message_unchanged() {
    for format in FORMATS {
        let (prev, next) = prompt_pair(
            format,
            "Hi",
            "What do I need to renew my passport?",
            &["Buy tea", "Renew passport"],
            None,
            None,
        );
        assert_eq!(prev.system, next.system, "{format:?}");
    }
}

#[test]
fn adding_a_task_changes_only_the_task_choices() {
    for format in FORMATS {
        for before in [&[][..], &["Buy tea"][..]] {
            let (prev, next) = prompt_pair(format, "Hi", "Thanks", before, Some("Buy milk"), None);
            let marker = if format == Format::Gemma {
                "declaration:complete_to_do{"
            } else {
                "\"name\":\"complete_to_do\""
            };
            assert!(
                common(&prev.full, &next.full) >= next.full.find(marker).unwrap(),
                "{format:?}"
            );
            assert!(
                next.without_choices(format, true)
                    .starts_with(&prev.without_choices(format, false)),
                "{format:?}"
            );
        }
    }
}

#[test]
fn try_again_extends_the_previous_prompt() {
    for format in FORMATS {
        let (prev, next) = prompt_pair(format, "Add buy milk", "Try again", &[], None, Some(true));
        assert_eq!(prev.system, next.system, "{format:?}");
        assert!(next.full.starts_with(&prev.stable), "{format:?}");
        let (prev, next) = prompt_pair(format, "Add buy milk", "Try again", &[], None, Some(false));
        assert_eq!(next.tools.allowed, Some(vec![]));
        assert!(
            next.without_choices(format, true)
                .starts_with(&prev.without_choices(format, false))
        );
    }
}

#[test]
fn the_follow_up_pass_extends_the_first_pass() {
    let user = "List my tasks and add buy tea.";
    let db = ChatDb::open_in_memory(vec![7; 32]).unwrap();
    db.create_todo("Buy milk", None).unwrap();
    let tools = crate::todo::chat_tools(user, &["Buy milk"]);
    let first = crate::llm::ChatRequest {
        messages: vec![
            ChatMessage::new("system", "Be brief."),
            ChatMessage::new("user", user),
        ],
        tools: Some(tools),
        ..Default::default()
    };
    let outcome = ToolOutcome {
        calls: vec![ToolCall {
            name: LIST_TOOL.into(),
            arguments: Default::default(),
        }],
        call_probability: Some(1.0),
        ..Default::default()
    };
    let follow_up =
        crate::todo::follow_up::FollowUp::new(db.list_todos().unwrap(), db.now_ms(), user.into());
    let second = follow_up.next(&first, &outcome).unwrap();
    for format in FORMATS {
        let first_prompt =
            crate::llm::render_native(format, first.messages.clone(), first.tools.as_ref());
        let prefix = first_prompt + &format.render_calls(&outcome.calls);
        let second_prompt =
            crate::llm::render_native(format, second.messages.clone(), second.tools.as_ref());
        let suffix = second_prompt.strip_prefix(&prefix).unwrap();
        assert!(suffix.contains("1. Buy milk") && suffix.contains("The listing is complete."));
    }
}
