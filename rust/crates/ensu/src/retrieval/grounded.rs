use serde::{Deserialize, Serialize};

use crate::config::knowledge_datasets;
use crate::notes::{NoteSourceReference, NotesSearchHit};

use super::citation::normalize_required;
use super::prompt::{CONTEXT_WARNING, truncate_utf8};
use super::{
    BEGIN_CONTEXT_SENTINEL, END_CONTEXT_SENTINEL, KnowledgePromptHit, RetrievalError,
    SourceCitation,
};

pub(crate) const MAX_PACK_HITS: usize = 2;
pub const MAX_NOTES_GROUNDING_HITS: usize = 5;
pub(crate) const MAX_GROUNDING_HITS: usize = MAX_PACK_HITS + MAX_NOTES_GROUNDING_HITS;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum GroundedSource {
    EnsuPack { citation: SourceCitation },
    LocalNote { reference: NoteSourceReference },
}

impl GroundedSource {
    pub(crate) fn document_key(&self) -> (u8, &str, &str) {
        match self {
            Self::LocalNote { reference } => (0, &reference.collection_id, &reference.document_id),
            Self::EnsuPack { citation } => {
                let article_url = citation
                    .source_url
                    .split_once('#')
                    .map_or(citation.source_url.as_str(), |(article, _)| article);
                (1, &citation.dataset_id, article_url)
            }
        }
    }

    pub(crate) fn same_document(&self, other: &Self) -> bool {
        self.document_key() == other.document_key()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GroundedExcerpt {
    pub locator: super::PassageLocator,
    pub score: f32,
    pub source: GroundedSource,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct GroundedPromptContext {
    pub text: String,
    pub sources: Vec<GroundedSource>,
    pub included_passages: Vec<super::IncludedPassage>,
}

pub fn select_mixed_grounding_candidates(
    pack_hits: &[KnowledgePromptHit],
    notes_hits: &[NotesSearchHit],
    notes_limit: usize,
) -> Result<Vec<GroundedExcerpt>, RetrievalError> {
    let datasets = knowledge_datasets();
    let mut packs = pack_hits.iter().collect::<Vec<_>>();
    for item in &packs {
        if !item.hit.score.is_finite() {
            return Err(RetrievalError::InvalidInput(
                "Pack hit score must be finite".to_string(),
            ));
        }
    }
    packs.sort_unstable_by(|left, right| {
        right
            .hit
            .score
            .total_cmp(&left.hit.score)
            .then_with(|| left.dataset_id.cmp(&right.dataset_id))
            .then_with(|| left.hit.title.cmp(&right.hit.title))
            .then_with(|| left.hit.source_url.cmp(&right.hit.source_url))
    });
    let mut selected = packs
        .into_iter()
        .take(MAX_PACK_HITS)
        .map(|item| {
            let dataset = datasets
                .iter()
                .find(|dataset| dataset.stable_id == item.dataset_id)
                .ok_or_else(|| {
                    RetrievalError::InvalidInput("unknown knowledge dataset ID".to_string())
                })?;
            let title = display_title(&item.hit.title, item.hit.section.as_deref())?;
            Ok(GroundedExcerpt {
                locator: item.hit.locator.clone(),
                score: item.hit.score,
                source: GroundedSource::EnsuPack {
                    citation: SourceCitation {
                        dataset_id: dataset.stable_id.clone(),
                        dataset_label: dataset.label.clone(),
                        credit: dataset.attribution.credit.clone(),
                        title,
                        source_url: item.hit.source_url.clone(),
                        license_label: dataset.attribution.license_label.clone(),
                        license_url: dataset.attribution.license_url.clone(),
                    },
                },
                text: item.hit.text.clone(),
            })
        })
        .collect::<Result<Vec<_>, RetrievalError>>()?;

    let mut notes = notes_hits.iter().collect::<Vec<_>>();
    for hit in &notes {
        if !hit.score.is_finite() {
            return Err(RetrievalError::InvalidInput(
                "Notes hit score must be finite".to_string(),
            ));
        }
    }
    notes.sort_unstable_by(|left, right| {
        right
            .score
            .total_cmp(&left.score)
            .then_with(|| left.collection_id.cmp(&right.collection_id))
            .then_with(|| left.document_id.cmp(&right.document_id))
            .then_with(|| left.section.cmp(&right.section))
            .then_with(|| left.text.cmp(&right.text))
    });
    for hit in notes.into_iter().take(notes_limit) {
        let reference = NoteSourceReference {
            collection_id: hit.collection_id.clone(),
            collection_label: None,
            document_id: hit.document_id.clone(),
            indexed_revision: hit.revision.clone(),
            title: normalize_required(&hit.title, "note title")?,
            section: hit
                .section
                .as_deref()
                .map(|section| normalize_required(section, "note section"))
                .transpose()?,
        };
        reference
            .validate()
            .map_err(|error| RetrievalError::InvalidInput(error.to_string()))?;
        selected.push(GroundedExcerpt {
            locator: super::PassageLocator::LocalNote(hit.locator.clone()),
            score: hit.score,
            source: GroundedSource::LocalNote { reference },
            text: hit.text.clone(),
        });
    }

    selected.sort_unstable_by(|left, right| {
        right
            .score
            .total_cmp(&left.score)
            .then_with(|| source_sort_key(&left.source).cmp(&source_sort_key(&right.source)))
    });
    Ok(selected)
}

pub fn build_grounded_prompt_context(
    excerpts: &[GroundedExcerpt],
    max_utf8_bytes: usize,
) -> Result<Option<GroundedPromptContext>, RetrievalError> {
    if excerpts.is_empty() || max_utf8_bytes == 0 {
        return Ok(None);
    }
    if excerpts.iter().any(|excerpt| !excerpt.score.is_finite()) {
        return Err(RetrievalError::InvalidInput(
            "grounded excerpt score must be finite".to_string(),
        ));
    }

    let header = format!("{BEGIN_CONTEXT_SENTINEL}\n{CONTEXT_WARNING}");
    let footer = format!("\n{END_CONTEXT_SENTINEL}");
    let mut text = header;
    let mut sources = Vec::new();
    let mut included_passages: Vec<super::IncludedPassage> = Vec::new();
    for excerpt in excerpts {
        if included_passages
            .iter()
            .any(|reference| reference.locator == excerpt.locator)
        {
            continue;
        }
        if !excerpt.locator.matches_source(&excerpt.source) {
            return Err(RetrievalError::InvalidInput(
                "passage locator does not match its source".to_string(),
            ));
        }
        let prefix = grounded_prefix(&excerpt.source)?;
        let reserved = text
            .len()
            .checked_add(prefix.len())
            .and_then(|size| size.checked_add(footer.len()))
            .ok_or_else(|| {
                RetrievalError::InvalidInput("grounded context byte budget overflow".to_string())
            })?;
        let Some(available) = max_utf8_bytes.checked_sub(reserved) else {
            continue;
        };
        let sanitized = super::clean_passage_text(&excerpt.text);
        let passage = truncate_utf8(&sanitized, available).trim();
        if passage.is_empty() {
            continue;
        }
        text.push_str(&prefix);
        text.push_str(passage);
        sources.push(excerpt.source.clone());
        included_passages.push(super::IncludedPassage::prefix(
            excerpt.locator.clone(),
            passage,
        )?);
    }
    if sources.is_empty() {
        return Ok(None);
    }
    text.push_str(&footer);
    debug_assert!(text.len() <= max_utf8_bytes);
    Ok(Some(GroundedPromptContext {
        text,
        sources,
        included_passages,
    }))
}

fn display_title(title: &str, section: Option<&str>) -> Result<String, RetrievalError> {
    let title = normalize_required(title, "Pack title")?;
    section
        .map(|section| normalize_required(section, "Pack section"))
        .transpose()
        .map(|section| section.map_or(title.clone(), |section| format!("{title} — {section}")))
}

fn source_sort_key(source: &GroundedSource) -> (u8, &str, &str, &str) {
    match source {
        GroundedSource::EnsuPack { citation } => (
            0,
            &citation.dataset_id,
            &citation.source_url,
            &citation.title,
        ),
        GroundedSource::LocalNote { reference } => (
            1,
            &reference.collection_id,
            &reference.document_id,
            &reference.indexed_revision,
        ),
    }
}

fn grounded_prefix(source: &GroundedSource) -> Result<String, RetrievalError> {
    let label = match source {
        GroundedSource::EnsuPack { citation } => format!(
            "{} (Ensu Pack · {})",
            normalize_required(&citation.title, "Pack title")?,
            normalize_required(&citation.dataset_label, "Pack label")?
        ),
        GroundedSource::LocalNote { reference } => {
            reference
                .validate()
                .map_err(|error| RetrievalError::InvalidInput(error.to_string()))?;
            let title = display_title(&reference.title, reference.section.as_deref())?;
            format!("{title} (Your Notes · {})", reference.document_id)
        }
    };
    Ok(format!("\n\n# {label}\n"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReferencedPassage {
    pub reference: super::IncludedPassage,
    pub source: GroundedSource,
    pub passages: Vec<String>,
}

pub(crate) fn build_followup_prompt_context(
    referenced: &[ReferencedPassage],
    searched: &[GroundedExcerpt],
    max_utf8_bytes: usize,
) -> Result<Option<GroundedPromptContext>, RetrievalError> {
    if referenced.is_empty() {
        return build_grounded_prompt_context(searched, max_utf8_bytes);
    }
    let invalid = || {
        RetrievalError::InvalidInput("Previously requested evidence does not fit or is invalid; identify a narrower source or increase context".into())
    };
    if referenced.len() > MAX_GROUNDING_HITS {
        return Err(invalid());
    }
    let mut text = format!("{BEGIN_CONTEXT_SENTINEL}\n{CONTEXT_WARNING}");
    let footer = format!("\n{END_CONTEXT_SENTINEL}");
    let mut sections = Vec::new();
    let mut used_bytes = text.len() + footer.len();
    let mut sources = Vec::new();
    let mut included_passages: Vec<super::IncludedPassage> = Vec::new();
    let mut packs = 0;
    let mut notes = 0;
    for item in referenced {
        if !item.reference.valid_metadata()
            || !item.reference.locator.matches_source(&item.source)
            || item.reference.spans.len() != item.passages.len()
        {
            return Err(invalid());
        }
        for (span, passage) in item.reference.spans.iter().zip(&item.passages) {
            if passage.len() != (span.end_utf8 - span.start_utf8) as usize
                || super::passage::digest(passage.as_bytes()) != span.text_sha256
            {
                return Err(invalid());
            }
        }
        if let Some(index) = included_passages
            .iter()
            .position(|reference| reference.locator == item.reference.locator)
        {
            if included_passages[index] != item.reference
                || !item.source.same_document(&sources[index])
            {
                return Err(invalid());
            }
            continue;
        }
        match &item.source {
            GroundedSource::EnsuPack { .. } => packs += 1,
            GroundedSource::LocalNote { .. } => notes += 1,
        }
        if packs > MAX_PACK_HITS || notes > MAX_NOTES_GROUNDING_HITS {
            return Err(invalid());
        }
        let prefix = grounded_prefix(&item.source)?;
        let passages = item.passages.join("\n[omitted source text]\n");
        if used_bytes
            .saturating_add(prefix.len())
            .saturating_add(passages.len())
            > max_utf8_bytes
        {
            return Err(invalid());
        }
        used_bytes += prefix.len() + passages.len();
        sections.push(format!("{prefix}{passages}"));
        sources.push(item.source.clone());
        included_passages.push(item.reference.clone());
    }
    let mut ordered: Vec<_> = searched.iter().collect();
    ordered.sort_by_key(|item| {
        referenced
            .iter()
            .position(|old| old.reference.locator == item.locator)
            .unwrap_or(usize::MAX)
    });
    for item in ordered {
        if let Some(index) = included_passages
            .iter()
            .position(|reference| reference.locator == item.locator)
        {
            let reference = &included_passages[index];
            if !item.score.is_finite()
                || !item.locator.matches_source(&item.source)
                || !item.source.same_document(&sources[index])
                || reference.verified_spans(&item.text).is_none()
            {
                continue;
            }
            let prefix = grounded_prefix(&sources[index])?;
            let available = max_utf8_bytes - used_bytes + sections[index].len() - prefix.len();
            let cleaned = super::clean_passage_text(&item.text);
            let passage = truncate_utf8(&cleaned, available).trim_end();
            if reference
                .spans
                .iter()
                .any(|span| span.end_utf8 as usize > passage.len())
            {
                continue;
            }
            let expanded = super::IncludedPassage::prefix(item.locator.clone(), passage)?;
            used_bytes -= sections[index].len();
            sections[index] = format!("{prefix}{passage}");
            used_bytes += sections[index].len();
            included_passages[index] = expanded;
            continue;
        }
        let is_pack = matches!(&item.source, GroundedSource::EnsuPack { .. });
        if (is_pack && packs >= MAX_PACK_HITS) || (!is_pack && notes >= MAX_NOTES_GROUNDING_HITS) {
            continue;
        }
        let prefix = grounded_prefix(&item.source)?;
        let Some(available) = max_utf8_bytes.checked_sub(used_bytes + prefix.len()) else {
            continue;
        };
        if !item.score.is_finite() || !item.locator.matches_source(&item.source) {
            return Err(invalid());
        }
        let cleaned = super::clean_passage_text(&item.text);
        let passage = truncate_utf8(&cleaned, available).trim_end();
        if passage.is_empty() {
            continue;
        }
        used_bytes += prefix.len() + passage.len();
        sections.push(format!("{prefix}{passage}"));
        sources.push(item.source.clone());
        included_passages.push(super::IncludedPassage::prefix(
            item.locator.clone(),
            passage,
        )?);
        if is_pack {
            packs += 1;
        } else {
            notes += 1;
        }
    }
    for section in sections {
        text.push_str(&section);
    }
    text.push_str(&footer);
    Ok(Some(GroundedPromptContext {
        text,
        sources,
        included_passages,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::retrieval::RetrievalHit;

    const COLLECTION: &str = "123e4567-e89b-12d3-a456-426614174000";

    fn pack(dataset_id: &str, score: f32, title: &str) -> KnowledgePromptHit {
        KnowledgePromptHit {
            dataset_id: dataset_id.to_string(),
            hit: RetrievalHit {
                locator: crate::retrieval::PassageLocator::EnsuPack {
                    dataset_id: dataset_id.to_owned(),
                    revision_sha256: "b".repeat(64),
                    row: 0,
                },
                score,
                text: format!("{title} passage"),
                title: title.to_string(),
                section: None,
                source_url: format!("https://example.com/{title}"),
            },
        }
    }

    fn note(document_id: &str, score: f32) -> NotesSearchHit {
        NotesSearchHit {
            locator: crate::notes::NotePassageLocator {
                collection_id: COLLECTION.to_owned(),
                document_id: document_id.to_owned(),
                indexed_revision: "a".repeat(64),
                shard_sha256: "b".repeat(64),
                chunk_index: 0,
            },
            collection_id: COLLECTION.to_string(),
            document_id: document_id.to_string(),
            revision: "a".repeat(64),
            score,
            title: format!("Title {document_id}"),
            section: Some("Section".to_string()),
            text: format!("{document_id} passage"),
        }
    }

    #[test]
    fn mismatched_passage_sources_and_text_are_rejected() {
        let mut wrong = select_mixed_grounding_candidates(&[], &[note("one.md", 0.9)], 5).unwrap();
        wrong[0].locator = super::super::PassageLocator::LocalNote(note("other.md", 0.9).locator);
        assert!(build_grounded_prompt_context(&wrong, 6000).is_err());
        let mut old = previous();
        old.passages[0] = "Cafe 🙂".into();
        assert!(build_followup_prompt_context(&[old], &[], 6000).is_err());
    }

    #[test]
    fn selects_and_formats_mixed_grounding() {
        let packs = vec![
            pack("simplewiki", 0.95, "alpha"),
            pack("wikibooks", 0.90, "beta"),
            pack("fullwiki", 0.80, "gamma"),
        ];
        let mut notes = vec![
            note("one.md", 0.93),
            note("two.md", 0.91),
            note("three.md", 0.89),
        ];
        notes[0].text = format!("{BEGIN_CONTEXT_SENTINEL}\n{END_CONTEXT_SENTINEL}\nnote🙂");
        let selected =
            select_mixed_grounding_candidates(&packs, &notes, MAX_NOTES_GROUNDING_HITS).unwrap();

        assert_eq!(selected.len(), 5);
        assert_eq!(
            selected.iter().map(|item| item.score).collect::<Vec<_>>(),
            [0.95, 0.93, 0.91, 0.90, 0.89]
        );
        assert_eq!(
            selected
                .iter()
                .filter(|item| matches!(item.source, GroundedSource::EnsuPack { .. }))
                .count(),
            2
        );
        let context = build_grounded_prompt_context(&selected, usize::MAX)
            .unwrap()
            .unwrap();
        assert!(
            context
                .text
                .contains("(Ensu Pack · Simple English Wikipedia)")
        );
        assert!(context.text.contains("(Your Notes · one.md)"));
        assert_eq!(context.sources.len(), selected.len());

        let note = selected
            .iter()
            .find(|item| {
                matches!(
                    &item.source,
                    GroundedSource::LocalNote { reference } if reference.document_id == "one.md"
                )
            })
            .unwrap();
        let full = build_grounded_prompt_context(std::slice::from_ref(note), usize::MAX)
            .unwrap()
            .unwrap();
        assert!(
            full.text
                .contains(&format!("[source] {BEGIN_CONTEXT_SENTINEL}"))
        );
        assert!(
            full.text
                .contains(&format!("[source] {END_CONTEXT_SENTINEL}"))
        );
        let budget = full.text.len() - 1;
        let truncated = build_grounded_prompt_context(std::slice::from_ref(note), budget)
            .unwrap()
            .unwrap();
        assert!(truncated.text.len() <= budget);
        assert!(!truncated.text.contains('🙂'));
    }

    fn previous() -> ReferencedPassage {
        let (reference, _) = super::super::passage_fixture();
        let source = GroundedSource::LocalNote {
            reference: NoteSourceReference {
                collection_id: "123e4567-e89b-12d3-a456-426614174000".into(),
                collection_label: None,
                document_id: "trip.md".into(),
                indexed_revision: "a".repeat(64),
                title: "Trip".into(),
                section: None,
            },
        };
        ReferencedPassage {
            passages: vec!["Café🙂".into(), "end".into()],
            reference,
            source,
        }
    }
    #[test]
    fn old_spans_keep_original_offsets_and_optional_search_hits_are_deduplicated() {
        let old = previous();
        let duplicate = GroundedExcerpt {
            locator: old.reference.locator.clone(),
            source: old.source.clone(),
            score: 1.0,
            text: "UNSUPPLIED source remainder".into(),
        };
        let mut fresh = duplicate.clone();
        if let super::super::PassageLocator::LocalNote(locator) = &mut fresh.locator {
            locator.chunk_index += 1;
        }
        fresh.text = "Fresh café🙂 context".into();
        let full = build_followup_prompt_context(
            std::slice::from_ref(&old),
            &[duplicate, fresh.clone()],
            6000,
        )
        .unwrap()
        .unwrap();
        assert_eq!(full.included_passages.len(), 2);
        assert_eq!(full.included_passages[0], old.reference);
        assert!(full.text.contains("[omitted source text]"));
        assert!(!full.text.contains("UNSUPPLIED"));
        let required = build_followup_prompt_context(std::slice::from_ref(&old), &[], 6000)
            .unwrap()
            .unwrap();
        for (case, budget) in [
            ("required only", required.text.len()),
            ("truncated optional passage", full.text.len() - 1),
        ] {
            let packed = build_followup_prompt_context(
                std::slice::from_ref(&old),
                std::slice::from_ref(&fresh),
                budget,
            )
            .unwrap()
            .unwrap();
            assert!(packed.text.len() <= budget, "{case}");
            assert_eq!(packed.included_passages[0], old.reference, "{case}");
        }

        let raw = super::super::passage_fixture().1;
        let matching = GroundedExcerpt {
            locator: old.reference.locator.clone(),
            source: old.source.clone(),
            score: 1.0,
            text: raw.into(),
        };
        let expanded = build_followup_prompt_context(
            std::slice::from_ref(&old),
            std::slice::from_ref(&matching),
            6000,
        )
        .unwrap()
        .unwrap();
        assert_eq!(expanded.sources, vec![old.source.clone()]);
        assert_eq!(expanded.included_passages.len(), 1);
        assert!(expanded.text.contains("Café🙂\nबीच\tend"));
        assert_eq!(
            expanded.included_passages[0].verified_spans(raw).unwrap(),
            ["Café🙂\nबीच\tend"]
        );

        let mut prefix = old.clone();
        prefix.reference.spans.truncate(1);
        prefix.passages.truncate(1);
        let required_prefix =
            build_followup_prompt_context(std::slice::from_ref(&prefix), &[], 6000)
                .unwrap()
                .unwrap();
        for (case, budget) in [
            ("required prefix only", required_prefix.text.len()),
            ("truncated expansion", expanded.text.len() - 1),
        ] {
            let packed = build_followup_prompt_context(
                std::slice::from_ref(&prefix),
                std::slice::from_ref(&matching),
                budget,
            )
            .unwrap()
            .unwrap();
            assert!(packed.text.len() <= budget, "{case}");
            assert_eq!(packed.included_passages.len(), 1, "{case}");
            let spans = packed.included_passages[0].verified_spans(raw).unwrap();
            assert!(spans[0].starts_with(&prefix.passages[0]), "{case}");
            assert!(packed.text.contains(&spans[0]), "{case}");
        }
        assert!(build_followup_prompt_context(&[old], &[], required.text.len() - 1).is_err());
    }
}
