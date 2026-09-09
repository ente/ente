use std::collections::HashSet;

use serde::{Deserialize, Serialize};
use url::Url;

use crate::config::{
    KNOWLEDGE_LICENSE_LABEL as LICENSE_LABEL, KNOWLEDGE_LICENSE_URL as LICENSE_URL,
    is_path_safe_component,
};

use super::{GroundedSource, RetrievalError, normalize_single_line};

const BEGIN_SENTINEL: &str = "----- BEGIN ENSU KNOWLEDGE SOURCES v1 -----";
const END_SENTINEL: &str = "----- END ENSU KNOWLEDGE SOURCES -----";
const MIXED_BEGIN_SENTINEL: &str = "----- BEGIN ENSU GROUNDED SOURCES v2 -----";
const MIXED_END_SENTINEL: &str = "----- END ENSU GROUNDED SOURCES -----";
const MIXED_SOURCES_PREFIX: &str = "Sources: ";
const LICENSE_HEADER: &str =
    "Adapted sources · CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/";
pub const MAX_GROUNDED_SOURCES: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SourceCitation {
    pub dataset_id: String,
    pub dataset_label: String,
    pub credit: String,
    pub title: String,
    pub source_url: String,
    pub license_label: String,
    pub license_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedAssistantText {
    pub text: String,
    pub citations: Vec<SourceCitation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedGroundedAssistantText {
    pub text: String,
    pub sources: Vec<GroundedSource>,
}

pub fn finalize_assistant_text(
    raw_assistant_text: &str,
    citations: &[SourceCitation],
) -> Result<String, RetrievalError> {
    if citations.len() > MAX_GROUNDED_SOURCES {
        return Err(RetrievalError::InvalidInput(
            "too many grounded sources".to_string(),
        ));
    }
    let assistant_text = neutralize_model_sentinels(raw_assistant_text.trim());
    if assistant_text.is_empty() || citations.is_empty() {
        return Ok(assistant_text);
    }
    let normalized = normalize_and_deduplicate(citations)?;
    Ok(format!(
        "{assistant_text}\n\n{}",
        format_footer(&normalized)
    ))
}

pub fn parse_assistant_text(stored_text: &str) -> ParsedAssistantText {
    let parsed = parse_grounded_assistant_text(stored_text);
    ParsedAssistantText {
        text: parsed.text,
        citations: parsed
            .sources
            .into_iter()
            .filter_map(|source| match source {
                GroundedSource::EnsuPack { citation } => Some(citation),
                GroundedSource::LocalNote { .. } => None,
            })
            .collect(),
    }
}

pub fn clean_assistant_text(stored_text: &str) -> String {
    parse_grounded_assistant_text(stored_text).text
}

pub fn finalize_grounded_assistant_text(
    raw_assistant_text: &str,
    sources: &[GroundedSource],
) -> Result<String, RetrievalError> {
    if sources.len() > MAX_GROUNDED_SOURCES {
        return Err(RetrievalError::InvalidInput(
            "too many grounded sources".to_string(),
        ));
    }
    let pack_citations = sources
        .iter()
        .map(|source| match source {
            GroundedSource::EnsuPack { citation } => Some(citation.clone()),
            GroundedSource::LocalNote { .. } => None,
        })
        .collect::<Option<Vec<_>>>();
    if let Some(citations) = pack_citations {
        return finalize_assistant_text(raw_assistant_text, &citations);
    }

    let assistant_text = neutralize_model_sentinels(raw_assistant_text.trim());
    if assistant_text.is_empty() || sources.is_empty() {
        return Ok(assistant_text);
    }
    let sources = normalize_grounded_sources(sources)?;
    if sources.is_empty() {
        return Ok(assistant_text);
    }
    let sources = serde_json::to_string(&sources)?;
    Ok(format!(
        "{assistant_text}\n\n{MIXED_BEGIN_SENTINEL}\n{MIXED_SOURCES_PREFIX}{sources}\n{MIXED_END_SENTINEL}"
    ))
}

pub fn parse_grounded_assistant_text(stored_text: &str) -> ParsedGroundedAssistantText {
    if let Some(parsed) = parse_mixed_assistant_text_inner(stored_text) {
        return parsed;
    }
    if let Some(parsed) = parse_assistant_text_inner(stored_text) {
        return ParsedGroundedAssistantText {
            text: parsed.text,
            sources: parsed
                .citations
                .into_iter()
                .map(|citation| GroundedSource::EnsuPack { citation })
                .collect(),
        };
    }
    ParsedGroundedAssistantText {
        text: stored_text.to_owned(),
        sources: Vec::new(),
    }
}

pub fn knowledge_source_chip_label(citations: &[SourceCitation]) -> Option<String> {
    source_chip_label(citations.iter().map(|citation| {
        (
            citation.dataset_id.as_str(),
            citation.dataset_label.as_str(),
        )
    }))
}

pub fn grounded_source_chip_labels(sources: &[GroundedSource]) -> Vec<String> {
    let packs = source_chip_label(sources.iter().filter_map(|source| match source {
        GroundedSource::EnsuPack { citation } => Some((
            citation.dataset_id.as_str(),
            citation.dataset_label.as_str(),
        )),
        GroundedSource::LocalNote { .. } => None,
    }));
    let notes = source_chip_label(sources.iter().filter_map(|source| {
        match source {
            GroundedSource::LocalNote { reference } => Some((
                reference.collection_id.as_str(),
                reference
                    .collection_label
                    .as_deref()
                    .unwrap_or("Your Notes"),
            )),
            GroundedSource::EnsuPack { .. } => None,
        }
    }));
    packs.into_iter().chain(notes).collect()
}

fn source_chip_label<'a>(sources: impl IntoIterator<Item = (&'a str, &'a str)>) -> Option<String> {
    let mut sources = sources.into_iter();
    let (first_id, label) = sources.next()?;
    let mut distinct = HashSet::from([first_id]);
    distinct.extend(sources.map(|(id, _)| id));
    let additional = distinct.len() - 1;
    if additional == 0 {
        Some(label.to_owned())
    } else {
        Some(format!("{label} +{additional}"))
    }
}

fn normalize_and_deduplicate(
    citations: &[SourceCitation],
) -> Result<Vec<SourceCitation>, RetrievalError> {
    let mut seen = HashSet::new();
    let mut normalized = Vec::with_capacity(citations.len());
    for citation in citations {
        let citation = normalize_citation(citation)?;
        let key = (citation.dataset_id.clone(), citation.source_url.clone());
        if !seen.insert(key) {
            continue;
        }
        normalized.push(citation);
    }
    Ok(normalized)
}

fn normalize_citation(citation: &SourceCitation) -> Result<SourceCitation, RetrievalError> {
    if !is_path_safe_component(&citation.dataset_id) {
        return Err(RetrievalError::InvalidInput(
            "citation dataset_id is not path-safe".to_string(),
        ));
    }
    let license_label = normalize_required(&citation.license_label, "license label")?;
    if license_label != LICENSE_LABEL || citation.license_url != LICENSE_URL {
        return Err(RetrievalError::InvalidInput(
            "citation must use the v1 CC BY-SA 4.0 license".to_string(),
        ));
    }
    validate_https_url(&citation.source_url, "source URL")?;
    Ok(SourceCitation {
        dataset_id: citation.dataset_id.clone(),
        dataset_label: normalize_required(&citation.dataset_label, "dataset label")?,
        credit: normalize_required(&citation.credit, "credit")?,
        title: normalize_required(&citation.title, "title")?,
        source_url: citation.source_url.clone(),
        license_label,
        license_url: citation.license_url.clone(),
    })
}

fn format_footer(citations: &[SourceCitation]) -> String {
    let mut output = String::new();
    output.push_str(BEGIN_SENTINEL);
    output.push('\n');
    output.push_str(LICENSE_HEADER);
    output.push('\n');
    for (index, citation) in citations.iter().enumerate() {
        if index > 0 {
            output.push('\n');
        }
        output.push_str(&format!("Source {}\n", index + 1));
        output.push_str(&format!("Dataset-ID: {}\n", citation.dataset_id));
        output.push_str(&format!("Dataset: {}\n", citation.dataset_label));
        output.push_str(&format!("Credit: {}\n", citation.credit));
        output.push_str(&format!("Title: {}\n", citation.title));
        output.push_str(&format!("URL: {}\n", citation.source_url));
        output.push_str(&format!("License: {}\n", citation.license_label));
        output.push_str(&format!("License-URL: {}\n", citation.license_url));
    }
    output.push_str(END_SENTINEL);
    output
}

fn normalize_grounded_sources(
    sources: &[GroundedSource],
) -> Result<Vec<GroundedSource>, RetrievalError> {
    let mut normalized = Vec::with_capacity(sources.len());
    let mut seen = HashSet::new();
    for source in sources {
        match source {
            GroundedSource::EnsuPack { citation } => {
                let citation = normalize_citation(citation)?;
                let key = format!(
                    "pack\u{0}{}\u{0}{}",
                    citation.dataset_id, citation.source_url
                );
                if seen.insert(key) {
                    normalized.push(GroundedSource::EnsuPack { citation });
                }
            }
            GroundedSource::LocalNote { reference } => {
                let reference = crate::notes::NoteSourceReference {
                    collection_id: reference.collection_id.clone(),
                    collection_label: reference
                        .collection_label
                        .as_deref()
                        .map(|label| normalize_required(label, "note collection label"))
                        .transpose()?,
                    document_id: reference.document_id.clone(),
                    indexed_revision: reference.indexed_revision.clone(),
                    title: normalize_required(&reference.title, "note title")?,
                    section: reference
                        .section
                        .as_deref()
                        .map(|section| normalize_required(section, "note section"))
                        .transpose()?,
                };
                reference
                    .validate()
                    .map_err(|error| RetrievalError::InvalidInput(error.to_string()))?;
                let key = format!(
                    "note\u{0}{}\u{0}{}\u{0}{}\u{0}{}\u{0}{}",
                    reference.collection_id,
                    reference.document_id,
                    reference.indexed_revision,
                    reference.title,
                    reference.section.as_deref().unwrap_or_default()
                );
                if seen.insert(key) {
                    normalized.push(GroundedSource::LocalNote { reference });
                }
            }
        }
    }
    Ok(normalized)
}

fn parse_mixed_assistant_text_inner(stored_text: &str) -> Option<ParsedGroundedAssistantText> {
    let candidate = stored_text.strip_suffix('\n').unwrap_or(stored_text);
    let separator = format!("\n\n{MIXED_BEGIN_SENTINEL}\n");
    let footer_start = candidate.rfind(&separator)?;
    let assistant_text = &candidate[..footer_start];
    if assistant_text.is_empty() {
        return None;
    }
    let footer = &candidate[footer_start + 2..];
    let mut lines = footer.split('\n');
    if lines.next()? != MIXED_BEGIN_SENTINEL {
        return None;
    }
    let sources_json = lines.next()?.strip_prefix(MIXED_SOURCES_PREFIX)?;
    if lines.next()? != MIXED_END_SENTINEL || lines.next().is_some() {
        return None;
    }
    let sources = serde_json::from_str::<Vec<GroundedSource>>(sources_json).ok()?;
    if sources.is_empty() || sources.len() > MAX_GROUNDED_SOURCES {
        return None;
    }
    let sources = normalize_grounded_sources(&sources).ok()?;
    (!sources.is_empty()).then(|| ParsedGroundedAssistantText {
        text: assistant_text.to_owned(),
        sources,
    })
}

fn parse_assistant_text_inner(stored_text: &str) -> Option<ParsedAssistantText> {
    let candidate = stored_text.strip_suffix('\n').unwrap_or(stored_text);
    let separator = format!("\n\n{BEGIN_SENTINEL}\n");
    let footer_start = candidate.rfind(&separator)?;
    let assistant_text = &candidate[..footer_start];
    if assistant_text.is_empty() {
        return None;
    }
    let footer = &candidate[footer_start + 2..];
    let citations = parse_footer(footer)?;
    Some(ParsedAssistantText {
        text: assistant_text.to_owned(),
        citations,
    })
}

fn parse_footer(footer: &str) -> Option<Vec<SourceCitation>> {
    let lines = footer.split('\n').collect::<Vec<_>>();
    if lines.first().copied()? != BEGIN_SENTINEL || lines.get(1).copied()? != LICENSE_HEADER {
        return None;
    }

    let mut cursor = 2;
    let mut number = 1;
    let mut citations = Vec::new();
    let mut seen = HashSet::new();
    loop {
        if lines.get(cursor).copied()? != format!("Source {number}") {
            return None;
        }
        cursor += 1;
        let dataset_id = parse_field(lines.get(cursor).copied()?, "Dataset-ID: ")?;
        cursor += 1;
        let dataset_label = parse_field(lines.get(cursor).copied()?, "Dataset: ")?;
        cursor += 1;
        let credit = parse_field(lines.get(cursor).copied()?, "Credit: ")?;
        cursor += 1;
        let title = parse_field(lines.get(cursor).copied()?, "Title: ")?;
        cursor += 1;
        let source_url = parse_field(lines.get(cursor).copied()?, "URL: ")?;
        cursor += 1;
        let license_label = parse_field(lines.get(cursor).copied()?, "License: ")?;
        cursor += 1;
        let license_url = parse_field(lines.get(cursor).copied()?, "License-URL: ")?;
        cursor += 1;

        if !is_path_safe_component(dataset_id)
            || !valid_stored_field(dataset_label)
            || !valid_stored_field(credit)
            || !valid_stored_field(title)
            || license_label != LICENSE_LABEL
            || license_url != LICENSE_URL
            || validate_https_url(source_url, "source URL").is_err()
            || !seen.insert((dataset_id, source_url))
        {
            return None;
        }
        citations.push(SourceCitation {
            dataset_id: dataset_id.to_owned(),
            dataset_label: dataset_label.to_owned(),
            credit: credit.to_owned(),
            title: title.to_owned(),
            source_url: source_url.to_owned(),
            license_label: license_label.to_owned(),
            license_url: license_url.to_owned(),
        });
        if citations.len() > MAX_GROUNDED_SOURCES {
            return None;
        }

        match lines.get(cursor).copied()? {
            END_SENTINEL if cursor + 1 == lines.len() => break,
            "" => {
                cursor += 1;
                number += 1;
            }
            _ => return None,
        }
    }
    (!citations.is_empty()).then_some(citations)
}

fn parse_field<'a>(line: &'a str, prefix: &str) -> Option<&'a str> {
    let value = line.strip_prefix(prefix)?;
    (!value.is_empty()).then_some(value)
}

fn valid_stored_field(value: &str) -> bool {
    !value.trim().is_empty() && !value.chars().any(char::is_control)
}

pub(super) fn normalize_required(value: &str, field: &str) -> Result<String, RetrievalError> {
    let normalized = normalize_single_line(value);
    if normalized.is_empty() {
        Err(RetrievalError::InvalidInput(format!(
            "citation {field} must not be empty"
        )))
    } else {
        Ok(normalized)
    }
}

fn validate_https_url(value: &str, field: &str) -> Result<(), RetrievalError> {
    if value.chars().any(char::is_control) {
        return Err(RetrievalError::InvalidInput(format!(
            "citation {field} contains a control character"
        )));
    }
    let url = Url::parse(value).map_err(|error| {
        RetrievalError::InvalidInput(format!("citation {field} is invalid: {error}"))
    })?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(RetrievalError::InvalidInput(format!(
            "citation {field} must be an HTTPS URL without credentials"
        )));
    }
    Ok(())
}

fn neutralize_model_sentinels(text: &str) -> String {
    text.lines()
        .map(|line| {
            if matches!(
                line,
                BEGIN_SENTINEL | END_SENTINEL | MIXED_BEGIN_SENTINEL | MIXED_END_SENTINEL
            ) {
                format!("[model] {line}")
            } else {
                line.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn citation(dataset_id: &str, dataset_label: &str, url: &str) -> SourceCitation {
        SourceCitation {
            dataset_id: dataset_id.to_owned(),
            dataset_label: dataset_label.to_owned(),
            credit: format!("{dataset_label} contributors"),
            title: "Example title".to_owned(),
            source_url: url.to_owned(),
            license_label: LICENSE_LABEL.to_owned(),
            license_url: LICENSE_URL.to_owned(),
        }
    }

    #[test]
    fn finalizes_and_parses_one_or_multiple_sources() {
        let first = citation(
            "simplewiki",
            "Simple English Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        let second = citation(
            "wikibooks",
            "Wikibooks",
            "https://en.wikibooks.org/wiki/Tea",
        );
        let finalized = finalize_assistant_text("An answer", &[first, second]).unwrap();
        assert!(!finalized.ends_with('\n'));

        let parsed = parse_assistant_text(&finalized);
        assert_eq!(parsed.text, "An answer");
        assert_eq!(parsed.citations.len(), 2);
        assert_eq!(parsed.citations[1].title, "Example title");
        assert_eq!(
            knowledge_source_chip_label(&parsed.citations).as_deref(),
            Some("Simple English Wikipedia +1")
        );
    }

    #[test]
    fn deduplicates_by_dataset_and_url_preserving_first_rank() {
        let mut first = citation(
            "simplewiki",
            "Simple English Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        let mut duplicate = first.clone();
        first.title = "First".to_owned();
        duplicate.title = "Second".to_owned();
        let finalized = finalize_assistant_text("Answer", &[first, duplicate]).unwrap();
        let parsed = parse_assistant_text(&finalized);
        assert_eq!(parsed.citations.len(), 1);
        assert_eq!(parsed.citations[0].title, "First");
    }

    #[test]
    fn normalizes_fields_and_neutralizes_model_sentinels() {
        let mut source = citation(
            "simplewiki",
            "Simple\n English  Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        source.title = "Title\twith\u{0000} controls".to_owned();
        let raw = format!("before\n{BEGIN_SENTINEL}\nafter\n{END_SENTINEL}");
        let finalized = finalize_assistant_text(&raw, &[source]).unwrap();
        assert!(finalized.starts_with("before\n[model] ----- BEGIN"));
        let parsed = parse_assistant_text(&finalized);
        assert_eq!(
            parsed.citations[0].dataset_label,
            "Simple English Wikipedia"
        );
        assert_eq!(parsed.citations[0].title, "Title with controls");
    }

    #[test]
    fn malformed_or_nonterminal_footers_remain_visible() {
        let source = citation(
            "simplewiki",
            "Simple English Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        let finalized = finalize_assistant_text("Answer", &[source]).unwrap();
        for malformed in [
            finalized.replace("Source 1", "Source 2"),
            finalized.replace("URL: https://", "URL: http://"),
            format!("{finalized}\nextra"),
            finalized.replace("License: CC BY-SA 4.0", "Unknown: value"),
        ] {
            let parsed = parse_assistant_text(&malformed);
            assert!(parsed.citations.is_empty());
            assert_eq!(parsed.text, malformed);
        }
    }

    #[test]
    fn accepts_one_optional_final_newline_and_never_writes_footer_only_text() {
        let source = citation(
            "simplewiki",
            "Simple English Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        assert_eq!(
            finalize_assistant_text("  ", std::slice::from_ref(&source)).unwrap(),
            ""
        );
        let finalized = finalize_assistant_text("Answer", &[source]).unwrap();
        assert_eq!(parse_assistant_text(&(finalized + "\n")).text, "Answer");
    }

    #[test]
    fn mixed_footer_round_trips_and_old_pack_apis_remain_compatible() {
        let pack = citation(
            "simplewiki",
            "Simple English Wikipedia",
            "https://simple.wikipedia.org/wiki/Example",
        );
        let sources = vec![
            GroundedSource::EnsuPack {
                citation: pack.clone(),
            },
            GroundedSource::LocalNote {
                reference: crate::notes::NoteSourceReference {
                    collection_id: "123e4567-e89b-12d3-a456-426614174000".to_string(),
                    collection_label: Some("InterestAreas".to_string()),
                    document_id: "folder/note.md".to_string(),
                    indexed_revision: "a".repeat(64),
                    title: "Local title".to_string(),
                    section: Some("Details".to_string()),
                },
            },
        ];
        let finalized = finalize_grounded_assistant_text("Grounded answer", &sources).unwrap();
        assert!(finalized.contains(MIXED_BEGIN_SENTINEL));
        let parsed = parse_grounded_assistant_text(&finalized);
        assert_eq!(parsed.text, "Grounded answer");
        assert_eq!(parsed.sources, sources);
        assert_eq!(clean_assistant_text(&finalized), "Grounded answer");

        let pack_view = parse_assistant_text(&finalized);
        assert_eq!(pack_view.text, "Grounded answer");
        assert_eq!(pack_view.citations, [pack]);
    }
}
