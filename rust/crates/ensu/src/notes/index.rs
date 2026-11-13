use std::collections::{BTreeMap, btree_map::Entry};
use std::path::Path;

use serde::{Deserialize, Serialize};

use super::manifest::{
    collection_directory, document_storage_id, load_published_manifest, shard_directory,
};
use super::shard::{NotesShard, load_and_validate_shard_metadata, load_and_validate_vectors};
use super::{NotesCollectionReadPin, NotesError, pinned_revision_key, validate_collection_id};

const RELEVANCE_THRESHOLD: f32 = 0.50;
const MAX_HITS_PER_COLLECTION: usize = 5;
const MAX_HITS_PER_DOCUMENT: usize = 3;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotePassageLocator {
    pub collection_id: String,
    pub document_id: String,
    pub indexed_revision: String,
    pub shard_sha256: String,
    pub chunk_index: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NotesSearchHit {
    pub locator: NotePassageLocator,
    pub collection_id: String,
    pub document_id: String,
    pub revision: String,
    pub score: f32,
    pub title: String,
    pub section: Option<String>,
    pub text: String,
}

struct IndexedDocument {
    document_id: String,
    revision: String,
    chunk_count: usize,
    vector_offset: usize,
    shard_sha256: String,
}

#[derive(Clone, Copy)]
struct RankedChunk {
    score: f32,
    document_index: usize,
    chunk_index: usize,
    vector_offset: usize,
}

pub struct NotesCollectionIndex {
    read_pin: NotesCollectionReadPin,
    collection_id: String,
    last_updated_at_ms: Option<i64>,
    dimension: usize,
    scale: f32,
    documents: Vec<IndexedDocument>,
    vectors: Vec<u8>,
}

pub struct NotesCollectionIndexSummary {
    pub document_count: usize,
    pub last_updated_at_ms: Option<i64>,
}

impl NotesCollectionIndex {
    pub fn inspect(
        index_root: impl AsRef<Path>,
        collection_id: String,
    ) -> Result<NotesCollectionIndexSummary, NotesError> {
        validate_collection_id(&collection_id)?;
        let collection_directory = collection_directory(index_root.as_ref(), &collection_id);
        let (manifest, last_updated_at_ms) =
            load_published_manifest(&collection_directory, &collection_id, true)?;
        Ok(NotesCollectionIndexSummary {
            document_count: manifest.documents.len(),
            last_updated_at_ms,
        })
    }

    pub fn open(index_root: impl AsRef<Path>, collection_id: String) -> Result<Self, NotesError> {
        validate_collection_id(&collection_id)?;
        let collection_directory = collection_directory(index_root.as_ref(), &collection_id);
        let mut read_pin = NotesCollectionReadPin::acquire(&collection_directory)?;
        let collection_directory = read_pin.collection_directory().to_path_buf();
        let (manifest, last_updated_at_ms) =
            load_published_manifest(&collection_directory, &collection_id, true)?;
        read_pin.pin_revisions(manifest.documents.iter().map(|(document_id, document)| {
            pinned_revision_key(&document_storage_id(document_id), &document.revision)
        }))?;
        let dimension =
            usize::try_from(manifest.index_contract.retrieval_dimension).map_err(|_| {
                NotesError::InvalidIndex("retrieval dimension is too large".to_string())
            })?;
        let scale = manifest.index_contract.quantization_scale as f32;
        let total_chunks = manifest
            .documents
            .values()
            .try_fold(0_usize, |total, document| {
                let chunk_count = usize::try_from(document.chunk_count).map_err(|_| {
                    NotesError::InvalidIndex("manifest chunk count is too large".to_string())
                })?;
                total.checked_add(chunk_count).ok_or_else(|| {
                    NotesError::InvalidIndex("collection chunk count overflow".to_string())
                })
            })?;
        let vector_bytes = total_chunks.checked_mul(dimension).ok_or_else(|| {
            NotesError::InvalidIndex("collection vector byte length overflow".to_string())
        })?;
        let mut documents = Vec::new();
        documents
            .try_reserve_exact(manifest.documents.len())
            .map_err(|_| {
                NotesError::InvalidIndex("collection document allocation is too large".to_string())
            })?;
        let mut vectors = Vec::new();
        vectors.try_reserve_exact(vector_bytes).map_err(|_| {
            NotesError::InvalidIndex("collection vector allocation is too large".to_string())
        })?;
        for (document_id, document) in &manifest.documents {
            let chunk_count = usize::try_from(document.chunk_count).map_err(|_| {
                NotesError::InvalidIndex("manifest chunk count is too large".to_string())
            })?;
            let directory = shard_directory(&collection_directory, document_id, &document.revision);
            let loaded_vectors =
                load_and_validate_vectors(&directory, chunk_count, &document.vectors_sha256)?;
            documents.push(IndexedDocument {
                document_id: document_id.clone(),
                revision: document.revision.clone(),
                chunk_count,
                vector_offset: vectors.len(),
                shard_sha256: document.shard_sha256.clone(),
            });
            vectors.extend_from_slice(&loaded_vectors);
        }
        if documents.len() != manifest.documents.len() || vectors.len() != vector_bytes {
            return Err(NotesError::InvalidIndex(
                "loaded collection shape does not match its manifest".to_string(),
            ));
        }
        Ok(Self {
            read_pin,
            collection_id,
            last_updated_at_ms,
            dimension,
            scale,
            documents,
            vectors,
        })
    }

    pub fn document_count(&self) -> usize {
        self.documents.len()
    }

    pub fn last_updated_at_ms(&self) -> Option<i64> {
        self.last_updated_at_ms
    }

    pub fn estimated_heap_bytes(&self) -> usize {
        self.collection_id
            .capacity()
            .saturating_add(self.read_pin.estimated_heap_bytes())
            .saturating_add(
                self.documents
                    .capacity()
                    .saturating_mul(std::mem::size_of::<IndexedDocument>()),
            )
            .saturating_add(self.vectors.capacity())
            .saturating_add(self.documents.iter().fold(0_usize, |total, document| {
                total
                    .saturating_add(document.document_id.capacity())
                    .saturating_add(document.revision.capacity())
                    .saturating_add(document.shard_sha256.capacity())
            }))
    }

    fn load_shard(&self, document: &IndexedDocument) -> Result<NotesShard, NotesError> {
        let directory = shard_directory(
            self.read_pin.collection_directory(),
            &document.document_id,
            &document.revision,
        );
        load_and_validate_shard_metadata(
            &directory,
            &self.collection_id,
            &document.document_id,
            &document.revision,
            document.chunk_count,
            &document.shard_sha256,
            None,
        )
    }

    pub fn reload_passage(
        &self,
        locator: &NotePassageLocator,
    ) -> Result<Option<NotesSearchHit>, NotesError> {
        let NotePassageLocator {
            collection_id,
            document_id,
            indexed_revision,
            shard_sha256,
            chunk_index,
        } = locator;
        if collection_id != &self.collection_id {
            return Ok(None);
        }
        let Some(document) = self.documents.iter().find(|document| {
            &document.document_id == document_id
                && &document.revision == indexed_revision
                && &document.shard_sha256 == shard_sha256
        }) else {
            return Ok(None);
        };
        let Ok(chunk_index) = usize::try_from(*chunk_index) else {
            return Ok(None);
        };
        if chunk_index >= document.chunk_count {
            return Ok(None);
        }
        let shard = self.load_shard(document)?;
        self.passage_hit(document, &shard, chunk_index, 0.0)
            .map(Some)
    }

    pub fn search(&self, query: &[f32]) -> Result<Vec<NotesSearchHit>, NotesError> {
        validate_search(query, self.dimension)?;
        let mut ranked = Vec::with_capacity(MAX_HITS_PER_COLLECTION);
        for (document_index, document) in self.documents.iter().enumerate() {
            let mut document_ranked = Vec::with_capacity(MAX_HITS_PER_DOCUMENT);
            for chunk_index in 0..document.chunk_count {
                let vector_offset = document
                    .vector_offset
                    .checked_add(chunk_index.checked_mul(self.dimension).ok_or_else(|| {
                        NotesError::InvalidIndex("shard vector offset overflow".to_string())
                    })?)
                    .ok_or_else(|| {
                        NotesError::InvalidIndex("shard vector offset overflow".to_string())
                    })?;
                let vector_end = vector_offset.checked_add(self.dimension).ok_or_else(|| {
                    NotesError::InvalidIndex("shard vector offset overflow".to_string())
                })?;
                let vector = self.vectors.get(vector_offset..vector_end).ok_or_else(|| {
                    NotesError::InvalidIndex(
                        "shard vector range exceeds the collection".to_string(),
                    )
                })?;
                let score = query
                    .iter()
                    .zip(vector)
                    .map(|(query, stored)| *query * f32::from(*stored as i8))
                    .sum::<f32>()
                    / self.scale;
                if score.is_finite() && score >= RELEVANCE_THRESHOLD {
                    retain_best(
                        &mut document_ranked,
                        RankedChunk {
                            score,
                            document_index,
                            chunk_index,
                            vector_offset,
                        },
                        MAX_HITS_PER_DOCUMENT,
                        &self.documents,
                    );
                }
            }
            for candidate in document_ranked {
                retain_best(
                    &mut ranked,
                    candidate,
                    MAX_HITS_PER_COLLECTION,
                    &self.documents,
                );
            }
        }

        let mut hits = Vec::with_capacity(MAX_HITS_PER_COLLECTION.min(ranked.len()));
        let mut loaded_shards = BTreeMap::<usize, NotesShard>::new();
        for candidate in ranked {
            let document = &self.documents[candidate.document_index];
            let shard = match loaded_shards.entry(candidate.document_index) {
                Entry::Occupied(entry) => entry.into_mut(),
                Entry::Vacant(entry) => entry.insert(self.load_shard(document)?),
            };
            hits.push(self.passage_hit(document, shard, candidate.chunk_index, candidate.score)?);
        }
        Ok(hits)
    }

    fn passage_hit(
        &self,
        document: &IndexedDocument,
        shard: &NotesShard,
        chunk_index: usize,
        score: f32,
    ) -> Result<NotesSearchHit, NotesError> {
        let chunk = shard.chunks.get(chunk_index).ok_or_else(|| {
            NotesError::InvalidIndex("selected shard chunk is missing".to_string())
        })?;
        Ok(NotesSearchHit {
            locator: NotePassageLocator {
                collection_id: self.collection_id.clone(),
                document_id: document.document_id.clone(),
                indexed_revision: document.revision.clone(),
                shard_sha256: document.shard_sha256.clone(),
                chunk_index: chunk_index as u64,
            },
            collection_id: self.collection_id.clone(),
            document_id: document.document_id.clone(),
            revision: document.revision.clone(),
            score,
            title: shard.title.clone(),
            section: chunk.section.clone(),
            text: chunk.text.clone(),
        })
    }
}

fn retain_best(
    ranked: &mut Vec<RankedChunk>,
    candidate: RankedChunk,
    limit: usize,
    documents: &[IndexedDocument],
) {
    ranked.push(candidate);
    ranked.sort_unstable_by(|left, right| ranked_order(left, right, documents));
    ranked.truncate(limit);
}

fn ranked_order(
    left: &RankedChunk,
    right: &RankedChunk,
    documents: &[IndexedDocument],
) -> std::cmp::Ordering {
    right
        .score
        .total_cmp(&left.score)
        .then_with(|| {
            documents[left.document_index]
                .document_id
                .cmp(&documents[right.document_index].document_id)
        })
        .then_with(|| left.vector_offset.cmp(&right.vector_offset))
}

fn validate_search(query: &[f32], dimension: usize) -> Result<(), NotesError> {
    if query.len() != dimension {
        return Err(NotesError::InvalidInput(format!(
            "query has {} dimensions; expected {dimension}",
            query.len()
        )));
    }
    if query.iter().any(|component| !component.is_finite()) {
        return Err(NotesError::InvalidInput(
            "query contains a non-finite component".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;
    use crate::notes::shard::{NOTES_SHARD_FILE, NOTES_VECTORS_FILE};
    use crate::notes::{
        NotesIndexWriter, NotesSourceDocument, PreparedNotesChunk, PreparedNotesDocument,
        cleanup_unreferenced_notes_shards, notes_content_revision,
    };

    const COLLECTION_ID: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn document(document_id: &str, chunk_count: usize) -> PreparedNotesDocument {
        PreparedNotesDocument {
            document_id: document_id.to_string(),
            revision: notes_content_revision(document_id.as_bytes()),
            title: document_id.to_string(),
            chunks: (0..chunk_count)
                .map(|index| PreparedNotesChunk {
                    section: None,
                    text: format!("{document_id} chunk {index}"),
                })
                .collect(),
        }
    }

    fn source(document: &PreparedNotesDocument) -> NotesSourceDocument {
        NotesSourceDocument {
            document_id: document.document_id.clone(),
            size: document
                .chunks
                .iter()
                .map(|chunk| chunk.text.len() as u64)
                .sum(),
            modified_at_ms: Some(1),
        }
    }

    fn embedding(axis: usize, score: f32) -> Vec<f32> {
        let mut embedding = vec![0.0; 512];
        embedding[axis] = score;
        embedding
    }

    #[test]
    fn passage_reload_checks_revision_chunk_and_shard_integrity() {
        let temp = tempfile::tempdir().unwrap();
        let doc = document("trip.md", 2);
        let mut writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(&doc, &[embedding(0, 1.0), embedding(0, 0.9)], &source(&doc))
            .unwrap();
        writer.publish(true).unwrap();
        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        let hits = index.search(&embedding(0, 1.0)).unwrap();
        assert_eq!(hits.len(), 2);
        assert_ne!(hits[0].locator, hits[1].locator);
        drop(index);
        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        for (hit, chunk) in hits.iter().zip(&doc.chunks) {
            let loaded = index.reload_passage(&hit.locator).unwrap().unwrap();
            assert_eq!(loaded.text, chunk.text);
            assert_eq!(loaded.locator, hit.locator);
        }
        for field in ["revision", "shard", "chunk", "collection", "document"] {
            let mut wrong = hits[0].locator.clone();
            match field {
                "revision" => wrong.indexed_revision = "c".repeat(64),
                "shard" => wrong.shard_sha256 = "c".repeat(64),
                "chunk" => wrong.chunk_index = u64::MAX,
                "collection" => wrong.collection_id = "other".to_string(),
                _ => wrong.document_id = "other.md".to_string(),
            }
            assert!(index.reload_passage(&wrong).unwrap().is_none(), "{field}");
        }
        let directory = shard_directory(
            &collection_directory(temp.path(), COLLECTION_ID),
            &doc.document_id,
            &doc.revision,
        );
        fs::write(directory.join(NOTES_SHARD_FILE), b"corrupt").unwrap();
        assert!(index.reload_passage(&hits[0].locator).is_err());
    }

    #[test]
    fn search_loads_metadata_only_for_selected_documents() {
        let temp = tempfile::tempdir().unwrap();
        let first = document("first.md", 1);
        let second = document("second.md", 1);
        let mut writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(&first, &[embedding(0, 1.0)], &source(&first))
            .unwrap();
        writer
            .commit_document(&second, &[embedding(1, 1.0)], &source(&second))
            .unwrap();
        writer.publish(true).unwrap();

        let second_shard = shard_directory(
            &collection_directory(temp.path(), COLLECTION_ID),
            &second.document_id,
            &second.revision,
        )
        .join(NOTES_SHARD_FILE);
        fs::write(second_shard, b"corrupt").unwrap();

        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        let hits = index.search(&embedding(0, 1.0)).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].document_id, "first.md");
        assert!(matches!(
            index.search(&embedding(1, 1.0)),
            Err(NotesError::InvalidIndex(_) | NotesError::Json(_))
        ));
    }

    #[test]
    fn open_index_keeps_its_shards_alive_until_it_is_dropped() {
        let temp = tempfile::tempdir().unwrap();
        let original = document("note.md", 1);
        let original_directory = shard_directory(
            &collection_directory(temp.path(), COLLECTION_ID),
            &original.document_id,
            &original.revision,
        );
        let mut writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(&original, &[embedding(0, 1.0)], &source(&original))
            .unwrap();
        writer.publish(true).unwrap();
        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();

        let mut replacement = document("note.md", 1);
        replacement.revision = notes_content_revision(b"replacement");
        replacement.chunks[0].text = "replacement chunk".to_string();
        writer
            .commit_document(&replacement, &[embedding(1, 1.0)], &source(&replacement))
            .unwrap();
        writer.publish(true).unwrap();

        assert!(original_directory.is_dir());
        let hits = index.search(&embedding(0, 1.0)).unwrap();
        assert_eq!(hits[0].text, original.chunks[0].text);

        drop(index);
        let replacement_index =
            NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        cleanup_unreferenced_notes_shards(temp.path(), COLLECTION_ID).unwrap();
        assert!(!original_directory.exists());
        assert_eq!(
            replacement_index.search(&embedding(1, 1.0)).unwrap()[0].text,
            replacement.chunks[0].text
        );
    }

    #[test]
    fn failed_open_releases_its_collection_read_pin() {
        let temp = tempfile::tempdir().unwrap();
        let note = document("note.md", 1);
        let mut writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(&note, &[embedding(0, 1.0)], &source(&note))
            .unwrap();
        writer.publish(true).unwrap();
        let collection_directory = collection_directory(temp.path(), COLLECTION_ID);
        let vectors_path =
            shard_directory(&collection_directory, &note.document_id, &note.revision)
                .join(NOTES_VECTORS_FILE);
        fs::write(vectors_path, b"corrupt").unwrap();

        assert!(NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).is_err());
        let collection_directory = fs::canonicalize(collection_directory).unwrap();
        let (opening, revisions) = crate::notes::collection_reader_snapshot(&collection_directory);
        assert!(!opening);
        assert!(revisions.is_empty());
    }

    #[test]
    fn search_bounds_per_document_and_global_ranking() {
        let temp = tempfile::tempdir().unwrap();
        let dominant = document("a.md", 5);
        let mut writer = NotesIndexWriter::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        writer
            .commit_document(
                &dominant,
                &[1.0, 0.99, 0.98, 0.97, 0.96]
                    .into_iter()
                    .map(|score| embedding(0, score))
                    .collect::<Vec<_>>(),
                &source(&dominant),
            )
            .unwrap();
        for (document_id, score) in [("b.md", 0.95), ("c.md", 0.94), ("d.md", 0.93)] {
            let document = document(document_id, 1);
            writer
                .commit_document(&document, &[embedding(0, score)], &source(&document))
                .unwrap();
        }
        writer.publish(true).unwrap();

        let index = NotesCollectionIndex::open(temp.path(), COLLECTION_ID.to_string()).unwrap();
        let hits = index.search(&embedding(0, 1.0)).unwrap();

        assert_eq!(hits.len(), MAX_HITS_PER_COLLECTION);
        assert_eq!(
            hits.iter().filter(|hit| hit.document_id == "a.md").count(),
            MAX_HITS_PER_DOCUMENT
        );
        assert_eq!(hits[3].document_id, "b.md");
        assert_eq!(hits[4].document_id, "c.md");
    }
}
