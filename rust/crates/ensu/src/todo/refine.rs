//! Rule-based repairs to the model's To Do calls before they are applied.
//!
//! Small models often quote a deadline a word short ("5" for "at 5"), run it
//! into the next clause ("tomorrow and call Lee at 4 PM"), pass "the second
//! one" as words instead of a list position, or leave out the list filter.
//! These repairs only use the user's message and the length of the list just
//! shown, so they hold for any wording rather than for particular cases.

use chrono::NaiveDateTime;

use super::{COMPLETE_TOOL, LIST_TOOL, ListFilter, SAVE_TOOL, timing};
use crate::llm::{ToolCall, ToolValue};

/// Longest deadline phrase considered, in words.
const MAX_DEADLINE_WORDS: usize = 8;

/// Words that end a clause, so a deadline never reaches into the next task.
const CLAUSE_WORDS: &[&str] = &["and", "then", "also", "but", "&", "plus"];

/// Words that say nothing about which task is meant beyond its position.
const VAGUE_TASK_WORDS: &[&str] = &[
    "the", "one", "ones", "that", "this", "it", "task", "item", "number", "no", "#", "last",
];

const ORDINALS: &[(&str, &str, usize)] = &[
    ("first", "1st", 1),
    ("second", "2nd", 2),
    ("third", "3rd", 3),
    ("fourth", "4th", 4),
    ("fifth", "5th", 5),
    ("sixth", "6th", 6),
    ("seventh", "7th", 7),
    ("eighth", "8th", 8),
    ("ninth", "9th", 9),
    ("tenth", "10th", 10),
];

/// Calls as they should be applied. `user_text` is the message the calls
/// answer, `shown` the number of tasks in the list the previous reply showed
/// (0 if it showed none), and `now` the local time deadlines resolve against.
pub fn refine_calls(
    calls: &[ToolCall],
    user_text: &str,
    shown: usize,
    now: NaiveDateTime,
) -> Vec<ToolCall> {
    calls
        .iter()
        .map(|call| {
            let mut call = call.clone();
            match call.name.as_str() {
                SAVE_TOOL => {
                    let resolve = |quote: &str| timing::parse_deadline(quote, now).map(|d| d.at);
                    if let Some(when) = call.text("when")
                        && let Some(better) =
                            deadline_phrase(user_text, when, call.text("title"), now)
                        && resolve(better) != resolve(when)
                    {
                        call.arguments
                            .insert("when".into(), ToolValue::Text(better.to_owned()));
                    }
                    // A "deadline" with no time in it ("the pharmacy") was
                    // never one; one the parser can't read stays, so the
                    // reply can say so.
                    if call
                        .text("when")
                        .is_some_and(|when| resolve(when).is_none() && !timing::mentions_time(when))
                    {
                        call.arguments.remove("when");
                    }
                }
                LIST_TOOL => {
                    if call
                        .text("filter")
                        .and_then(ListFilter::from_name)
                        .is_none()
                    {
                        call.arguments
                            .insert("filter".into(), ToolValue::Text("open".into()));
                    }
                }
                COMPLETE_TOOL => {
                    // A position in the message wins over a number the model
                    // guessed while quoting the position as the task.
                    let task = call.text("task");
                    if shown > 0
                        && (call.integer("number").is_none() || task.is_some())
                        && task.is_none_or(is_positional)
                        && let Some(number) = position(user_text, shown)
                    {
                        call.arguments.remove("task");
                        call.arguments
                            .insert("number".into(), ToolValue::Integer(number as i64));
                    }
                }
                _ => {}
            }
            call
        })
        .collect()
}

#[derive(Debug)]
struct Word<'a> {
    /// The word without surrounding punctuation, as written.
    text: &'a str,
    start: usize,
    end: usize,
    clause: usize,
}

fn is_edge_punctuation(c: char) -> bool {
    matches!(
        c,
        ',' | ';' | '.' | '!' | '?' | ':' | '"' | '\'' | '(' | ')' | '“' | '”' | '‘' | '’'
    )
}

/// The message's words with their byte ranges and clause numbers. Clauses end
/// at line breaks, at sentence or list punctuation, and at joining words such
/// as "and".
fn words(text: &str) -> Vec<Word<'_>> {
    let mut out = Vec::new();
    let mut clause = 0;
    let mut start = None;
    for (i, c) in text
        .char_indices()
        .chain(std::iter::once((text.len(), '\n')))
    {
        if !c.is_whitespace() {
            start.get_or_insert(i);
            continue;
        }
        if let Some(s) = start.take() {
            let raw = &text[s..i];
            let leading = raw.len() - raw.trim_start_matches(is_edge_punctuation).len();
            let core = raw.trim_matches(is_edge_punctuation);
            let ends_clause = raw
                .trim_end_matches(['"', '\'', ')', '”', '’'])
                .ends_with([',', ';', '.', '!', '?', ':']);
            let separator = core.is_empty() || matches!(core, "-" | "*" | "•");
            if separator || CLAUSE_WORDS.contains(&core.to_lowercase().as_str()) {
                clause += 1;
            } else {
                out.push(Word {
                    text: core,
                    start: s + leading,
                    end: s + leading + core.len(),
                    clause,
                });
                if ends_clause {
                    clause += 1;
                }
            }
        }
        if c == '\n' {
            clause += 1;
        }
    }
    out
}

/// The longest phrase of the user's message that the deadline parser accepts
/// and that overlaps `quote`, within the one clause that holds this task.
/// `None` when the quote can't be found or nothing nearby parses.
fn deadline_phrase<'a>(
    user_text: &'a str,
    quote: &str,
    title: Option<&str>,
    now: NaiveDateTime,
) -> Option<&'a str> {
    let at = user_text.find(quote).or_else(|| {
        let lower = user_text.to_lowercase();
        (lower.len() == user_text.len())
            .then(|| lower.find(&quote.to_lowercase()))
            .flatten()
    })?;
    let (quote_start, quote_end) = (at, at + quote.len());
    let words = words(user_text);
    let overlapping: Vec<usize> = (0..words.len())
        .filter(|&i| words[i].start < quote_end && words[i].end > quote_start)
        .collect();
    let mut clauses: Vec<usize> = overlapping.iter().map(|&i| words[i].clause).collect();
    clauses.dedup();
    // Clauses the quote touches that hold a deadline, best first: the one
    // naming the most title words, then the earliest.
    let found: Vec<(usize, (usize, usize))> = clauses
        .iter()
        .filter_map(|&clause| {
            let touched: Vec<usize> = overlapping
                .iter()
                .copied()
                .filter(|&i| words[i].clause == clause)
                .collect();
            longest_deadline(user_text, &words, clause, &touched, now).map(|span| (clause, span))
        })
        .collect();
    let scores: Vec<usize> = found
        .iter()
        .map(|(clause, _)| title_score(&words, *clause, title))
        .collect();
    let best = scores.iter().copied().max()?;
    let (_, (start, end)) = found[scores.iter().position(|&score| score == best)?];
    Some(&user_text[words[start].start..words[end].end])
}

/// The longest phrase in `clause` that overlaps the `touched` words and
/// parses as a deadline, as first and last word indices.
fn longest_deadline(
    user_text: &str,
    words: &[Word],
    clause: usize,
    touched: &[usize],
    now: NaiveDateTime,
) -> Option<(usize, usize)> {
    let (first, last) = (*touched.first()?, *touched.last()?);
    let clause_words: Vec<usize> = (0..words.len())
        .filter(|&i| words[i].clause == clause)
        .collect();
    let (clause_start, clause_end) = (*clause_words.first()?, *clause_words.last()?);
    let mut best: Option<(usize, usize)> = None;
    for start in clause_start..=last {
        for end in start.max(first)..=clause_end {
            let len = end - start + 1;
            if len > MAX_DEADLINE_WORDS {
                break;
            }
            if best.is_some_and(|(s, e)| e - s + 1 >= len) {
                continue;
            }
            let phrase = &user_text[words[start].start..words[end].end];
            if timing::parse_deadline(phrase, now).is_some() {
                best = Some((start, end));
            }
        }
    }
    best
}

/// How many of the title's words `clause` contains.
fn title_score(words: &[Word], clause: usize, title: Option<&str>) -> usize {
    let title_words: Vec<String> = title
        .unwrap_or_default()
        .split_whitespace()
        .map(|word| word.trim_matches(is_edge_punctuation).to_lowercase())
        .filter(|word| word.chars().count() >= 3)
        .collect();
    words
        .iter()
        .filter(|word| word.clause == clause)
        .filter(|word| title_words.contains(&word.text.to_lowercase()))
        .count()
}

fn ordinal(word: &str) -> Option<usize> {
    ORDINALS
        .iter()
        .find(|(name, short, _)| word == *name || word == *short)
        .map(|(_, _, n)| *n)
}

/// Lowercased words without edge punctuation or a trailing "'s".
fn plain_words(text: &str) -> Vec<String> {
    text.split_whitespace()
        .map(|word| {
            let word = word.trim_matches(is_edge_punctuation).to_lowercase();
            word.strip_suffix("'s")
                .or_else(|| word.strip_suffix("’s"))
                .map_or_else(|| word.clone(), str::to_owned)
        })
        .collect()
}

/// True when a task reference picks a list item by position: it names
/// nothing but a position ("second one"), or points at one ("the first one's
/// done now", "the last task"). An ordinal describing the task itself ("the
/// 2nd draft") doesn't count.
fn is_positional(task: &str) -> bool {
    let words = plain_words(task);
    let vague = words.iter().all(|word| {
        word.is_empty()
            || VAGUE_TASK_WORDS.contains(&word.as_str())
            || ordinal(word).is_some()
            || word.trim_start_matches('#').parse::<usize>().is_ok()
    });
    let points = words.iter().enumerate().any(|(i, word)| {
        let next = words.get(i + 1);
        let ordinal_item = (ordinal(word).is_some() || word == "last")
            && next.is_none_or(|next| {
                matches!(next.as_str(), "one" | "ones" | "task" | "item" | "thing")
            });
        // "number five", "no. 3", "item 2", "#4".
        let numbered_item = matches!(word.as_str(), "number" | "no" | "item")
            && next.is_some_and(|next| {
                next.parse::<usize>().is_ok() || timing::number_word(next).is_some()
            });
        let hashed = word
            .strip_prefix('#')
            .is_some_and(|n| n.parse::<usize>().is_ok());
        ordinal_item || numbered_item || hashed
    });
    vague || points
}

/// The list position the user's message points at: an ordinal ("the second
/// one"), "the last one", or "number 3" / "#3". `None` when there is none or
/// it is outside the list just shown.
fn position(user_text: &str, shown: usize) -> Option<usize> {
    let words: Vec<String> = words(user_text)
        .iter()
        .map(|word| word.text.to_lowercase())
        .collect();
    let found = words.iter().enumerate().find_map(|(i, word)| {
        if let Some(n) = ordinal(word) {
            return Some(n);
        }
        if word == "last" {
            return Some(shown);
        }
        if let Some(n) = word.strip_prefix('#').and_then(|n| n.parse().ok()) {
            return Some(n);
        }
        let numbered = i > 0 && matches!(words[i - 1].as_str(), "number" | "no" | "item" | "task");
        numbered
            .then(|| {
                word.parse()
                    .ok()
                    .or_else(|| timing::number_word(word).and_then(|n| usize::try_from(n).ok()))
            })
            .flatten()
    })?;
    (1..=shown).contains(&found).then_some(found)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn now() -> NaiveDateTime {
        chrono::NaiveDate::from_ymd_opt(2026, 11, 12)
            .unwrap()
            .and_hms_opt(14, 30, 0)
            .unwrap()
    }

    fn call(name: &str, arguments: &[(&str, ToolValue)]) -> ToolCall {
        ToolCall {
            name: name.into(),
            arguments: arguments
                .iter()
                .map(|(key, value)| ((*key).to_owned(), value.clone()))
                .collect::<BTreeMap<_, _>>(),
        }
    }

    fn text(value: &str) -> ToolValue {
        ToolValue::Text(value.into())
    }

    fn when_after(user: &str, title: &str, when: &str) -> Option<String> {
        let calls = [call(
            SAVE_TOOL,
            &[("title", text(title)), ("when", text(when))],
        )];
        refine_calls(&calls, user, 0, now())[0]
            .text("when")
            .map(str::to_owned)
    }

    #[test]
    fn deadlines_widen_to_the_whole_phrase() {
        assert_eq!(
            when_after("Ring the vet at 4", "Ring the vet", "4").as_deref(),
            Some("at 4")
        );
        assert_eq!(
            when_after(
                "Pay the gas bill by 3 PM today please",
                "Pay gas bill",
                "today"
            )
            .as_deref(),
            Some("by 3 PM today")
        );
        assert_eq!(
            when_after(
                "Order a cake for the 9th of January",
                "Order cake",
                "January"
            )
            .as_deref(),
            Some("for the 9th of January")
        );
    }

    #[test]
    fn deadlines_stop_at_the_clause_naming_the_task() {
        assert_eq!(
            when_after(
                "Wash the car Friday and ring Sam at 7 PM",
                "Ring Sam",
                "Friday and ring Sam at 7 PM"
            )
            .as_deref(),
            Some("at 7 PM")
        );
        assert_eq!(
            when_after(
                "Wash the car Friday and ring Sam at 7 PM",
                "Wash the car",
                "Friday and ring Sam at 7 PM"
            )
            .as_deref(),
            Some("Friday")
        );
        assert_eq!(
            when_after(
                "Meeting at 2pm on Tuesday, have to prepare",
                "Prepare for meeting",
                "Tuesday, have to prepare"
            )
            .as_deref(),
            Some("at 2pm on Tuesday")
        );
    }

    #[test]
    fn unparseable_or_missing_deadlines_are_left_alone() {
        assert_eq!(
            when_after("Fix the fence this weekend", "Fix fence", "this weekend").as_deref(),
            Some("this weekend")
        );
        assert_eq!(
            when_after("Fix the fence tomorrow", "Fix fence", "next month").as_deref(),
            Some("next month")
        );
    }

    #[test]
    fn positions_become_list_numbers() {
        let complete = |task: &str| [call(COMPLETE_TOOL, &[("task", text(task))])];
        let refined = refine_calls(&complete("second one"), "The second one is done", 3, now());
        assert_eq!(refined[0].integer("number"), Some(2));
        assert_eq!(refined[0].text("task"), None);
        let refined = refine_calls(&complete("one"), "Finished the last one", 4, now());
        assert_eq!(refined[0].integer("number"), Some(4));
        let refined = refine_calls(&complete("it"), "Tick off number 2", 3, now());
        assert_eq!(refined[0].integer("number"), Some(2));
        // The model quoted the whole message.
        let message = "The first one's done now";
        let refined = refine_calls(&complete(message), message, 3, now());
        assert_eq!(refined[0].integer("number"), Some(1));
        // ...or also guessed a number.
        let message = "Cross off number five";
        let calls = [call(
            COMPLETE_TOOL,
            &[("task", text(message)), ("number", ToolValue::Integer(1))],
        )];
        let refined = refine_calls(&calls, message, 6, now());
        assert_eq!(refined[0].integer("number"), Some(5));
        // A number alone is kept.
        let calls = [call(COMPLETE_TOOL, &[("number", ToolValue::Integer(2))])];
        let refined = refine_calls(&calls, "Tick off the third", 6, now());
        assert_eq!(refined[0].integer("number"), Some(2));
    }

    #[test]
    fn deadlines_without_any_time_are_dropped() {
        assert_eq!(
            when_after("Swing by the pharmacy", "Pharmacy", "the pharmacy"),
            None
        );
        assert_eq!(
            when_after("Add milk to my to-do list", "Milk", "to-do"),
            None
        );
        // Real deadlines the parser can't read stay, so the reply can say so.
        assert_eq!(
            when_after(
                "Plant bulbs sometime in March",
                "Plant bulbs",
                "sometime in March"
            )
            .as_deref(),
            Some("sometime in March")
        );
        assert_eq!(
            when_after("Call Kim at quarter-past", "Call Kim", "at quarter-past 4").as_deref(),
            Some("at quarter-past 4")
        );
    }

    #[test]
    fn ordinals_describing_a_task_are_not_positions() {
        let message = "Finished the 2nd draft of the essay";
        let calls = [call(
            COMPLETE_TOOL,
            &[("task", text("2nd draft of the essay"))],
        )];
        let refined = refine_calls(&calls, message, 3, now());
        assert_eq!(refined[0].text("task"), Some("2nd draft of the essay"));
        assert_eq!(refined[0].integer("number"), None);
    }

    #[test]
    fn positions_need_a_list_and_a_vague_task() {
        let complete = |task: &str| [call(COMPLETE_TOOL, &[("task", text(task))])];
        // No list shown.
        let refined = refine_calls(&complete("second one"), "The second one is done", 0, now());
        assert_eq!(refined[0].text("task"), Some("second one"));
        // Outside the list.
        let refined = refine_calls(&complete("fifth"), "The fifth one is done", 3, now());
        assert_eq!(refined[0].integer("number"), None);
        // A named task stays named, even with an ordinal nearby.
        let refined = refine_calls(
            &complete("milk"),
            "First thing, I bought the milk",
            3,
            now(),
        );
        assert_eq!(refined[0].text("task"), Some("milk"));
    }

    #[test]
    fn lists_default_to_open_tasks() {
        let refined = refine_calls(&[call(LIST_TOOL, &[])], "What's on my list?", 0, now());
        assert_eq!(refined[0].text("filter"), Some("open"));
        let refined = refine_calls(
            &[call(LIST_TOOL, &[("filter", text("overdue"))])],
            "What's overdue?",
            0,
            now(),
        );
        assert_eq!(refined[0].text("filter"), Some("overdue"));
    }
}
