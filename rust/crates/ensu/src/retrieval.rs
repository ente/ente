mod citation;
mod index;
mod pack;
mod prompt;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum RetrievalError {
    #[error("invalid retrieval input: {0}")]
    InvalidInput(String),
    #[error("invalid knowledge pack: {0}")]
    InvalidPack(String),
    #[error("knowledge pack I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("knowledge pack JSON failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("knowledge pack metadata decompression failed: {0}")]
    Zstd(String),
}

fn normalize_single_line(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_control() {
                ' '
            } else {
                character
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

const BEGIN_CONTEXT_SENTINEL: &str = "----- BEGIN KNOWLEDGE CONTEXT -----";
const END_CONTEXT_SENTINEL: &str = "----- END KNOWLEDGE CONTEXT -----";

pub use citation::{
    ParsedAssistantText, SourceCitation, clean_assistant_text, finalize_assistant_text,
    knowledge_source_chip_label, parse_assistant_text,
};
pub use index::{RetrievalHit, RetrievalIndex};
pub use pack::{
    KnowledgeReconciliation, KnowledgeReconciliationStatus,
    cleanup_obsolete_knowledge_pack_revisions, download_knowledge_pack, reconcile_knowledge_pack,
};
pub use prompt::{KnowledgePromptContext, KnowledgePromptHit, build_knowledge_prompt_context};
