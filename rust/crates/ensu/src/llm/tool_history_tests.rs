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
