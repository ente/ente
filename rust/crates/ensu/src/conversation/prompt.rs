use super::*;
use crate::db::{self, AttachmentMeta, Backend, ChatDb, chat::ConversationSnapshot};
use crate::retrieval::{
    GroundedPromptContext, GroundedSource, IncludedPassage, RetrievalError,
    finalize_grounded_assistant_text,
};
use std::sync::Mutex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct GroundingAnchor {
    message_uuid: Uuid,
    prefix_fingerprint: String,
    evidence_fingerprint: [u8; 32],
}

#[derive(Default)]
pub struct GroundingCache {
    anchor: Mutex<Option<GroundingAnchor>>,
}

impl GroundingCache {
    pub(crate) fn prepare_turn(
        &self,
        input: TurnInput,
        effects: &mut impl Effects,
    ) -> Result<PreparedTurn, PrepareError> {
        let anchor = self.anchor.lock().ok().and_then(|anchor| anchor.clone());
        super::turn::prepare_turn_with_anchor(input, anchor, effects)
    }
}

#[derive(Debug)]
pub enum FinishWarning {
    SourcesDropped(RetrievalError),
    EvidenceNotRetained,
    EvidenceFailed(db::Error),
}

impl std::fmt::Display for FinishWarning {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::SourcesDropped(cause) => write!(f, "Reply saved without sources: {cause}"),
            Self::EvidenceNotRetained => {
                f.write_str("Reply saved, but its source references could not be retained")
            }
            Self::EvidenceFailed(cause) => write!(
                f,
                "Reply saved but source reference persistence failed: {cause}"
            ),
        }
    }
}

#[derive(Debug)]
pub struct FinishedTurn {
    pub reply: db::chat::FinishedReply,
    pub warnings: Vec<FinishWarning>,
}

pub(super) struct Answer<'a> {
    pub text: &'a str,
    pub sources: &'a [GroundedSource],
    pub passages: Vec<IncludedPassage>,
    pub attachments: Vec<AttachmentMeta>,
    pub outcome: Option<&'a crate::llm::ToolOutcome>,
}

pub(super) fn save_prepared_reply<B: Backend>(
    cache: Option<&GroundingCache>,
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    prepared: &mut PreparationResult,
    reply: Answer<'_>,
    can_finish: &dyn Fn(&crate::llm::ToolOutcome, i64) -> bool,
) -> db::Result<FinishedTurn> {
    if prepared.is_saved() {
        return Err(db::Error::UnsupportedOperation(
            "Answer already saved".into(),
        ));
    }
    let finished = save_reply(db, snapshot, reply, can_finish)?;
    prepared.saved = true;
    if finished.reply.tool_turn.is_none()
        && let Some(cache) = cache
        && let Ok(mut anchor) = cache.anchor.lock()
    {
        *anchor = prepared.grounding_anchor.take();
    }
    Ok(finished)
}

fn save_reply<B: Backend>(
    db: &ChatDb<B>,
    snapshot: &ConversationSnapshot,
    reply: Answer<'_>,
    can_finish: &dyn Fn(&crate::llm::ToolOutcome, i64) -> bool,
) -> db::Result<FinishedTurn> {
    let mut warnings = Vec::new();
    let text = if reply.outcome.is_some_and(|outcome| {
        outcome
            .calls
            .iter()
            .any(|call| call.name != crate::todo::LIST_TOOL)
    }) {
        String::new()
    } else {
        match finalize_grounded_assistant_text(reply.text, reply.sources) {
            Ok(text) => text,
            Err(cause) => {
                let plain = finalize_grounded_assistant_text(reply.text, &[])
                    .map_err(|error| db::Error::UnsupportedOperation(error.to_string()))?;
                warnings.push(FinishWarning::SourcesDropped(cause));
                plain
            }
        }
    };
    let finished = db.finish_reply_inner(
        snapshot,
        &text,
        reply.attachments,
        reply.outcome,
        can_finish,
    )?;
    if finished.tool_turn.is_none() && !reply.passages.is_empty() {
        match db.save_answer_evidence(snapshot, finished.message.uuid, reply.passages) {
            Ok(true) => {}
            Ok(false) => warnings.push(FinishWarning::EvidenceNotRetained),
            Err(error) => warnings.push(FinishWarning::EvidenceFailed(error)),
        }
    }
    Ok(FinishedTurn {
        reply: finished,
        warnings,
    })
}

pub(super) struct PromptGrounding {
    text: String,
    previous: Option<GroundingAnchor>,
    current: GroundingAnchor,
}

impl PromptGrounding {
    pub(super) fn new(
        context: &GroundedPromptContext,
        previous: Option<GroundingAnchor>,
        history: &[Message],
    ) -> Result<Self, PrepareError> {
        let current = history.last().ok_or(Error::InvalidHistory)?;
        let evidence_fingerprint = ente_ensu_crypto::sha256(
            &serde_json::to_vec(context)
                .map_err(|error| PrepareError::Backend(error.to_string()))?,
        );
        let previous = previous.filter(|anchor| {
            anchor.evidence_fingerprint == evidence_fingerprint
                && history
                    .iter()
                    .position(|message| {
                        message.uuid == anchor.message_uuid && message.sender == Sender::SelfUser
                    })
                    .is_some_and(|index| {
                        fingerprint(&history[..=index]) == anchor.prefix_fingerprint
                    })
        });
        Ok(Self {
            text: context.text.clone(),
            previous,
            current: GroundingAnchor {
                message_uuid: current.uuid,
                prefix_fingerprint: fingerprint(history),
                evidence_fingerprint,
            },
        })
    }

    fn target<'a>(&'a self, tail: &[Message]) -> (usize, &'a GroundingAnchor) {
        if let Some(anchor) = &self.previous
            && let Some(index) = tail
                .iter()
                .position(|message| message.uuid == anchor.message_uuid)
        {
            (index + 1, anchor)
        } else {
            (tail.len() + 1, &self.current)
        }
    }

    pub(super) fn apply(&self, tail: &[Message], messages: &mut [ChatMessage]) {
        let (index, _) = self.target(tail);
        messages[index].content = format!("{}\n\n{}", self.text, messages[index].content);
    }

    pub(super) fn anchor(&self, tail: &[Message]) -> GroundingAnchor {
        self.target(tail).1.clone()
    }
}
