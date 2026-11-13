use super::chunk::prepare_chunks;
use super::{
    NOTES_MAX_SOURCE_BYTES, NotesError, contains_unsupported_control, notes_content_revision,
    validate_document_id,
};

const EMBEDDING_TITLE_MAX_UTF8_BYTES: usize = 512;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotesSourceDocument {
    pub document_id: String,
    pub size: u64,
    pub modified_at_ms: Option<i64>,
}

impl NotesSourceDocument {
    pub fn validate(&self) -> Result<(), NotesError> {
        validate_document_id(&self.document_id)?;
        if self.size > NOTES_MAX_SOURCE_BYTES as u64 {
            return Err(NotesError::InvalidInput(
                "source document exceeds the supported size".to_string(),
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedNotesDocument {
    pub document_id: String,
    pub revision: String,
    pub title: String,
    pub chunks: Vec<PreparedNotesChunk>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedNotesChunk {
    pub section: Option<String>,
    pub text: String,
}

impl PreparedNotesDocument {
    pub fn embed(
        &self,
        mut embed_chunk: impl FnMut(&str, &str) -> Result<Vec<f32>, crate::llm::Error>,
    ) -> Result<Option<Vec<Vec<f32>>>, crate::llm::Error> {
        let mut embeddings = Vec::with_capacity(self.chunks.len());
        for chunk in &self.chunks {
            match embed_chunk(&self.embedding_title(chunk), &chunk.text) {
                Ok(vector) => embeddings.push(vector),
                Err(crate::llm::Error::PromptTooLong { .. }) => return Ok(None),
                Err(error) => return Err(error),
            }
        }
        Ok(Some(embeddings))
    }

    fn embedding_title(&self, chunk: &PreparedNotesChunk) -> String {
        let mut title = match chunk.section.as_deref() {
            Some(section) if section != self.title => format!("{} — {section}", self.title),
            _ => self.title.clone(),
        };
        let mut end = title.len().min(EMBEDDING_TITLE_MAX_UTF8_BYTES);
        while !title.is_char_boundary(end) {
            end -= 1;
        }
        title.truncate(end);
        title
    }
}

pub fn prepare_notes_document(
    document_id: &str,
    bytes: &[u8],
) -> Result<PreparedNotesDocument, NotesError> {
    validate_document_id(document_id)?;
    if bytes.len() > NOTES_MAX_SOURCE_BYTES {
        return Err(NotesError::InvalidInput(
            "source document exceeds the supported size".to_string(),
        ));
    }
    let text = std::str::from_utf8(bytes)
        .map_err(|_| NotesError::InvalidInput("source document is not valid UTF-8".to_string()))?;
    if text.trim().is_empty() {
        return Err(NotesError::InvalidInput(
            "source document must not be empty".to_string(),
        ));
    }
    if contains_unsupported_control(text) {
        return Err(NotesError::InvalidInput(
            "source document contains an unsupported control character".to_string(),
        ));
    }

    let revision = notes_content_revision(bytes);
    let (title, chunks) = prepare_chunks(document_id, text)?;
    Ok(PreparedNotesDocument {
        document_id: document_id.to_string(),
        revision,
        title,
        chunks,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::notes::{
        NOTES_CHUNK_OVERLAP_UTF8_BYTES, NOTES_CHUNK_UTF8_BYTES, NOTES_HEADING_MAX_UTF8_BYTES,
    };

    #[test]
    fn oversized_chunks_discard_partial_document_embeddings() {
        let prepared =
            prepare_notes_document("note.md", b"# Note\n\nFirst\n\n## Second\n\nSecond").unwrap();
        let mut calls = 0;
        let result = prepared
            .embed(|_, _| {
                calls += 1;
                if calls == 1 {
                    Ok(vec![1.0])
                } else {
                    Err(crate::llm::Error::PromptTooLong {
                        tokens: 2,
                        context_size: 1,
                    })
                }
            })
            .unwrap();
        assert_eq!(calls, 2);
        assert!(result.is_none());
    }

    #[test]
    fn prepares_and_chunks_markdown() {
        let text = "preamble\r\n\r\n# Local Notes\r\n\r\nintro\r\n\r\n## Indexing\r\n\r\nfirst paragraph\r\n\r\nsecond paragraph\r\n";
        let prepared = prepare_notes_document("projects/notes.md", text.as_bytes()).unwrap();
        assert_eq!(prepared.title, "Local Notes");
        assert_eq!(prepared.chunks.len(), 3);
        assert_eq!(prepared.chunks[0].section, None);
        assert_eq!(prepared.chunks[0].text, "preamble");
        assert_eq!(prepared.chunks[1].text, "intro");
        assert_eq!(prepared.chunks[2].section.as_deref(), Some("Indexing"));
        assert_eq!(
            prepared.chunks[2].text,
            "first paragraph\n\nsecond paragraph"
        );

        let text = "é".repeat(1_600);
        let prepared = prepare_notes_document("unicode.md", text.as_bytes()).unwrap();
        assert_eq!(prepared.title, "unicode.md");
        assert_eq!(prepared.chunks.len(), 3);
        assert!(
            prepared
                .chunks
                .iter()
                .all(|chunk| chunk.text.len() <= NOTES_CHUNK_UTF8_BYTES)
        );
        for pair in prepared.chunks.windows(2) {
            let overlap_characters = NOTES_CHUNK_OVERLAP_UTF8_BYTES / "é".len();
            let overlap = pair[0]
                .text
                .chars()
                .rev()
                .take(overlap_characters)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect::<String>();
            let next = pair[1]
                .text
                .chars()
                .take(overlap_characters)
                .collect::<String>();
            assert!(overlap.len() <= NOTES_CHUNK_OVERLAP_UTF8_BYTES);
            assert_eq!(overlap, next);
        }

        let prepared =
            prepare_notes_document("outline.md", b"# Project\n## Alice\n## Bob\n## Carol\n")
                .unwrap();
        assert_eq!(prepared.title, "Project");
        assert_eq!(prepared.chunks.len(), 3);
        assert_eq!(
            prepared
                .chunks
                .iter()
                .map(|chunk| chunk.text.as_str())
                .collect::<Vec<_>>(),
            ["Alice", "Bob", "Carol"]
        );
    }

    #[test]
    fn rejects_unsafe_or_oversized_content() {
        let error = prepare_notes_document("controls.md", b"safe\x1funsafe").unwrap_err();
        assert!(matches!(error, NotesError::InvalidInput(_)));

        let source = format!("# {}\n\nbody", "a".repeat(NOTES_HEADING_MAX_UTF8_BYTES + 1));
        assert!(matches!(
            prepare_notes_document("heading.md", source.as_bytes()),
            Err(NotesError::InvalidInput(_))
        ));
    }

    #[test]
    fn handles_fenced_and_indented_code() {
        let source = "```rust\n```not-a-closer\n# Code heading\n```\n# Real title\nbody";
        let prepared = prepare_notes_document("fenced.md", source.as_bytes()).unwrap();
        assert_eq!(prepared.title, "Real title");
        assert!(prepared.chunks.iter().all(|chunk| {
            chunk.section.as_deref() != Some("Code heading")
                && !chunk.text.starts_with("Code heading")
        }));

        let source = "    ```\n# Real title\nbody";
        let prepared = prepare_notes_document("indented.md", source.as_bytes()).unwrap();
        assert_eq!(prepared.title, "Real title");
    }
}
