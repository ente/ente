use chrono::NaiveDateTime;

use super::intent::{Intent, Target, When};
use super::matching::{choice_label, content_words, mentions_task};
use super::phrase::{deadline_phrase, is_edge_punctuation};
use super::{COMPLETE_TOOL, LIST_TOOL, ListFilter, SAVE_TOOL, timing};
use crate::llm::ToolCall;

const VAGUE_TASK_WORDS: &[&str] = &[
    "the", "one", "ones", "that", "this", "it", "task", "item", "number", "no", "#", "last",
];

const USER_ITEMS: &[&str] = &["one", "ones", "task", "item"];

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

#[cfg(test)]
fn refine_calls(
    calls: &[ToolCall],
    user_text: &str,
    shown: usize,
    open_titles: &[&str],
    now: NaiveDateTime,
) -> Vec<ToolCall> {
    let all: Vec<&ToolCall> = calls.iter().collect();
    let references = references(&all, user_text, open_titles.iter().copied());
    calls
        .iter()
        .zip(places(&all))
        .map(|(call, place)| {
            interpret(call, &references, shown, Some(now), place)
                .unwrap()
                .to_call()
        })
        .collect()
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct Place {
    nth: usize,
    numbered: usize,
    completions: usize,
}

pub(crate) struct References<'a> {
    user_text: &'a str,
    text: String,
    located: bool,
    labels: Vec<String>,
}

pub(crate) fn references<'a, 'b>(
    calls: &[&ToolCall],
    user_text: &'a str,
    open_titles: impl Iterator<Item = &'b str>,
) -> References<'a> {
    if !calls.iter().any(|call| call.name == COMPLETE_TOOL) {
        return References {
            user_text,
            text: String::new(),
            located: true,
            labels: Vec::new(),
        };
    }
    let titles: Vec<_> = calls
        .iter()
        .filter(|call| call.name == SAVE_TOOL)
        .filter_map(|call| call.text("title"))
        .collect();
    let (text, located) = reference_text(user_text, &titles);
    References {
        user_text,
        text,
        located,
        labels: open_titles.filter_map(choice_label).collect(),
    }
}

pub(crate) fn places(calls: &[&ToolCall]) -> Vec<Place> {
    let numbered =
        |call: &ToolCall| call.integer("number").is_some() && call.text("task").is_none();
    let completions = calls
        .iter()
        .filter(|call| call.name == COMPLETE_TOOL)
        .count();
    let total = calls
        .iter()
        .filter(|call| call.name == COMPLETE_TOOL && numbered(call))
        .count();
    let mut nth = 0;
    calls
        .iter()
        .map(|call| {
            let place = Place {
                nth,
                numbered: total,
                completions,
            };
            nth += usize::from(call.name == COMPLETE_TOOL && numbered(call));
            place
        })
        .collect()
}

pub(crate) fn interpret(
    call: &ToolCall,
    references: &References<'_>,
    shown: usize,
    now: Option<NaiveDateTime>,
    place: Place,
) -> Result<Intent, String> {
    let user_text = references.user_text;
    match call.name.as_str() {
        SAVE_TOOL => {
            let title = call.text("title").map(str::to_owned);
            let mut when = call.text("when").map(|quote| When {
                quote: quote.to_owned(),
                deadline: None,
            });
            if let Some(now) = now {
                if let Some(given) = when.as_mut() {
                    given.deadline = timing::parse_deadline(&given.quote, now);
                    if let Some((quote, deadline)) = deadline_phrase(
                        user_text,
                        &given.quote,
                        title.as_deref(),
                        now,
                        given.deadline,
                    )
                    .filter(|(_, deadline)| *deadline != given.deadline)
                    {
                        given.quote = quote.to_owned();
                        given.deadline = deadline;
                    }
                }
                if when.as_ref().is_some_and(|when| {
                    when.deadline.is_none() && !timing::mentions_time(&when.quote)
                }) {
                    when = None;
                }
            }
            Ok(Intent::Save { title, when })
        }
        LIST_TOOL => Ok(Intent::List {
            filter: call.text("filter").and_then(ListFilter::from_name),
            query: call.text("query").map(str::to_owned),
        }),
        COMPLETE_TOOL => {
            let located = references.located;
            let text = &references.text;
            let task = call.text("task");
            let given = call.integer("number");
            let supported = given.is_some_and(|number| {
                usize::try_from(number).is_ok_and(|number| bears_out(text, shown, number))
            });
            let positions = shown > 0 && place.completions == 1;
            let named = task.filter(|task| !is_positional(task, user_text, &references.labels));
            let pointed = match named {
                None if !located => None,
                None if positions && (given.is_none() || task.is_some()) => position(text, shown),
                None if positions && supported => None,
                None if positions => item_position(text, shown),
                None if shown > 0 && task.is_none() => {
                    let mut pointed = pointers(text);
                    pointed.dedup();
                    usize::try_from(given.unwrap_or(0))
                        .ok()
                        .filter(|given| *given > 0 && !supported && pointed.len() == place.numbered)
                        .and_then(|_| in_list(pointed[place.nth], shown))
                }
                None => None,
                Some(task) if !positions || names_task(task, user_text) => None,
                Some(_) => item_position(text, shown).or_else(|| {
                    let number = usize::try_from(given?).ok()?;
                    supported.then_some(number)
                }),
            };
            let (task, number) = match pointed {
                Some(pointed) => (None, Some(pointed as i64)),
                None if named.is_some() => (task, None),
                None => (task, given),
            };
            let text = if number.is_some() { text } else { user_text };
            let mut intent = complete(task, number, text, shown);
            if !located
                && number.is_some()
                && let Intent::Complete { sure, .. } = &mut intent
            {
                *sure = false;
            }
            Ok(intent)
        }
        _ => Err(call.name.clone()),
    }
}

pub(super) fn complete(
    task: Option<&str>,
    number: Option<i64>,
    user_text: &str,
    shown: usize,
) -> Intent {
    let sure = match (task, number) {
        (Some(task), _) => names_task(task, user_text),
        (None, Some(number)) => !usize::try_from(number).is_ok_and(|number| {
            (1..=shown).contains(&number) && !bears_out(user_text, shown, number)
        }),
        (None, None) => true,
    };
    let target = match (number, task) {
        (Some(number), _) => Target::Position(number),
        (None, Some(task)) => Target::Named(task.to_owned()),
        (None, None) => Target::Unspecified,
    };
    Intent::Complete { target, sure }
}

fn ordinal(word: &str) -> Option<usize> {
    ORDINALS
        .iter()
        .find(|(name, short, _)| word == *name || word == *short)
        .map(|(_, _, n)| *n)
}

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

fn reference_text(user_text: &str, titles: &[&str]) -> (String, bool) {
    if titles.is_empty() {
        return (user_text.to_owned(), true);
    }
    let mut words = plain_words(user_text);
    let content: Vec<_> = words
        .iter()
        .enumerate()
        .flat_map(|(i, word)| content_words(word).into_iter().map(move |word| (i, word)))
        .collect();
    let mut located = true;
    for title in titles {
        let title = content_words(title);
        if title.is_empty() {
            located = false;
            continue;
        }
        let mut found = false;
        for span in content.windows(title.len()) {
            if span.iter().map(|(_, word)| word).eq(&title) {
                found = true;
                words[span[0].0..=span[span.len() - 1].0].fill(String::new());
            }
        }
        located &= found;
    }
    (words.join(" "), located)
}

fn is_positional(task: &str, user_text: &str, labels: &[String]) -> bool {
    if labels.iter().any(|label| label == task.trim()) {
        return false;
    }
    let words = plain_words(task);
    let vague = words.iter().all(|word| {
        word.is_empty()
            || VAGUE_TASK_WORDS.contains(&word.as_str())
            || ordinal(word).is_some()
            || word.trim_start_matches('#').parse::<usize>().is_ok()
    });
    let quoted = user_text.to_lowercase().contains(&task.to_lowercase());
    vague || quoted && points_at_item(task, &["one", "ones", "task", "item", "thing"], false)
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Pointer {
    Nth(usize),
    Last,
}

const DATE_PREPOSITIONS: &[&str] = &[
    "on", "by", "since", "until", "till", "before", "after", "from", "for", "to", "around", "due",
];

fn item_number(word: &str, digits_only: bool) -> Option<usize> {
    word.parse().ok().or_else(|| {
        (!digits_only && !matches!(word, "a" | "an"))
            .then(|| timing::number_word(word).and_then(|n| usize::try_from(n).ok()))
            .flatten()
    })
}

fn pointer(words: &[String], items: &[&str], bare: bool) -> Option<Pointer> {
    words.iter().enumerate().find_map(|(i, word)| {
        let next = words.get(i + 1);
        let position = ordinal(word)
            .map(Pointer::Nth)
            .or((word == "last").then_some(Pointer::Last));
        if let Some(position) = position {
            let names_item = next.is_some_and(|next| items.contains(&next.as_str()));
            let ends_text = bare
                && next.is_none()
                && i > 0
                && words[i - 1] == "the"
                && !(i > 1 && DATE_PREPOSITIONS.contains(&words[i - 2].as_str()));
            if names_item || ends_text {
                return Some(position);
            }
        }
        if matches!(word.as_str(), "number" | "no" | "item")
            && reference_edge(i.checked_sub(1).and_then(|i| words.get(i)))
            && let Some(n) = next.and_then(|next| item_number(next, word == "no"))
        {
            return Some(Pointer::Nth(n));
        }
        word.strip_prefix('#')
            .filter(|_| reference_edge(i.checked_sub(1).and_then(|i| words.get(i))))
            .and_then(|n| n.parse().ok())
            .map(Pointer::Nth)
    })
}

fn points_at_item(text: &str, items: &[&str], bare: bool) -> bool {
    pointer(&plain_words(text), items, bare).is_some()
}

pub(super) fn names_task(task: &str, user_text: &str) -> bool {
    let said = plain_words(user_text);
    mentions_task(task, user_text, &|word| {
        ordinal(word).is_some() || word == "last" || word.parse::<usize>().is_ok()
    }) && plain_words(task)
        .iter()
        .all(|word| word.parse::<usize>().is_err() || said.contains(word))
}

pub(super) fn bears_out(user_text: &str, shown: usize, number: usize) -> bool {
    if pointers(user_text)
        .into_iter()
        .any(|pointed| in_list(pointed, shown) == Some(number))
    {
        return true;
    }
    let words = plain_words(user_text);
    (1..=shown).contains(&number)
        && words.iter().enumerate().any(|(i, word)| {
            let dated = i > 0
                && (words[i - 1] == "at" || DATE_PREPOSITIONS.contains(&words[i - 1].as_str()));
            word.parse() == Ok(number)
                && !dated
                && reference_edge(i.checked_sub(1).and_then(|i| words.get(i)))
                && reference_edge(words.get(i + 1))
        })
}

fn reference_edge(word: Option<&String>) -> bool {
    word.is_none_or(|word| {
        content_words(word).is_empty()
            || matches!(word.as_str(), "are" | "were" | "out" | "pls")
            || ordinal(word).is_some()
            || word == "last"
            || word.parse::<usize>().is_ok()
    })
}

fn item_position(user_text: &str, shown: usize) -> Option<usize> {
    in_list(pointer(&plain_words(user_text), USER_ITEMS, false)?, shown)
}

fn in_list(pointed: Pointer, shown: usize) -> Option<usize> {
    let found = match pointed {
        Pointer::Nth(n) => n,
        Pointer::Last => shown,
    };
    (1..=shown).contains(&found).then_some(found)
}

fn position(user_text: &str, shown: usize) -> Option<usize> {
    in_list(pointers(user_text).into_iter().next()?, shown)
}

fn pointers(user_text: &str) -> Vec<Pointer> {
    let words = plain_words(user_text);
    pointer(&words, USER_ITEMS, true)
        .into_iter()
        .chain(words.iter().enumerate().filter_map(|(i, word)| {
            let before = (i > 0).then(|| words[i - 1].as_str());
            let earlier = (i > 1).then(|| words[i - 2].as_str());
            let dated = before.is_some_and(|word| {
                word == "at" || DATE_PREPOSITIONS.contains(&word) || timing::mentions_time(word)
            }) || before == Some("the")
                && earlier.is_some_and(|word| DATE_PREPOSITIONS.contains(&word));
            let describes = words.get(i + 1).is_some_and(|next| {
                matches!(next.as_str(), "thing" | "time" | "of") || timing::mentions_time(next)
            });
            if !dated
                && !describes
                && reference_edge(i.checked_sub(1).and_then(|i| words.get(i)))
                && reference_edge(words.get(i + 1))
            {
                if let Some(n) = ordinal(word) {
                    return Some(Pointer::Nth(n));
                }
                if word == "last" {
                    return Some(Pointer::Last);
                }
            }
            (before == Some("task"))
                .then(|| item_number(word, false))
                .flatten()
                .map(Pointer::Nth)
        }))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::llm::ToolValue;
    use crate::todo::{LIST_TOOL, SAVE_TOOL};
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

    #[test]
    fn deadlines_are_refined_to_the_phrase_the_message_gives() {
        for (user, title, when, expected) in [
            ("Ring the vet at 4", "Ring the vet", "4", Some("at 4")),
            (
                "Pay the gas bill by 3 PM today please",
                "Pay gas bill",
                "today",
                Some("by 3 PM today"),
            ),
            (
                "Order a cake for the 9th of January",
                "Order cake",
                "January",
                Some("for the 9th of January"),
            ),
            (
                "Wash the car Friday and ring Sam at 7 PM",
                "Ring Sam",
                "Friday and ring Sam at 7 PM",
                Some("at 7 PM"),
            ),
            (
                "Wash the car Friday and ring Sam at 7 PM",
                "Wash the car",
                "Friday and ring Sam at 7 PM",
                Some("Friday"),
            ),
            (
                "Wash the car Friday, ring Sam at 7 PM",
                "Ring Sam",
                "Friday, ring Sam at 7 PM",
                Some("at 7 PM"),
            ),
            (
                "Wash the car Friday, ring Sam at 7 PM",
                "Wash the car",
                "Friday, ring Sam at 7 PM",
                Some("Friday"),
            ),
            (
                "Meeting at 2pm on Tuesday, have to prepare",
                "Prepare for meeting",
                "Tuesday, have to prepare",
                Some("at 2pm on Tuesday"),
            ),
            (
                "Call Sam tomorrow, 5:30 pm",
                "Call Sam",
                "tomorrow, 5:30 pm",
                Some("tomorrow, 5:30 pm"),
            ),
            (
                "Renew passport on January 5, 2028",
                "Renew passport",
                "on January 5, 2028",
                Some("on January 5, 2028"),
            ),
            (
                "Call Sam at 5 p.m. tomorrow",
                "Call Sam",
                "at 5 p.m. tomorrow",
                Some("at 5 p.m. tomorrow"),
            ),
            (
                "Call Sam tomorrow at 9",
                "Call Sam",
                "tomorrow",
                Some("tomorrow at 9"),
            ),
            (
                "Pay the gas bill by 5.30pm. Tomorrow call Lee",
                "Pay the gas bill",
                "by 5.30pm",
                Some("by 5.30pm"),
            ),
            (
                "Call Sam at 5 p.m. tomorrow",
                "Call Sam",
                "tomorrow",
                Some("at 5 p.m. tomorrow"),
            ),
            (
                "I was supposed to renew my licence 2 days ago",
                "Renew licence",
                "2 days ago",
                Some("2 days ago"),
            ),
            (
                "I was supposed to renew my licence 2 days ago",
                "Renew licence",
                "2 days",
                Some("2 days ago"),
            ),
            (
                "The report was due last Friday",
                "Report",
                "last Friday",
                Some("last Friday"),
            ),
            (
                "The report was due last Friday",
                "Report",
                "Friday",
                Some("last Friday"),
            ),
            (
                "Water the plants every Monday",
                "Water plants",
                "every Monday",
                Some("every Monday"),
            ),
            (
                "Water the plants every Monday",
                "Water plants",
                "Monday",
                Some("every Monday"),
            ),
            (
                "Review notes from last week tomorrow",
                "Review notes",
                "tomorrow",
                Some("tomorrow"),
            ),
            (
                "Book the room Friday at 5 for 2 hours",
                "Book the room",
                "Friday at 5 for 2 hours",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for half an hour",
                "Book the room",
                "Friday at 5 for half an hour",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for a week",
                "Book the room",
                "Friday at 5 for a week",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for one week",
                "Book the room",
                "Friday at 5 for one week",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for 2 hours 30 minutes",
                "Book the room",
                "Friday at 5 for 2 hours 30 minutes",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for a few hours",
                "Book the room",
                "Friday at 5 for a few hours",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for 1.5 hours",
                "Book the room",
                "Friday at 5 for 1.5 hours",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for 2 months",
                "Book the room",
                "Friday at 5 for 2 months",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for 30 seconds",
                "Book the room",
                "Friday at 5 for 30 seconds",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for a year",
                "Book the room",
                "Friday at 5 for a year",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5 for some time",
                "Book the room",
                "Friday at 5 for some time",
                Some("Friday at 5 for"),
            ),
            (
                "Book the room Friday at 5, for 2 hours",
                "Book the room",
                "Friday at 5, for 2 hours",
                Some("Friday at 5"),
            ),
            (
                "Book the room Friday at 5 for 2 hours, 30 minutes",
                "Book the room",
                "Friday at 5 for 2 hours, 30 minutes",
                Some("Friday at 5 for"),
            ),
            (
                "Send report next week on Friday",
                "Send report",
                "next week on Friday",
                Some("next week on Friday"),
            ),
            (
                "Send report next week Friday",
                "Send report",
                "next week Friday",
                Some("next week Friday"),
            ),
            (
                "Send report tomorrow at 5 PM UTC",
                "Send report",
                "tomorrow at 5 PM UTC",
                Some("tomorrow at 5 PM UTC"),
            ),
            (
                "Send report tomorrow at 5 PM, UTC",
                "Send report",
                "tomorrow at 5 PM, UTC",
                Some("tomorrow at 5 PM, UTC"),
            ),
            (
                "Send report tomorrow at 5 PM\nUTC",
                "Send report",
                "tomorrow at 5 PM\nUTC",
                Some("tomorrow at 5 PM\nUTC"),
            ),
            (
                "Send report next week; on Friday",
                "Send report",
                "next week; on Friday",
                Some("next week; on Friday"),
            ),
            (
                "Send report tomorrow at 5 PM utc",
                "Send report",
                "tomorrow at 5 PM utc",
                Some("tomorrow at 5 PM utc"),
            ),
            (
                "Send report tomorrow at 5 PM gmt+05:30",
                "Send report",
                "tomorrow at 5 PM gmt+05:30",
                Some("tomorrow at 5 PM gmt+05:30"),
            ),
            (
                "Send report tomorrow at 5 PM PST",
                "Send report",
                "tomorrow at 5 PM PST",
                Some("tomorrow at 5 PM PST"),
            ),
            (
                "Send report tomorrow at 5 PM pst",
                "Send report",
                "tomorrow at 5 PM pst",
                Some("tomorrow at 5 PM pst"),
            ),
            (
                "Send report tomorrow at 5 PM America/New_York",
                "Send report",
                "tomorrow at 5 PM America/New_York",
                Some("tomorrow at 5 PM America/New_York"),
            ),
            (
                "Send report tomorrow at 5 PM Eastern",
                "Send report",
                "tomorrow at 5 PM Eastern",
                Some("tomorrow at 5 PM Eastern"),
            ),
            (
                "Send report tomorrow at 5 PM pacific time",
                "Send report",
                "tomorrow at 5 PM pacific time",
                Some("tomorrow at 5 PM pacific time"),
            ),
            (
                "Send report tomorrow at 5 PM local time",
                "Send report",
                "tomorrow at 5 PM local time",
                Some("tomorrow at 5 PM"),
            ),
            (
                "Send report tomorrow at 5 PM on time",
                "Send report",
                "tomorrow at 5 PM on time",
                Some("tomorrow at 5 PM on"),
            ),
            (
                "Send report tomorrow at 5 PM w/friends",
                "Send report",
                "tomorrow at 5 PM w/friends",
                Some("tomorrow at 5 PM"),
            ),
            (
                "Send report tomorrow 25:00",
                "Send report",
                "tomorrow 25:00",
                Some("tomorrow 25:00"),
            ),
            (
                "Send report tomorrow at 25:00",
                "Send report",
                "tomorrow at 25:00",
                Some("tomorrow at 25:00"),
            ),
            (
                "Send report tomorrow, at 25:00",
                "Send report",
                "tomorrow, at 25:00",
                Some("tomorrow, at 25:00"),
            ),
            (
                "Send report tomorrow, at 5 PM",
                "Send report",
                "tomorrow, at 5 PM",
                Some("tomorrow, at 5 PM"),
            ),
            (
                "Send report tomorrow at five",
                "Send report",
                "tomorrow at five",
                Some("tomorrow at five"),
            ),
            (
                "Send report tomorrow, at five",
                "Send report",
                "tomorrow, at five",
                Some("tomorrow, at five"),
            ),
            (
                "Send report Friday at 3 PM or 4 PM",
                "Send report",
                "Friday at 3 PM or 4 PM",
                Some("Friday at 3 PM or 4 PM"),
            ),
            (
                "Send report Friday, at 3 PM or 4 PM",
                "Send report",
                "Friday, at 3 PM or 4 PM",
                Some("Friday, at 3 PM or 4 PM"),
            ),
            (
                "Send report Friday at 3 PM, or 4 PM",
                "Send report",
                "Friday at 3 PM, or 4 PM",
                Some("Friday at 3 PM, or 4 PM"),
            ),
            (
                "Send report Friday at three or four",
                "Send report",
                "Friday at three or four",
                Some("Friday at three or four"),
            ),
            (
                "Send report tomorrow at 5 PM please",
                "Send report",
                "tomorrow at 5 PM please",
                Some("tomorrow at 5 PM"),
            ),
            (
                "Send report tomorrow at 5 PM PLEASE",
                "Send report",
                "tomorrow at 5 PM PLEASE",
                Some("tomorrow at 5 PM"),
            ),
            (
                "Send report tomorrow at 5 PM PLS",
                "Send report",
                "tomorrow at 5 PM PLS",
                Some("tomorrow at 5 PM"),
            ),
            (
                "Call Lee tomorrow night at 1",
                "Call Lee",
                "tomorrow night at 1",
                Some("tomorrow night at 1"),
            ),
            (
                "Call Lee tomorrow night at 12:30",
                "Call Lee",
                "tomorrow night at 12:30",
                Some("tomorrow night at 12:30"),
            ),
            (
                "Take vitamins every day at 9",
                "Take vitamins",
                "at 9",
                Some("every day at 9"),
            ),
            (
                "Pay the invoice that was due last Friday by Friday",
                "Pay the invoice",
                "Friday",
                Some("Friday"),
            ),
            (
                "Wash the car Friday and finish the last chapter",
                "Wash the car",
                "Friday and finish the last chapter",
                Some("Friday"),
            ),
            (
                "Call mom tomorrow at 5 and call dad at 5",
                "Call dad",
                "at 5",
                Some("at 5"),
            ),
            (
                "Call mom tomorrow at 5 and call dad at 5",
                "Call mom",
                "at 5",
                Some("tomorrow at 5"),
            ),
            (
                "Chat 5 minutes with Lee at 5",
                "Chat with Lee",
                "at 5",
                Some("at 5"),
            ),
            (
                "Ring Zoë TOMORROW at 4",
                "Ring Zoë",
                "tomorrow",
                Some("TOMORROW at 4"),
            ),
            (
                "Fix the fence this weekend",
                "Fix fence",
                "this weekend",
                Some("this weekend"),
            ),
            (
                "Fix the fence tomorrow",
                "Fix fence",
                "next month",
                Some("next month"),
            ),
            ("Swing by the pharmacy", "Pharmacy", "the pharmacy", None),
            ("Add milk to my to-do list", "Milk", "to-do", None),
            (
                "Plant bulbs sometime in March",
                "Plant bulbs",
                "sometime in March",
                Some("sometime in March"),
            ),
            (
                "Call Kim at quarter-past",
                "Call Kim",
                "at quarter-past 4",
                Some("at quarter-past 4"),
            ),
        ] {
            let calls = [call(
                SAVE_TOOL,
                &[("title", text(title)), ("when", text(when))],
            )];
            let references = references(&[&calls[0]], user, std::iter::empty());
            let intent = interpret(
                &calls[0],
                &references,
                0,
                Some(now()),
                places(&[&calls[0]])[0],
            )
            .unwrap();
            let Intent::Save { when: refined, .. } = intent else {
                panic!("Expected a save intent");
            };
            assert_eq!(
                refined.as_ref().map(|when| when.quote.as_str()),
                expected,
                "{user}: {when}"
            );
            assert_eq!(
                refined.and_then(|when| when.deadline),
                expected.and_then(|when| timing::parse_deadline(when, now())),
                "{user}: {when}"
            );
        }
    }

    #[test]
    fn positions_become_numbers_only_when_the_message_points_at_the_list() {
        const ISSUES: [&str; 4] = [
            "Call Lee",
            "Fix issue #3",
            "Water plants",
            "Submit form no 2",
        ];
        const RENT: [&str; 3] = ["Call Lee", "Pay rent on the 1st", "Water plants"];
        const TICKETS: [&str; 4] = ["Call Lee", "Water plants", "Buy milk", "Ticket #3"];
        type Case<'a> = (Option<&'a str>, Option<i64>, &'a str, Option<i64>);
        let check = |shown: usize, open: &[&str], cases: &[Case]| {
            for (task, number, user, expected) in cases {
                let mut arguments = Vec::new();
                arguments.extend(task.map(|task| ("task", text(task))));
                arguments.extend(number.map(|n| ("number", ToolValue::Integer(n))));
                let calls = [call(COMPLETE_TOOL, &arguments)];
                let refined = refine_calls(&calls, user, shown, open, now()).remove(0);
                let kept = task.filter(|_| expected.is_none());
                assert_eq!(
                    (refined.text("task"), refined.integer("number")),
                    (kept, *expected),
                    "{user} ({task:?}, {number:?}, {shown} shown)"
                );
            }
        };
        check(
            3,
            &[],
            &[
                (Some("second one"), None, "The second one is done", Some(2)),
                (Some("it"), None, "Tick off number 2", Some(2)),
                (Some("Buy apples"), None, "The third one is done", Some(3)),
                (Some("Edit the draft"), None, "Finished the 2nd draft", None),
                (
                    Some("The first one's done now"),
                    None,
                    "The first one's done now",
                    Some(1),
                ),
                (
                    Some("2nd draft of the essay"),
                    None,
                    "Finished the 2nd draft of the essay",
                    None,
                ),
                (Some("Buy milk"), Some(1), "I bought the milk", None),
                (Some("Buy milk"), Some(1), "The fifth one is done", None),
                (Some("File the taxes"), None, "Got it done at last", None),
                (Some("File the taxes"), None, "Did that first", None),
                (
                    Some("File the taxes"),
                    None,
                    "No one helped but it's finished",
                    None,
                ),
                (Some("Submit form no 2"), None, "Submitted form no 2", None),
                (
                    Some("Review item 3 of the agenda"),
                    None,
                    "Reviewed the agenda",
                    None,
                ),
                (None, None, "Got it done at last", None),
                (None, None, "I finished the first draft", None),
                (None, None, "Finished chapter 3", None),
                (None, None, "Finished chapter #3", None),
                (None, None, "Finished version 3", None),
                (None, None, "Finished the last chapter", None),
                (None, None, "#3 is done", Some(3)),
                (None, None, "Finished item #3", Some(3)),
                (None, None, "Finished the task a while ago", None),
                (
                    Some("Call Lee"),
                    None,
                    "First of all, tick off the third one",
                    Some(3),
                ),
                (None, None, "Finished it last night", None),
                (None, None, "Did that first thing this morning", None),
                (None, None, "Paid it on the 1st", None),
                (Some("the second"), None, "Mark the second as done", Some(2)),
                (Some("fifth"), None, "The fifth one is done", None),
                (Some("milk"), None, "First thing, I bought the milk", None),
            ],
        );
        check(
            4,
            &[],
            &[
                (Some("one"), None, "Done with the last one", Some(4)),
                (
                    Some("Finish the report"),
                    None,
                    "Finished the report on the 3rd",
                    None,
                ),
                (
                    Some("Do the laundry"),
                    None,
                    "I did the laundry first",
                    None,
                ),
                (
                    Some("File the taxes"),
                    None,
                    "Finally done with the taxes at last",
                    None,
                ),
                (
                    Some("Finish the report"),
                    None,
                    "No one called, but I finished the report",
                    None,
                ),
                (
                    Some("Pay rent on the 1st"),
                    None,
                    "Paid rent on the 1st",
                    None,
                ),
            ],
        );
        check(
            6,
            &[],
            &[
                (
                    Some("Cross off number five"),
                    Some(1),
                    "Cross off number five",
                    Some(5),
                ),
                (None, Some(2), "Tick off the third", Some(2)),
            ],
        );
        check(
            0,
            &[],
            &[
                (Some("Buy milk"), Some(1), "I bought the milk", None),
                (Some("second one"), None, "The second one is done", None),
            ],
        );
        check(
            4,
            &ISSUES,
            &[
                (Some("Fix issue #3"), None, "Fix issue #3 is done", None),
                (
                    Some("Submit form no 2"),
                    None,
                    "Submit form no 2 is done",
                    None,
                ),
                (Some("Call Lee"), None, "The third one is done", Some(3)),
            ],
        );
        check(
            3,
            &["Rent payment"],
            &[(Some("Rent payment"), None, "Paid the rent on the 1st", None)],
        );
        check(
            3,
            &["Birthday gift for Sam"],
            &[(
                Some("Birthday gift for Sam"),
                None,
                "Bought the birthday present by the 2nd",
                None,
            )],
        );
        check(
            3,
            &RENT,
            &[
                (
                    Some("Pay rent on the 1st"),
                    None,
                    "The 1st one is done",
                    Some(1),
                ),
                (Some("Call Lee"), None, "Booked a table for the 3rd", None),
                (Some("Call Lee"), None, "Tick off the third", None),
                (Some("Call Lee"), None, "Mark the second as done", None),
                (None, Some(2), "The third one is done", Some(3)),
                (None, None, "Paid it on December 1st", None),
                (Some("Call Lee"), Some(3), "Please tick off 3", Some(3)),
                (Some("Call Lee"), Some(3), "Tick off the third", Some(3)),
                (
                    Some("Call Lee"),
                    Some(2),
                    "Mark the second as done",
                    Some(2),
                ),
                (Some("Call Lee"), Some(2), "Tick off the third", None),
            ],
        );
        check(
            4,
            &TICKETS,
            &[(Some("Ticket #3"), None, "Closed ticket #3", None)],
        );

        let both = [call(
            COMPLETE_TOOL,
            &[
                ("task", text("that one")),
                ("number", ToolValue::Integer(2)),
            ],
        )];
        let refined = refine_calls(&both, "Mark that one as done", 0, &[], now());
        assert_eq!(refined[0].integer("number"), Some(2));
        let named = [
            call(COMPLETE_TOOL, &[("task", text("Call Lee"))]),
            call(COMPLETE_TOOL, &[("task", text("Buy apples"))]),
        ];
        let open = ["Call Lee", "Buy apples", "Water plants"];
        let refined = refine_calls(
            &named,
            "Tick off the first one and the second one",
            3,
            &open,
            now(),
        );
        assert_eq!(refined[0].text("task"), Some("Call Lee"));
        assert_eq!(refined[1].text("task"), Some("Buy apples"));
        let numbered = [
            call(COMPLETE_TOOL, &[("number", ToolValue::Integer(2))]),
            call(COMPLETE_TOOL, &[("number", ToolValue::Integer(3))]),
        ];
        let refined = refine_calls(
            &numbered,
            "The second and third ones are done",
            3,
            &open,
            now(),
        );
        assert_eq!(refined[0].integer("number"), Some(2));
        assert_eq!(refined[1].integer("number"), Some(3));
    }

    #[test]
    fn list_filters_are_kept_only_when_given_and_known() {
        let filter = |arguments: &[(&str, ToolValue)]| {
            refine_calls(
                &[call(LIST_TOOL, arguments)],
                "What's on my list?",
                0,
                &[],
                now(),
            )
            .remove(0)
            .text("filter")
            .map(str::to_owned)
        };
        assert_eq!(filter(&[]), None);
        assert_eq!(filter(&[("filter", text("soon"))]), None);
        assert_eq!(
            filter(&[("filter", text("overdue"))]).as_deref(),
            Some("overdue")
        );
    }
}
