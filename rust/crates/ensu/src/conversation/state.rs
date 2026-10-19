use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::{ConversationState, MAX_STATE_BYTES, Summary, fingerprint, validate_summary_text};
use crate::db::{Message, Sender};
use crate::retrieval::IncludedPassage;

pub const ENVELOPE_VERSION: u32 = 2;
pub(super) const MAX_EVIDENCE_ANSWERS: usize = 8;
pub(super) const MAX_EVIDENCE_BYTES: usize = 12 * 1024;
pub(super) use crate::retrieval::MAX_GROUNDING_HITS as MAX_ANSWER_PASSAGES;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnswerEvidence {
    #[serde(with = "super::uuid_text")]
    pub assistant_message_uuid: Uuid,
    pub prefix_fingerprint: String,
    pub passages: Vec<IncludedPassage>,
}

impl AnswerEvidence {
    pub(crate) fn matches(&self, history: &[Message]) -> bool {
        history
            .iter()
            .position(|m| m.uuid == self.assistant_message_uuid)
            .is_some_and(|index| {
                history[index].sender == Sender::Other
                    && fingerprint(&history[..=index]) == self.prefix_fingerprint
            })
    }
}

pub(crate) fn valid_answer_passages(passages: &[IncludedPassage]) -> bool {
    !passages.is_empty()
        && passages.len() <= MAX_ANSWER_PASSAGES
        && passages.iter().all(IncludedPassage::valid_metadata)
        && serde_json::to_vec(passages).is_ok_and(|bytes| bytes.len() <= MAX_EVIDENCE_BYTES)
}

#[derive(Debug, Clone, Serialize)]
pub struct ConversationEnvelope {
    pub format_version: u32,
    #[serde(serialize_with = "super::uuid_text::serialize")]
    pub session_uuid: Uuid,
    pub summary: Option<Summary>,
    pub evidence: Vec<AnswerEvidence>,
}

impl ConversationEnvelope {
    pub fn empty(session: Uuid) -> Self {
        Self {
            format_version: ENVELOPE_VERSION,
            session_uuid: session,
            summary: None,
            evidence: Vec::new(),
        }
    }

    pub fn decode(bytes: &[u8], session: Uuid) -> Option<Self> {
        if bytes.len() > MAX_STATE_BYTES {
            return None;
        }
        let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
        let version = value.get("format_version")?.as_u64()?;
        if version != u64::from(ENVELOPE_VERSION)
            || value.get("session_uuid")?.as_str()? != session.to_string()
        {
            return None;
        }
        let summary = value
            .get("summary")
            .cloned()
            .and_then(|value| serde_json::from_value::<Summary>(value).ok())
            .filter(|summary| validate_summary_text(&summary.text).is_ok());
        let mut evidence: Vec<AnswerEvidence> = Vec::new();
        if let Some(entries) = value.get("evidence").and_then(|value| value.as_array())
            && entries.len() <= MAX_EVIDENCE_ANSWERS
        {
            for value in entries {
                if let Ok(entry) = serde_json::from_value::<AnswerEvidence>(value.clone())
                    && entry.prefix_fingerprint.len() == 64
                    && valid_answer_passages(&entry.passages)
                    && !evidence
                        .iter()
                        .any(|old| old.assistant_message_uuid == entry.assistant_message_uuid)
                {
                    evidence.push(entry);
                }
            }
        }
        if serde_json::to_vec(&evidence).ok()?.len() > MAX_EVIDENCE_BYTES {
            evidence.clear();
        }
        Some(Self {
            format_version: ENVELOPE_VERSION,
            session_uuid: session,
            summary,
            evidence,
        })
    }

    pub fn summary_state(&self) -> Option<ConversationState> {
        self.summary.clone().map(|summary| ConversationState {
            session_uuid: self.session_uuid,
            summary,
        })
    }

    pub fn add_evidence(&mut self, history: &[Message], passages: Vec<IncludedPassage>) -> bool {
        let Some(answer) = history.last() else {
            return false;
        };
        if history.len() < 2
            || answer.sender != Sender::Other
            || answer.session_uuid != self.session_uuid
            || !valid_answer_passages(&passages)
            || super::validate_path(history).is_err()
        {
            return false;
        }
        self.evidence
            .retain(|entry| entry.assistant_message_uuid != answer.uuid);
        self.evidence.push(AnswerEvidence {
            assistant_message_uuid: answer.uuid,
            prefix_fingerprint: fingerprint(history),
            passages,
        });
        while self.evidence.len() > MAX_EVIDENCE_ANSWERS
            || serde_json::to_vec(&self.evidence)
                .map_or(true, |bytes| bytes.len() > MAX_EVIDENCE_BYTES)
        {
            self.evidence.remove(0);
        }
        self.evidence
            .last()
            .is_some_and(|entry| entry.assistant_message_uuid == answer.uuid)
    }
}
