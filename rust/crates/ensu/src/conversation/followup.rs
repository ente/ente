use super::{AnswerEvidence, valid_answer_passages};
use crate::db::Message;
use crate::retrieval::IncludedPassage;

pub(super) fn refers_back(question: &str) -> bool {
    let mut words = question
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty());
    while let Some(word) = words.next() {
        let word = word.to_lowercase();
        if matches!(
            word.as_str(),
            "this" | "that" | "these" | "those" | "previous" | "earlier"
        ) && starts_temporal_phrase(words.clone())
        {
            continue;
        }
        if [
            "it", "its", "this", "that", "these", "those", "mine", "ours", "they", "them", "their",
            "theirs", "she", "her", "hers", "he", "him", "his", "former", "latter", "above",
            "previous", "earlier",
        ]
        .contains(&word.as_str())
        {
            return true;
        }
    }
    false
}

fn starts_temporal_phrase<'a>(words: impl Iterator<Item = &'a str>) -> bool {
    for word in words.take(8) {
        let word = word.to_lowercase();
        if [
            "in",
            "the",
            "this",
            "that",
            "these",
            "those",
            "past",
            "last",
            "next",
            "previous",
            "earlier",
            "early",
            "late",
            "coming",
            "current",
            "calendar",
            "fiscal",
            "financial",
            "academic",
            "school",
            "few",
            "several",
            "one",
            "two",
            "three",
            "four",
            "first",
            "second",
            "third",
            "fourth",
        ]
        .contains(&word.as_str())
            || word.bytes().all(|byte| byte.is_ascii_digit())
        {
            continue;
        }
        // Exclude "second" (ordinal) and "may" (verb) as time markers.
        return matches!(word.as_str(), "seconds" | "centuries" | "millennia")
            || [
                "minute",
                "hour",
                "day",
                "week",
                "fortnight",
                "month",
                "quarter",
                "year",
                "decade",
                "century",
                "millennium",
                "morning",
                "afternoon",
                "evening",
                "night",
                "weekend",
                "today",
                "tonight",
                "yesterday",
                "tomorrow",
                "spring",
                "summer",
                "autumn",
                "fall",
                "winter",
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday",
                "sunday",
                "january",
                "february",
                "march",
                "april",
                "june",
                "july",
                "august",
                "september",
                "october",
                "november",
                "december",
            ]
            .contains(&word.strip_suffix('s').unwrap_or(&word));
    }
    false
}

fn has_ownership_hint(question: &str) -> bool {
    question
        .split(|c: char| !c.is_alphanumeric())
        .any(|word| matches!(word.to_lowercase().as_str(), "my" | "our"))
}

pub(super) fn compares_owned_source(question: &str) -> bool {
    has_ownership_hint(question)
        && question.split(|c: char| !c.is_alphanumeric()).any(|word| {
            matches!(
                word.to_lowercase().as_str(),
                "compare"
                    | "compared"
                    | "comparing"
                    | "comparison"
                    | "versus"
                    | "vs"
                    | "differ"
                    | "differs"
                    | "difference"
                    | "differences"
                    | "than"
            )
        })
}

pub fn direct_followup_references(
    history: &[Message],
    evidence: &[AnswerEvidence],
    question: &str,
    searched: &[crate::retrieval::GroundedExcerpt],
) -> Vec<IncludedPassage> {
    let Some((message, entry)) = history.iter().rev().skip(1).find_map(|message| {
        evidence
            .iter()
            .find(|entry| entry.assistant_message_uuid == message.uuid && entry.matches(history))
            .map(|entry| (message, entry))
    }) else {
        return Vec::new();
    };
    if !valid_answer_passages(&entry.passages) {
        return Vec::new();
    }
    let prior = crate::retrieval::parse_grounded_assistant_text(&message.text).sources;
    let named = super::grounding::named_source_keys(
        question,
        prior.iter().chain(searched.iter().map(|hit| &hit.source)),
    );
    // "my/our" permit reload; select_sources decides historical priority.
    let may_refer_back = refers_back(question) || has_ownership_hint(question);
    if !may_refer_back
        && !named.is_empty()
        && named
            .iter()
            .all(|key| searched.iter().any(|hit| hit.source.document_key() == *key))
    {
        Vec::new()
    } else {
        entry.passages.clone()
    }
}
