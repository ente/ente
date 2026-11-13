use std::borrow::Cow;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextEncoding {
    Ascii,
    Utf8,
    Latin1,
    Windows1252,
}

pub(crate) fn decode(bytes: &[u8], encoding: TextEncoding) -> Option<Cow<'_, str>> {
    if encoding == TextEncoding::Utf8 || bytes.is_ascii() {
        return std::str::from_utf8(bytes).ok().map(Cow::Borrowed);
    }
    if encoding == TextEncoding::Ascii {
        return None;
    }
    const C1: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž',
        '\u{8f}', '\u{90}', '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}',
        'ž', 'Ÿ',
    ];
    Some(Cow::Owned(
        bytes
            .iter()
            .map(|&b| {
                if encoding == TextEncoding::Windows1252 && (0x80..=0x9f).contains(&b) {
                    C1[usize::from(b - 0x80)]
                } else {
                    char::from(b)
                }
            })
            .collect(),
    ))
}
