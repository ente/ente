pub fn strip_hidden_parts_text(text: &str) -> String {
    let input = text.replace('\0', "");
    let tags = ["<think>", "</think>", "<todo_list>", "</todo_list>"];
    let mut stack = Vec::new();
    let mut output = String::new();
    let mut remaining = input.as_str();
    while let Some((offset, tag)) = remaining.match_indices('<').find_map(|(offset, _)| {
        tags.iter()
            .find(|tag| {
                remaining[offset..]
                    .get(..tag.len())
                    .is_some_and(|candidate| candidate.eq_ignore_ascii_case(tag))
            })
            .map(|tag| (offset, *tag))
    }) {
        if stack.is_empty() {
            output.push_str(&remaining[..offset]);
        }
        let closing = tag.starts_with("</");
        let name = &tag[if closing { 2 } else { 1 }..tag.len() - 1];
        if !closing {
            stack.push(name);
        } else if stack.last() == Some(&name) {
            stack.pop();
        }
        remaining = &remaining[offset + tag.len()..];
    }
    if stack.is_empty() {
        output.push_str(remaining);
    }
    output
        .trim_matches(|ch| {
            matches!(ch, '\u{0009}'..='\u{000D}' | '\u{0020}' | '\u{00A0}' |
                '\u{1680}' | '\u{2000}'..='\u{200A}' | '\u{2028}' | '\u{2029}' |
                '\u{202F}' | '\u{205F}' | '\u{3000}' | '\u{FEFF}')
        })
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_hidden_parts_preserving_visible_text() {
        for (name, input, expected) in [
            ("plain_unicode", " माया owns SQLite. ", "माया owns SQLite."),
            (
                "closed_reasoning",
                "<think>Upload the data.</think>Keep data offline.",
                "Keep data offline.",
            ),
            (
                "interrupted_reasoning",
                "Visible fact.<THINK>Unfinished private reasoning",
                "Visible fact.",
            ),
            (
                "control_block",
                "<todo_list>Invent a purchase.</todo_list>No purchase approved.",
                "No purchase approved.",
            ),
            (
                "nested_blocks",
                "नमस्ते <ThInK>outer<THINK>inner</think><TODO_LIST>task</todo_list>hidden</tHiNk>Visible",
                "नमस्ते Visible",
            ),
            (
                "mismatched_close",
                "Before<think>hidden</todo_list>still hidden",
                "Before",
            ),
            ("nul", "\0Safe\0 text", "Safe text"),
            (
                "unknown_markup",
                "<example>Keep this</example>",
                "<example>Keep this</example>",
            ),
            (
                "multiple_blocks",
                "A<think>x</think>B<todo_list>y</todo_list>C",
                "ABC",
            ),
        ] {
            assert_eq!(strip_hidden_parts_text(input), expected, "{name}");
        }
    }
}
