use std::ops::Range;

use super::{Result, VoiceError};

fn utf16_range(text: &str, start: u32, end: u32) -> Result<Range<usize>> {
    if start > end {
        return Err(VoiceError::InvalidTextRange);
    }
    let mut units = 0_u32;
    let mut from = None;
    for (byte, character) in text
        .char_indices()
        .chain(std::iter::once((text.len(), '\0')))
    {
        if units == start {
            from = Some(byte);
        }
        if units == end {
            return Ok(from.ok_or(VoiceError::InvalidTextRange)?..byte);
        }
        units = units
            .checked_add(character.len_utf16() as u32)
            .ok_or(VoiceError::InvalidTextRange)?;
    }
    Err(VoiceError::InvalidTextRange)
}

fn left_edge(text: &str) -> Option<char> {
    text.chars()
        .rev()
        .find(|c| {
            !regex::regex!(r"\A[\p{M}\p{Join_Control}]\z").is_match(c.encode_utf8(&mut [0; 4]))
        })
        .or_else(|| text.chars().next())
}

pub(crate) fn transcript_separator(left: &str, right: &str) -> &'static str {
    fn unspaced(c: char) -> bool {
        matches!(c as u32, 0x3040..=0x30ff | 0x3400..=0x9fff | 0x20000..=0x3134f)
    }
    match (left_edge(left), right.chars().next()) {
        (Some(a), Some(b))
            if !a.is_whitespace() && !b.is_whitespace() && !unspaced(a) && !unspaced(b) =>
        {
            " "
        }
        _ => "",
    }
}

fn boundary_separator(left: &str, right: &str) -> &'static str {
    fn opening(c: char) -> bool {
        matches!(c, '¿' | '¡')
            || regex::regex!(r"\A[\p{Ps}\p{Pi}]\z").is_match(c.encode_utf8(&mut [0; 4]))
    }
    fn closing(c: char) -> bool {
        matches!(
            c,
            '.' | ','
                | '!'
                | '?'
                | ':'
                | ';'
                | '…'
                | '。'
                | '，'
                | '！'
                | '？'
                | '：'
                | '；'
                | '、'
                | '।'
                | '॥'
                | '؟'
                | '؛'
                | '،'
                | '%'
                | '‰'
                | '‱'
                | '٪'
                | '؉'
                | '؊'
                | '°'
        ) || regex::regex!(r"\A[\p{Pe}\p{Pf}]\z").is_match(c.encode_utf8(&mut [0; 4]))
    }
    fn emoji(c: char) -> bool {
        regex::regex!(r"\A\p{Extended_Pictographic}\z").is_match(c.encode_utf8(&mut [0; 4]))
    }

    let separator = transcript_separator(left, right);
    let (Some(a), Some(b)) = (left_edge(left), right.chars().next()) else {
        return separator;
    };
    if separator.is_empty()
        || opening(a)
        || closing(b)
        || emoji(a)
        || emoji(b)
        || matches!(a, '#' | '@' | '_' | '/' | '\\' | '-' | '+' | '−')
    {
        return "";
    }

    if regex::regex!(r"\A\p{Sc}\z").is_match(a.encode_utf8(&mut [0; 4]))
        && !left.rsplit_once(a).is_some_and(|(before, _)| {
            before
                .trim_end()
                .chars()
                .next_back()
                .is_some_and(char::is_numeric)
        })
    {
        return "";
    }
    if matches!(a, '\'' | '"')
        && left_edge(left.trim_end_matches(['\'', '"']))
            .is_none_or(|c| c.is_whitespace() || opening(c))
    {
        return "";
    }
    if matches!(b, '\'' | '"')
        && right
            .trim_start_matches(['\'', '"'])
            .chars()
            .next()
            .is_none_or(|c| c.is_whitespace() || closing(c))
    {
        return "";
    }
    separator
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ComposerAnchor {
    pub destination: String,
    pub revision: u64,
    pub start_utf16: u32,
    pub end_utf16: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceInsertion {
    pub anchor: ComposerAnchor,
    pub text: String,
}

pub fn preview_insertion(
    text: &str,
    anchor: &ComposerAnchor,
    voice_text: &str,
) -> Result<(String, u32)> {
    let range = utf16_range(text, anchor.start_utf16, anchor.end_utf16)?;
    if voice_text.is_empty() {
        return Ok((text.to_owned(), anchor.end_utf16));
    }
    let before = &text[..range.start];
    let after = &text[range.end..];
    let prefix = boundary_separator(before, voice_text);
    let suffix = boundary_separator(voice_text, after);
    let caret = before.encode_utf16().count()
        + prefix.encode_utf16().count()
        + voice_text.encode_utf16().count()
        + suffix.encode_utf16().count();
    Ok((
        format!("{before}{prefix}{voice_text}{suffix}{after}"),
        caret as u32,
    ))
}

#[derive(Debug, Default)]
pub struct ComposerTransfer {
    applied: bool,
}

impl ComposerTransfer {
    pub fn apply(
        &mut self,
        insertion: &VoiceInsertion,
        destination: &str,
        revision: &mut u64,
        text: &mut String,
        foreground: bool,
        composing: bool,
    ) -> Result<u32> {
        if self.applied {
            return Err(VoiceError::RevisionConflict);
        }
        if !foreground || insertion.anchor.destination != destination {
            return Err(VoiceError::RevisionConflict);
        }
        if composing {
            return Err(VoiceError::PendingEdit);
        }
        if insertion.text.trim().is_empty() {
            return Err(VoiceError::InvalidState);
        }
        let mut anchor = insertion.anchor.clone();
        if anchor.revision != *revision {
            anchor.start_utf16 = text.encode_utf16().count() as u32;
            anchor.end_utf16 = anchor.start_utf16;
        }
        let (rendered, caret) = preview_insertion(text, &anchor, &insertion.text)?;
        *text = rendered;
        *revision += 1;
        self.applied = true;
        Ok(caret)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn insertion(start: u32, end: u32, text: &str) -> VoiceInsertion {
        VoiceInsertion {
            text: text.into(),
            anchor: ComposerAnchor {
                destination: "chat".into(),
                revision: 7,
                start_utf16: start,
                end_utf16: end,
            },
        }
    }

    #[test]
    fn selected_text_is_replaced_once_and_duplicate_transfers_are_rejected() {
        let mut owner = ComposerTransfer::default();
        let mut text = "  meet Friday\n".to_owned();
        let mut revision = 7;
        let insert = insertion(7, 13, "Saturday");
        owner
            .apply(&insert, "chat", &mut revision, &mut text, true, false)
            .unwrap();
        assert_eq!(text, "  meet Saturday\n");
        assert_eq!(
            owner.apply(
                &insert,
                "different-chat",
                &mut revision,
                &mut text,
                false,
                false
            ),
            Err(VoiceError::RevisionConflict)
        );
        assert_eq!(revision, 8);
        assert_eq!(text, "  meet Saturday\n");
    }

    #[test]
    fn changed_draft_appends_once_but_a_different_chat_is_rejected() {
        let mut owner = ComposerTransfer::default();
        let mut text = "My edited draft".to_owned();
        let mut revision = 8;
        let insert = insertion(0, 0, "hello");
        for (destination, foreground, composing) in [
            ("another-chat", true, false),
            ("chat", false, false),
            ("chat", true, true),
        ] {
            assert!(
                owner
                    .apply(
                        &insert,
                        destination,
                        &mut revision,
                        &mut text,
                        foreground,
                        composing
                    )
                    .is_err()
            );
        }
        assert_eq!(text, "My edited draft");
        owner
            .apply(&insert, "chat", &mut revision, &mut text, true, false)
            .unwrap();
        assert_eq!(text, "My edited draft hello");
        assert_eq!(
            owner.apply(&insert, "chat", &mut revision, &mut text, true, false),
            Err(VoiceError::RevisionConflict)
        );
        assert_eq!(text, "My edited draft hello");
        assert_eq!(revision, 9);
    }

    #[test]
    fn utf16_ranges_preserve_text_and_reject_split_surrogates() {
        for text in ["👩🏽‍💻", "e\u{301}", "कि", "क्ष"] {
            let end = text.encode_utf16().count() as u32;
            assert_eq!(utf16_range(text, 0, end).unwrap(), 0..text.len());
            for (byte, character) in text.char_indices() {
                let start = text[..byte].encode_utf16().count() as u32;
                assert_eq!(
                    utf16_range(text, start, start + character.len_utf16() as u32).unwrap(),
                    byte..byte + character.len_utf8()
                );
                if character.len_utf16() == 2 {
                    assert_eq!(
                        utf16_range(text, start, start + 1),
                        Err(VoiceError::InvalidTextRange)
                    );
                    assert_eq!(
                        utf16_range(text, start + 1, end),
                        Err(VoiceError::InvalidTextRange)
                    );
                }
            }
        }
        for (start, end) in [(2, 1), (0, 9), (9, 9)] {
            assert_eq!(
                utf16_range("hello", start, end),
                Err(VoiceError::InvalidTextRange)
            );
        }
        assert_eq!(utf16_range("你好 مرحبا", 0, 2).unwrap(), 0..6);
    }

    #[test]
    fn insertion_preserves_whitespace_and_script_boundaries() {
        assert_eq!(boundary_separator("hello", "world"), " ");
        assert_eq!(boundary_separator("你好", "世界"), "");
        assert_eq!(boundary_separator("hello\n", "world"), "");
        assert_eq!(boundary_separator("مرحبا", "بك"), " ");
        assert_eq!(boundary_separator("कि", "Saturday"), " ");
        assert_eq!(boundary_separator("क्‍", "Saturday"), " ");
        assert_eq!(boundary_separator("cafe\u{301}", "Saturday"), " ");
        assert_eq!(boundary_separator("你\u{301}", "好"), "");
        assert_eq!(boundary_separator("👩🏽‍💻", "Saturday"), "");
        assert_eq!(boundary_separator("Done.", "Next"), " ");
        assert_eq!(boundary_separator("है।", "बैठक"), " ");
        assert_eq!(boundary_separator("نعم؟", "موعد"), " ");
        assert_eq!(boundary_separator("안녕", "친구"), " ");
        for (draft, dictated, expected) in [
            ("Charge 20%", "more tomorrow", "Charge 20% more tomorrow"),
            ("Charge 20‰", "extra", "Charge 20‰ extra"),
            ("Rotate 90°", "clockwise", "Rotate 90° clockwise"),
            ("Budget 20€", "today", "Budget 20€ today"),
            ("Budget 20 €", "today", "Budget 20 € today"),
            ("نسبة 20٪", "زيادة", "نسبة 20٪ زيادة"),
            ("Notes (draft)", "hello", "Notes (draft) hello"),
            ("Budget", "$20.", "Budget $20."),
            ("Budget €", "20", "Budget €20"),
            ("Budget -", "20", "Budget -20"),
            ("Change:", "-5 percent.", "Change: -5 percent."),
            ("Say", "\"hello.\"", "Say \"hello.\""),
            (
                "Say \"hello.\"",
                "Then leave.",
                "Say \"hello.\" Then leave.",
            ),
            ("Say \"", "hello", "Say \"hello"),
            ("Notes (", "draft", "Notes (draft"),
            ("Notes (\"", "draft", "Notes (\"draft"),
            ("hello", ", world", "hello, world"),
            ("Notes (draft", ")", "Notes (draft)"),
            ("Say \"hello", "\"", "Say \"hello\""),
        ] {
            let end = draft.encode_utf16().count() as u32;
            let insert = insertion(end, end, dictated);
            let (preview, caret) = preview_insertion(draft, &insert.anchor, dictated).unwrap();
            assert_eq!(preview, expected);
            let mut text = draft.to_owned();
            let mut revision = 7;
            assert_eq!(
                ComposerTransfer::default()
                    .apply(&insert, "chat", &mut revision, &mut text, true, false)
                    .unwrap(),
                caret
            );
            assert_eq!(text, expected);
            let anchor = insertion(0, 0, draft).anchor;
            assert_eq!(
                preview_insertion(dictated, &anchor, draft).unwrap().0,
                expected
            );
        }
    }
}
