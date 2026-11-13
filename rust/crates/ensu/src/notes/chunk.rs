use super::document::PreparedNotesChunk;
use super::{
    NOTES_CHUNK_OVERLAP_UTF8_BYTES, NOTES_CHUNK_UTF8_BYTES, NOTES_HEADING_MAX_UTF8_BYTES,
    NotesError, is_valid_label,
};

const CHUNK_COMPACTION_THRESHOLD: usize = 1_024;

#[derive(Debug)]
struct DocumentGroup {
    section: Option<String>,
    text: String,
}

pub(super) fn prepare_chunks(
    document_id: &str,
    source: &str,
) -> Result<(String, Vec<PreparedNotesChunk>), NotesError> {
    let source = source.replace("\r\n", "\n").replace('\r', "\n");
    let mut title = None;
    let mut section = None;
    let mut group_lines = Vec::new();
    let mut groups = Vec::new();
    let mut fence = None;

    for line in source.lines() {
        match fence {
            Some((marker, count)) => {
                if is_closing_fence(line, marker, count) {
                    fence = None;
                }
            }
            None => {
                fence = opening_fence(line);
            }
        }
        if fence.is_none()
            && let Some((level, heading)) = atx_heading(line)
        {
            if heading.len() > NOTES_HEADING_MAX_UTF8_BYTES || !is_valid_label(&heading) {
                return Err(NotesError::InvalidInput(
                    "heading length or characters are invalid".to_string(),
                ));
            }
            flush_group(&mut groups, section.clone(), &mut group_lines);
            if level == 1 && title.is_none() {
                title = Some(heading);
                section = None;
            } else {
                section = Some(heading);
            }
            continue;
        }

        let line = line.trim_end();
        if line.is_empty() {
            if group_lines
                .last()
                .is_some_and(|line: &String| !line.is_empty())
            {
                group_lines.push(String::new());
            }
        } else {
            group_lines.push(line.to_string());
        }
    }
    flush_group(&mut groups, section, &mut group_lines);

    let title = title.unwrap_or_else(|| document_id.to_string());
    if groups.is_empty() {
        groups.push(DocumentGroup {
            section: None,
            text: title.clone(),
        });
    }

    let mut chunks = Vec::new();
    for group in groups {
        for text in split_group(&group.text) {
            chunks.push(PreparedNotesChunk {
                section: group.section.clone(),
                text,
            });
        }
    }
    if chunks.len() > CHUNK_COMPACTION_THRESHOLD {
        chunks = compact_chunks(chunks);
    }
    if chunks.is_empty() {
        return Err(NotesError::InvalidInput(
            "source document produced no chunks".to_string(),
        ));
    }
    Ok((title, chunks))
}

fn flush_group(groups: &mut Vec<DocumentGroup>, section: Option<String>, lines: &mut Vec<String>) {
    if let (Some(start), Some(end)) = (
        lines.iter().position(|line| !line.is_empty()),
        lines.iter().rposition(|line| !line.is_empty()),
    ) {
        groups.push(DocumentGroup {
            section,
            text: lines[start..=end].join("\n"),
        });
    } else if let Some(section) = section {
        groups.push(DocumentGroup {
            section: None,
            text: section,
        });
    }
    lines.clear();
}

fn append_chunk(chunks: &mut Vec<PreparedNotesChunk>, section: Option<String>, text: String) {
    if let Some(previous) = chunks.last_mut() {
        let separator = match section.as_deref() {
            Some(section) => format!("\n\n## {section}\n"),
            None => "\n\n".to_string(),
        };
        if previous
            .text
            .len()
            .checked_add(separator.len())
            .and_then(|size| size.checked_add(text.len()))
            .is_some_and(|size| size <= NOTES_CHUNK_UTF8_BYTES)
        {
            previous.text.push_str(&separator);
            previous.text.push_str(&text);
            if previous.section != section {
                previous.section = None;
            }
            return;
        }
    }
    chunks.push(PreparedNotesChunk { section, text });
}

fn compact_chunks(chunks: Vec<PreparedNotesChunk>) -> Vec<PreparedNotesChunk> {
    let mut compacted = Vec::new();
    for chunk in chunks {
        append_chunk(&mut compacted, chunk.section, chunk.text);
    }
    compacted
}

fn atx_heading(line: &str) -> Option<(usize, String)> {
    let leading_spaces = line.bytes().take_while(|byte| *byte == b' ').count();
    if leading_spaces > 3 {
        return None;
    }
    let line = &line[leading_spaces..];
    let level = line.bytes().take_while(|byte| *byte == b'#').count();
    if !(1..=6).contains(&level) {
        return None;
    }
    let remainder = &line[level..];
    if !remainder.is_empty() && !remainder.chars().next().is_some_and(char::is_whitespace) {
        return None;
    }
    let mut heading = remainder.trim().to_string();
    if let Some(separator) = heading.rfind(char::is_whitespace)
        && heading[separator..]
            .trim()
            .chars()
            .all(|character| character == '#')
    {
        heading.truncate(separator);
        heading = heading.trim_end().to_string();
    }
    let heading = heading.split_whitespace().collect::<Vec<_>>().join(" ");
    if heading.is_empty() {
        None
    } else {
        Some((level, heading))
    }
}

fn fence_candidate(line: &str) -> Option<&str> {
    let leading_spaces = line.bytes().take_while(|byte| *byte == b' ').count();
    (leading_spaces <= 3).then(|| &line[leading_spaces..])
}

fn opening_fence(line: &str) -> Option<(char, usize)> {
    let line = fence_candidate(line)?;
    let marker = line.chars().next()?;
    if !matches!(marker, '`' | '~') {
        return None;
    }
    let count = line
        .chars()
        .take_while(|character| *character == marker)
        .count();
    if count < 3 || (marker == '`' && line[count..].contains('`')) {
        return None;
    }
    Some((marker, count))
}

fn is_closing_fence(line: &str, marker: char, open_count: usize) -> bool {
    let Some(line) = fence_candidate(line) else {
        return false;
    };
    let count = line
        .chars()
        .take_while(|character| *character == marker)
        .count();
    count >= open_count && line[count..].trim().is_empty()
}

fn split_group(text: &str) -> Vec<String> {
    if text.len() <= NOTES_CHUNK_UTF8_BYTES {
        return vec![text.to_string()];
    }

    let boundaries = text
        .char_indices()
        .map(|(index, _)| index)
        .chain(std::iter::once(text.len()))
        .collect::<Vec<_>>();
    let mut chunks = Vec::new();
    let mut start = 0_usize;
    while start + 1 < boundaries.len() {
        let maximum_end_byte = boundaries[start].saturating_add(NOTES_CHUNK_UTF8_BYTES);
        let end = boundaries
            .partition_point(|boundary| *boundary <= maximum_end_byte)
            .saturating_sub(1)
            .max(start + 1);
        let chunk = text[boundaries[start]..boundaries[end]].trim();
        if !chunk.is_empty() {
            chunks.push(chunk.to_string());
        }
        if end + 1 == boundaries.len() {
            break;
        }
        let minimum_start_byte = boundaries[end].saturating_sub(NOTES_CHUNK_OVERLAP_UTF8_BYTES);
        let overlapped_start =
            boundaries.partition_point(|boundary| *boundary < minimum_start_byte);
        start = if overlapped_start > start {
            overlapped_start.min(end)
        } else {
            end
        };
    }
    chunks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cross_section_compaction_uses_document_level_metadata() {
        let compacted = compact_chunks(vec![
            PreparedNotesChunk {
                section: Some("First".to_string()),
                text: "first passage".to_string(),
            },
            PreparedNotesChunk {
                section: Some("Second".to_string()),
                text: "second passage".to_string(),
            },
        ]);

        assert_eq!(compacted.len(), 1);
        assert_eq!(compacted[0].section, None);
        assert!(compacted[0].text.contains("## Second\nsecond passage"));
    }
}
