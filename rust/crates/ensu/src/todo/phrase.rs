use chrono::NaiveDateTime;

use super::timing::{self, Deadline};

const MAX_DEADLINE_WORDS: usize = 8;

const CLAUSE_WORDS: &[&str] = &["and", "then", "also", "but", "&", "plus"];

const NOT_UPCOMING_WORDS: &[&str] = &["ago", "last", "yesterday", "every", "not"];

#[derive(Debug)]
struct Word<'a> {
    text: &'a str,
    start: usize,
    end: usize,
    clause: usize,
}

pub(super) fn is_edge_punctuation(c: char) -> bool {
    matches!(
        c,
        ',' | ';' | '.' | '!' | '?' | ':' | '"' | '\'' | '(' | ')' | '“' | '”' | '‘' | '’'
    )
}

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
            let unquoted = raw.trim_end_matches(['"', '\'', ')', '”', '’']);
            let meridiem = matches!(core.to_lowercase().as_str(), "a.m" | "p.m");
            let ends_clause = unquoted.ends_with([',', ';', '!', '?', ':'])
                || unquoted.ends_with('.') && !meridiem;
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

fn occurrences(user_text: &str, quote: &str) -> Vec<(usize, usize)> {
    if quote.is_empty() {
        return Vec::new();
    }
    let ranges = |text: &str, quote: &str| -> Vec<(usize, usize)> {
        text.match_indices(quote)
            .map(|(at, found)| (at, at + found.len()))
            .collect()
    };
    let mut all = ranges(user_text, quote);
    if all.is_empty() {
        let lower = user_text.to_lowercase();
        if lower.len() == user_text.len() {
            all = ranges(&lower, &quote.to_lowercase());
            all.retain(|&(start, end)| {
                user_text.is_char_boundary(start) && user_text.is_char_boundary(end)
            });
        }
    }
    let edge = |c: Option<char>| c.is_none_or(|c| c.is_whitespace() || is_edge_punctuation(c));
    let whole: Vec<_> = all
        .iter()
        .copied()
        .filter(|&(start, end)| {
            edge(user_text[..start].chars().next_back()) && edge(user_text[end..].chars().next())
        })
        .collect();
    if whole.is_empty() { all } else { whole }
}

pub(super) fn deadline_phrase<'a>(
    user_text: &'a str,
    quote: &str,
    title: Option<&str>,
    now: NaiveDateTime,
    original: Option<Deadline>,
) -> Option<(&'a str, Option<Deadline>)> {
    let words = words(user_text);
    let scopes = deadline_scopes(user_text, &words);
    let keep_whole = original.is_some();
    type RankedPhrase = ((usize, bool), (usize, usize), Option<Deadline>);
    let mut best: Option<RankedPhrase> = None;
    for (quote_start, quote_end) in occurrences(user_text, quote) {
        let overlapping: Vec<usize> = (0..words.len())
            .filter(|&i| words[i].start < quote_end && words[i].end > quote_start)
            .collect();
        let mut clauses: Vec<usize> = overlapping.iter().map(|&i| words[i].clause).collect();
        clauses.dedup();
        for clause in clauses {
            let touched: Vec<usize> = overlapping
                .iter()
                .copied()
                .filter(|&i| words[i].clause == clause)
                .collect();
            let Some((start, end, deadline)) =
                longest_deadline(user_text, &words, clause, &touched, now)
            else {
                continue;
            };
            let covers_quote = overlapping.first().is_some_and(|&first| start <= first)
                && overlapping.last().is_some_and(|&last| end >= last);
            if keep_whole && !covers_quote {
                continue;
            }
            let duration_start = [end, end + 1].into_iter().find(|&i| {
                words.get(i).is_some_and(|word| {
                    scopes[i] == scopes[end] && word.text.eq_ignore_ascii_case("for")
                })
            });
            let duration_end = duration_start.and_then(|start| {
                let mut last = None;
                for (i, word) in words.iter().enumerate().skip(start + 1) {
                    if scopes[i] != scopes[end] {
                        break;
                    }
                    let word = word.text.to_lowercase();
                    let unit = word.strip_suffix('s').unwrap_or(&word);
                    if [
                        "second", "sec", "minute", "min", "hour", "hr", "day", "week", "month",
                        "year", "time",
                    ]
                    .contains(&unit)
                    {
                        last = Some(i);
                    } else if timing::number_word(&word).is_none()
                        && !word
                            .parse::<f64>()
                            .is_ok_and(|number| number.is_finite() && number > 0.0)
                        && ![
                            "half", "quarter", "few", "couple", "several", "many", "some", "of",
                        ]
                        .contains(&word.as_str())
                    {
                        break;
                    }
                }
                last
            });
            let drops_meaning = overlapping.iter().any(|&i| {
                let word = words[i].text.to_lowercase();
                let duration = i > end && duration_end.is_some_and(|last| i <= last);
                let zone = is_zone(&word)
                    && !(word == "time"
                        && i > 0
                        && ["local", "on"].contains(&words[i - 1].text.to_lowercase().as_str()));
                let clock = i > 0
                    && ["at", "around", "about", "by", "before"]
                        .contains(&words[i - 1].text.to_lowercase().as_str())
                    && !matches!(word.as_str(), "a" | "an")
                    && timing::number_word(&word).is_some();
                (i < start || i > end)
                    && scopes[i] == scopes[start]
                    && (NOT_UPCOMING_WORDS.contains(&word.as_str())
                        || !duration && (timing::mentions_time(&word) || zone || clock))
            });
            if drops_meaning {
                continue;
            }
            let span = with_not_upcoming(&words, start, end);
            let deadline = if span == (start, end) {
                Some(deadline)
            } else {
                timing::parse_deadline(&user_text[words[span.0].start..words[span.1].end], now)
            };
            let rank = (title_score(&words, clause, title), deadline.is_some());
            if best.is_none_or(|(best_rank, _, _)| rank > best_rank) {
                best = Some((rank, span, deadline));
            }
        }
    }
    let (_, (start, end), deadline) = best?;
    Some((&user_text[words[start].start..words[end].end], deadline))
}

fn deadline_scopes(user_text: &str, words: &[Word]) -> Vec<usize> {
    let mut scopes = vec![0; words.len()];
    for i in 1..words.len() {
        let continues = words[i].clause == words[i - 1].clause
            || user_text[words[i - 1].end..words[i].start]
                .chars()
                .all(|c| c.is_whitespace() || is_edge_punctuation(c))
                && words[i..]
                    .iter()
                    .enumerate()
                    .take_while(|(_, word)| word.clause == words[i].clause)
                    .all(|(offset, word)| {
                        let word = word.text.to_lowercase();
                        timing::mentions_time(&word)
                            || timing::number_word(&word).is_some()
                            || NOT_UPCOMING_WORDS.contains(&word.as_str())
                            || is_zone(&word)
                            || [
                                "at", "on", "by", "the", "this", "of", "around", "about", "before",
                                "until", "till", "due", "for", "coming", "in", "next", "or",
                                "local", "half", "quarter", "past", "to", "second", "seconds",
                                "sec", "secs", "few", "couple", "several", "many", "some",
                                "please", "pls",
                            ]
                            .contains(&word.as_str())
                            || words.get(i + offset + 1).is_some_and(|next| {
                                next.clause == words[i].clause
                                    && next.text.eq_ignore_ascii_case("time")
                            })
                    });
        scopes[i] = scopes[i - 1] + usize::from(!continues);
    }
    scopes
}

fn is_zone(word: &str) -> bool {
    word.starts_with("utc")
        || word.starts_with("gmt")
        || word == "time"
        || word.split_once('/').is_some_and(|(area, _)| {
            [
                "africa",
                "america",
                "antarctica",
                "arctic",
                "asia",
                "atlantic",
                "australia",
                "europe",
                "indian",
                "pacific",
                "etc",
                "us",
                "canada",
                "mexico",
                "brazil",
                "chile",
            ]
            .contains(&area)
                && word.split('/').all(|part| {
                    !part.is_empty()
                        && part
                            .bytes()
                            .all(|c| c.is_ascii_alphanumeric() || b"_+-".contains(&c))
                })
        })
        || [
            "est",
            "edt",
            "cst",
            "cdt",
            "mst",
            "mdt",
            "pst",
            "pdt",
            "cet",
            "cest",
            "eet",
            "eest",
            "bst",
            "ist",
            "jst",
            "kst",
            "aest",
            "aedt",
            "acst",
            "acdt",
            "awst",
            "nzst",
            "nzdt",
            "eastern",
            "pacific",
            "central",
            "mountain",
            "atlantic",
            "timezone",
            "time-zone",
        ]
        .contains(&word)
}

fn with_not_upcoming(words: &[Word], start: usize, end: usize) -> (usize, usize) {
    let clause = words[start].clause;
    let is = |i: usize, among: &[&str]| {
        words.get(i).is_some_and(|word| {
            word.clause == clause && among.contains(&word.text.to_lowercase().as_str())
        })
    };
    let end = if is(end + 1, &["ago"]) { end + 1 } else { end };
    let stands_alone = is(
        start,
        &[
            "by", "before", "until", "till", "today", "tonight", "tomorrow", "tmrw",
        ],
    );
    let mut before = start;
    while !stands_alone && before > 0 && is(before - 1, &["day", "week", "other", "single"]) {
        before -= 1;
    }
    if before > 0 && is(before - 1, &["last", "every", "not"]) {
        (before - 1, end)
    } else {
        (start, end)
    }
}

fn longest_deadline(
    user_text: &str,
    words: &[Word],
    clause: usize,
    touched: &[usize],
    now: NaiveDateTime,
) -> Option<(usize, usize, Deadline)> {
    let (first, last) = (*touched.first()?, *touched.last()?);
    let clause_words: Vec<usize> = (0..words.len())
        .filter(|&i| words[i].clause == clause)
        .collect();
    let (clause_start, clause_end) = (*clause_words.first()?, *clause_words.last()?);
    let mut best: Option<(usize, usize, Deadline)> = None;
    for start in clause_start..=last {
        for end in start.max(first)..=clause_end {
            let len = end - start + 1;
            if len > MAX_DEADLINE_WORDS {
                break;
            }
            if best.is_some_and(|(s, e, _)| e - s + 1 >= len) {
                continue;
            }
            let phrase = &user_text[words[start].start..words[end].end];
            if let Some(deadline) = timing::parse_deadline(phrase, now) {
                best = Some((start, end, deadline));
            }
        }
    }
    best
}

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
