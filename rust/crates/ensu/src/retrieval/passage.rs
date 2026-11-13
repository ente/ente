use serde::{Deserialize, Serialize};

use crate::notes::NotePassageLocator;

use super::{BEGIN_CONTEXT_SENTINEL, END_CONTEXT_SENTINEL, GroundedSource, RetrievalError};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum PassageLocator {
    EnsuPack {
        dataset_id: String,
        revision_sha256: String,
        row: u64,
    },
    LocalNote(NotePassageLocator),
}

impl PassageLocator {
    pub(crate) fn matches_source(&self, source: &GroundedSource) -> bool {
        match (self, source) {
            (Self::EnsuPack { dataset_id, .. }, GroundedSource::EnsuPack { citation }) => {
                *dataset_id == citation.dataset_id
            }
            (Self::LocalNote(locator), GroundedSource::LocalNote { reference }) => {
                locator.collection_id == reference.collection_id
                    && locator.document_id == reference.document_id
                    && locator.indexed_revision == reference.indexed_revision
            }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PassageSpan {
    pub start_utf8: u32,
    pub end_utf8: u32,
    pub text_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IncludedPassage {
    pub locator: PassageLocator,
    pub cleaning_version: u32,
    pub spans: Vec<PassageSpan>,
}

const PASSAGE_CLEANING_VERSION: u32 = 1;
const MAX_PASSAGE_SPANS: usize = 8;
const MAX_PASSAGE_UTF8_BYTES: usize = 64 * 1024;

impl IncludedPassage {
    pub(crate) fn valid_metadata(&self) -> bool {
        let sha = |value: &str| {
            value.len() == 64
                && value
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        };
        if self.cleaning_version != PASSAGE_CLEANING_VERSION
            || self.spans.is_empty()
            || self.spans.len() > MAX_PASSAGE_SPANS
        {
            return false;
        }
        let valid_locator = match &self.locator {
            PassageLocator::EnsuPack {
                dataset_id,
                revision_sha256,
                ..
            } => !dataset_id.is_empty() && dataset_id.len() <= 256 && sha(revision_sha256),
            PassageLocator::LocalNote(locator) => {
                uuid::Uuid::parse_str(&locator.collection_id).is_ok()
                    && crate::notes::validate_document_id(&locator.document_id).is_ok()
                    && sha(&locator.indexed_revision)
                    && sha(&locator.shard_sha256)
            }
        };
        valid_locator
            && self.spans.iter().all(|span| {
                span.start_utf8 < span.end_utf8
                    && span.end_utf8 as usize <= MAX_PASSAGE_UTF8_BYTES
                    && sha(&span.text_sha256)
            })
            && self
                .spans
                .windows(2)
                .all(|pair| pair[0].end_utf8 <= pair[1].start_utf8)
    }

    pub(crate) fn prefix(locator: PassageLocator, text: &str) -> Result<Self, RetrievalError> {
        let end_utf8 = u32::try_from(text.len()).map_err(|_| {
            RetrievalError::InvalidInput("included passage is too large".to_string())
        })?;
        Ok(Self {
            locator,
            cleaning_version: PASSAGE_CLEANING_VERSION,
            spans: vec![PassageSpan {
                start_utf8: 0,
                end_utf8,
                text_sha256: digest(text.as_bytes()),
            }],
        })
    }

    pub fn verified_spans(&self, reloaded_text: &str) -> Option<Vec<String>> {
        if !self.valid_metadata() || reloaded_text.len() > MAX_PASSAGE_UTF8_BYTES {
            return None;
        }
        let cleaned = clean_passage_text(reloaded_text);
        self.spans
            .iter()
            .map(|span| {
                let text = cleaned.get(span.start_utf8 as usize..span.end_utf8 as usize)?;
                (digest(text.as_bytes()) == span.text_sha256).then(|| text.to_owned())
            })
            .collect()
    }
}

pub(super) fn digest(bytes: &[u8]) -> String {
    ente_ensu_crypto::sha256(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

pub(crate) fn clean_passage_text(value: &str) -> String {
    value
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .lines()
        .map(|line| {
            let line = line
                .chars()
                .map(|character| {
                    if character == '\t' || !character.is_control() {
                        character
                    } else {
                        ' '
                    }
                })
                .collect::<String>();
            let start = line.trim_start();
            if start.starts_with(BEGIN_CONTEXT_SENTINEL) || start.starts_with(END_CONTEXT_SENTINEL)
            {
                format!("[source] {line}")
            } else {
                line
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned()
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;

    pub(crate) fn passage_fixture() -> (IncludedPassage, &'static str) {
        let reference = IncludedPassage {
            locator: PassageLocator::LocalNote(NotePassageLocator {
                collection_id: "123e4567-e89b-12d3-a456-426614174000".into(),
                document_id: "trip.md".into(),
                indexed_revision: "a".repeat(64),
                shard_sha256: "b".repeat(64),
                chunk_index: 2,
            }),
            cleaning_version: PASSAGE_CLEANING_VERSION,
            spans: vec![
                PassageSpan {
                    start_utf8: 0,
                    end_utf8: 9,
                    text_sha256: "894473efc373309a7c6d18cbe8504c8bb91e09cba4e1ab147ff97af12d481702"
                        .into(),
                },
                PassageSpan {
                    start_utf8: 20,
                    end_utf8: 23,
                    text_sha256: "361e48d0308f20e32dba5fb56328baf18d72ef0ccb43b84f5c262d2a6a1fc6c8"
                        .into(),
                },
            ],
        };
        (reference, " \r\nCafé🙂\r\nबीच\tend \0\r\n")
    }

    #[test]
    fn passage_references_verify_cleaned_text_and_reject_invalid_spans() {
        let (fixture, raw) = passage_fixture();
        assert_eq!(clean_passage_text(raw), "Café🙂\nबीच\tend");
        assert_eq!(fixture.verified_spans(raw).unwrap(), ["Café🙂", "end"]);
        assert!(
            fixture
                .verified_spans(&raw.replace("Café", "Cafe "))
                .is_none()
        );
        for (case, start, end) in [
            ("end splits UTF-8", 0, 4),
            ("start splits UTF-8", 4, 9),
            ("reversed range", 9, 0),
            ("oversized range", 0, u32::MAX),
        ] {
            let mut reference = fixture.clone();
            reference.spans[0].start_utf8 = start;
            reference.spans[0].end_utf8 = end;
            assert!(reference.verified_spans(raw).is_none(), "{case}");
        }
        let mut reference = fixture.clone();
        reference.cleaning_version = 2;
        assert!(reference.verified_spans(raw).is_none(), "cleaning version");
        reference = fixture;
        reference.spans[1] = reference.spans[0].clone();
        assert!(reference.verified_spans(raw).is_none(), "overlapping spans");
        reference.spans = (0..9)
            .map(|start_utf8| PassageSpan {
                start_utf8,
                end_utf8: start_utf8 + 1,
                text_sha256: "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
                    .into(),
            })
            .collect();
        assert!(
            reference.verified_spans("aaaaaaaaa").is_none(),
            "span limit"
        );
    }
}
