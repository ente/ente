use super::*;
use crate::db::{self, AttachmentMeta, Backend, ChatDb, chat::ConversationSnapshot};
use crate::retrieval::GroundedPromptContext;
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
    pub fn prepare_turn(
        &self,
        input: TurnInput,
        effects: &mut impl Effects,
    ) -> Result<PreparedTurn, PrepareError> {
        let anchor = self.anchor.lock().ok().and_then(|anchor| anchor.clone());
        super::turn::prepare_turn_with_anchor(input, anchor, effects)
    }

    pub fn save_answer<B: Backend>(
        &self,
        db: &ChatDb<B>,
        snapshot: &ConversationSnapshot,
        prepared: &mut PreparationResult,
        text: &str,
        attachments: Vec<AttachmentMeta>,
    ) -> db::Result<Message> {
        if prepared.is_saved() {
            return Err(db::Error::UnsupportedOperation(
                "Answer already saved".into(),
            ));
        }
        let answer = db.insert_message_guarded(
            snapshot.session_uuid(),
            "other",
            text,
            snapshot.messages().last().map(|message| message.uuid),
            attachments,
            Some(snapshot),
        )?;
        prepared.saved = true;
        if let Ok(mut anchor) = self.anchor.lock() {
            *anchor = prepared.grounding_anchor.take();
        }
        Ok(answer)
    }
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
