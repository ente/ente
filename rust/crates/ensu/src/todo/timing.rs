//! Deterministic parsing of a deadline the user stated, as quoted by the
//! model. The model only copies the words; all date arithmetic happens here.
//! Unrecognised words make the parse fail rather than guess.

use chrono::{
    Datelike, Days, Duration, Local, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Weekday,
};

/// A resolved deadline in local time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Deadline {
    pub at: NaiveDateTime,
    /// True when the user gave a day but no time and a default was used.
    pub default_time: bool,
}

const DEFAULT_HOUR: u32 = 9;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Day {
    Offset(u64),
    Weekday(Weekday),
    Date {
        month: u32,
        day: u32,
        year: Option<i32>,
    },
}

#[derive(Debug, Default)]
struct Parts {
    day: Option<Day>,
    time: Option<NaiveTime>,
    /// An hour without am/pm, resolved once the day is known.
    bare_hour: Option<(u32, u32)>,
    after: Option<Duration>,
    period: Option<u32>,
}

fn number_word(word: &str) -> Option<i64> {
    Some(match word {
        "a" | "an" | "one" => 1,
        "two" => 2,
        "three" => 3,
        "four" => 4,
        "five" => 5,
        "six" => 6,
        "seven" => 7,
        "eight" => 8,
        "nine" => 9,
        "ten" => 10,
        "eleven" => 11,
        "twelve" => 12,
        "fifteen" => 15,
        "twenty" => 20,
        "thirty" => 30,
        "forty" => 40,
        "fifty" => 50,
        _ => return word.parse().ok().filter(|n| (1..=10_000).contains(n)),
    })
}

fn weekday(word: &str) -> Option<Weekday> {
    let word = word
        .strip_suffix('s')
        .filter(|w| w.ends_with("day"))
        .unwrap_or(word);
    word.parse().ok()
}

fn month(word: &str) -> Option<u32> {
    word.parse::<chrono::Month>()
        .ok()
        .map(|m| m.number_from_month())
        .or(match word {
            "sept" => Some(9),
            _ => None,
        })
}

fn day_of_month(word: &str) -> Option<u32> {
    let digits = word
        .strip_suffix("st")
        .or_else(|| word.strip_suffix("nd"))
        .or_else(|| word.strip_suffix("rd"))
        .or_else(|| word.strip_suffix("th"))
        .unwrap_or(word);
    digits.parse().ok().filter(|d| (1..=31).contains(d))
}

/// Parses "5pm", "5:30 pm" (as two words), "17:00", "noon" and similar.
fn clock(words: &[&str]) -> Option<(usize, NaiveTime)> {
    let first = *words.first()?;
    match first {
        "noon" | "midday" => return Some((1, NaiveTime::from_hms_opt(12, 0, 0)?)),
        "midnight" => return Some((1, NaiveTime::from_hms_opt(23, 59, 0)?)),
        _ => {}
    }
    let (digits, mut meridiem, mut used) = match first
        .strip_suffix("am")
        .map(|d| (d, Some(false)))
        .or_else(|| first.strip_suffix("pm").map(|d| (d, Some(true))))
    {
        Some((digits, meridiem)) if !digits.is_empty() => (digits, meridiem, 1),
        _ => (first, None, 1),
    };
    if meridiem.is_none() {
        match words.get(1).copied() {
            Some("am" | "a.m" | "a.m.") => {
                meridiem = Some(false);
                used = 2;
            }
            Some("pm" | "p.m" | "p.m.") => {
                meridiem = Some(true);
                used = 2;
            }
            _ => {}
        }
    }
    let (hour, minute) = match digits.split_once(':') {
        Some((h, m)) if m.len() == 2 => (h.parse::<u32>().ok()?, m.parse::<u32>().ok()?),
        Some(_) => return None,
        None if digits.len() == 3 || digits.len() == 4 => {
            let (h, m) = digits.split_at(digits.len() - 2);
            // "615" is only a time when "am" or "pm" follows.
            meridiem?;
            (h.parse().ok()?, m.parse().ok()?)
        }
        None => (digits.parse().ok()?, 0),
    };
    if minute > 59 {
        return None;
    }
    let hour = match meridiem {
        Some(pm) if (1..=12).contains(&hour) => hour % 12 + if pm { 12 } else { 0 },
        Some(_) => return None,
        None if digits.contains(':') && hour < 24 => hour,
        None => return None,
    };
    Some((used, NaiveTime::from_hms_opt(hour, minute, 0)?))
}

const FILLER: &[&str] = &[
    "at", "on", "by", "the", "this", "next", "of", "around", "about", "before", "until", "till",
    "due", "for", "coming", "o'clock", "oclock",
];

fn parse_parts(quote: &str) -> Option<Parts> {
    let lower = quote.to_lowercase().replace([',', ';', '!', '?'], " ");
    let words: Vec<&str> = lower
        .split_whitespace()
        .map(|w| w.trim_end_matches('.'))
        .filter(|w| !w.is_empty())
        .collect();
    if words.is_empty() {
        return None;
    }
    let mut parts = Parts::default();
    let mut i = 0;
    let set_day = |parts: &mut Parts, day: Day| -> Option<()> {
        if parts.day.replace(day).is_some() {
            None
        } else {
            Some(())
        }
    };
    while i < words.len() {
        let word = words[i];
        let next = words.get(i + 1).copied();
        // Relative durations: "in 20 minutes", "2 hours from now", "half an hour".
        let amount = if word == "half" && matches!(next, Some("an" | "a")) {
            Some((30, i + 2, true))
        } else {
            number_word(word).map(|n| (n, i + 1, false))
        };
        if let Some((n, unit_at, half_hour)) = amount {
            let unit = words.get(unit_at).copied().unwrap_or("");
            let unit = unit.strip_suffix('s').unwrap_or(unit);
            let duration = match (unit, half_hour) {
                ("hour", true) => Some(Duration::minutes(n)),
                ("minute" | "min", false) => Some(Duration::minutes(n)),
                ("hour" | "hr", false) => Some(Duration::hours(n)),
                ("day", false) => {
                    set_day(&mut parts, Day::Offset(u64::try_from(n).ok()?))?;
                    i = unit_at + 1;
                    continue;
                }
                ("week", false) => {
                    set_day(&mut parts, Day::Offset(u64::try_from(n * 7).ok()?))?;
                    i = unit_at + 1;
                    continue;
                }
                _ => None,
            };
            if let Some(duration) = duration {
                if parts.after.replace(duration).is_some() {
                    return None;
                }
                i = unit_at + 1;
                if words.get(i) == Some(&"from") && words.get(i + 1) == Some(&"now") {
                    i += 2;
                }
                continue;
            }
        }
        if let Some((used, time)) = clock(&words[i..]) {
            if parts.time.replace(time).is_some() {
                return None;
            }
            i += used;
            continue;
        }
        if let Ok(hour) = word.parse::<u32>()
            && (1..=12).contains(&hour)
            && i > 0
            && matches!(words[i - 1], "at" | "around" | "about" | "by" | "before")
        {
            parts.bare_hour = Some((hour, 0));
            i += 1;
            continue;
        }
        match word {
            "in" | "from" | "now" => {
                i += 1;
                continue;
            }
            "today" => set_day(&mut parts, Day::Offset(0))?,
            "tonight" => {
                set_day(&mut parts, Day::Offset(0))?;
                parts.period = Some(20);
            }
            "tomorrow" | "tmrw" => set_day(&mut parts, Day::Offset(1))?,
            "morning" => parts.period = Some(9),
            "afternoon" => parts.period = Some(15),
            "evening" => parts.period = Some(18),
            "night" => parts.period = Some(21),
            _ if word == "day"
                && next == Some("after")
                && words.get(i + 2) == Some(&"tomorrow") =>
            {
                set_day(&mut parts, Day::Offset(2))?;
                i += 3;
                continue;
            }
            _ if weekday(word).is_some() => set_day(&mut parts, Day::Weekday(weekday(word)?))?,
            _ if FILLER.contains(&word) => {}
            _ => {
                if let Ok(date) = NaiveDate::parse_from_str(word, "%Y-%m-%d") {
                    set_day(
                        &mut parts,
                        Day::Date {
                            month: date.month(),
                            day: date.day(),
                            year: Some(date.year()),
                        },
                    )?;
                } else if let Some(m) = month(word) {
                    let after = next.and_then(day_of_month);
                    let before = (i > 0)
                        .then(|| words[i - 1])
                        .and_then(day_of_month)
                        .or_else(|| {
                            (i > 1 && words[i - 1] == "of")
                                .then(|| words[i - 2])
                                .and_then(day_of_month)
                        });
                    let day = after.or(before)?;
                    let mut consumed = usize::from(after.is_some());
                    let year = words
                        .get(i + 1 + consumed)
                        .filter(|w| w.len() == 4)
                        .and_then(|w| w.parse::<i32>().ok());
                    consumed += usize::from(year.is_some());
                    set_day(
                        &mut parts,
                        Day::Date {
                            month: m,
                            day,
                            year,
                        },
                    )?;
                    i += 1 + consumed;
                    continue;
                } else if day_of_month(word).is_some()
                    && (next.and_then(month).is_some()
                        || next == Some("of")
                            && words.get(i + 2).copied().and_then(month).is_some())
                    || word == "of" && next.and_then(month).is_some()
                {
                    // Consumed with the following month.
                } else {
                    return None;
                }
            }
        }
        i += 1;
    }
    Some(parts)
}

fn next_weekday(today: NaiveDate, target: Weekday) -> Option<NaiveDate> {
    let offset = (7 + target.num_days_from_monday() - today.weekday().num_days_from_monday()) % 7;
    today.checked_add_days(Days::new(u64::from(if offset == 0 { 7 } else { offset })))
}

/// Resolves `quote` against `now`, both in local time. Returns `None` when the
/// quote isn't a deadline this parser understands or lies in the past.
pub fn parse_deadline(quote: &str, now: NaiveDateTime) -> Option<Deadline> {
    let parts = parse_parts(quote)?;
    if let Some(after) = parts.after {
        if parts.day.is_some() || parts.time.is_some() || parts.bare_hour.is_some() {
            return None;
        }
        return Some(Deadline {
            at: now.checked_add_signed(after)?,
            default_time: false,
        });
    }
    let today = now.date();
    let date = match parts.day {
        None => None,
        Some(Day::Offset(n)) => Some(today.checked_add_days(Days::new(n))?),
        Some(Day::Weekday(target)) => Some(next_weekday(today, target)?),
        Some(Day::Date { month, day, year }) => {
            let year_now = today.year();
            let candidate = NaiveDate::from_ymd_opt(year.unwrap_or(year_now), month, day)?;
            if year.is_none() && candidate < today {
                Some(NaiveDate::from_ymd_opt(year_now + 1, month, day)?)
            } else {
                Some(candidate)
            }
        }
    };
    let time = parts.time.or_else(|| {
        let (hour, minute) = parts.bare_hour?;
        let hour = match parts.period {
            Some(period) if period >= 12 && hour < 12 => hour + 12,
            Some(_) => hour,
            None if hour < 7 => hour + 12,
            None => hour,
        };
        NaiveTime::from_hms_opt(hour, minute, 0)
    });
    let (at, default_time) = match (date, time) {
        (Some(date), Some(time)) => (date.and_time(time), false),
        (None, Some(time)) => {
            let candidate = today.and_time(time);
            if candidate > now {
                (candidate, false)
            } else {
                (today.checked_add_days(Days::new(1))?.and_time(time), false)
            }
        }
        (Some(date), None) => {
            let hour = parts.period.unwrap_or(DEFAULT_HOUR);
            let candidate = date.and_time(NaiveTime::from_hms_opt(hour, 0, 0)?);
            if date == today && candidate <= now {
                // "today" after the default time: give the user an hour.
                (
                    now.checked_add_signed(Duration::hours(1))?,
                    parts.period.is_none(),
                )
            } else {
                (candidate, parts.period.is_none())
            }
        }
        (None, None) => {
            let hour = parts.period?;
            let candidate = today.and_time(NaiveTime::from_hms_opt(hour, 0, 0)?);
            if candidate > now {
                (candidate, false)
            } else {
                (
                    today
                        .checked_add_days(Days::new(1))?
                        .and_time(NaiveTime::from_hms_opt(hour, 0, 0)?),
                    false,
                )
            }
        }
    };
    (at > now).then_some(Deadline { at, default_time })
}

/// Milliseconds since the epoch for a local time. Repeated times use the
/// earlier instant; skipped times move forward an hour.
pub fn local_millis(at: NaiveDateTime) -> Option<i64> {
    Local
        .from_local_datetime(&at)
        .earliest()
        .or_else(|| {
            Local
                .from_local_datetime(&(at + Duration::hours(1)))
                .earliest()
        })
        .map(|instant| instant.timestamp_millis())
}

/// Local time for milliseconds since the epoch.
pub fn local_time(ms: i64) -> Option<NaiveDateTime> {
    Local
        .timestamp_millis_opt(ms)
        .single()
        .map(|instant| instant.naive_local())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M").unwrap()
    }

    // Thursday afternoon.
    const NOW: &str = "2026-11-12 14:30";

    #[test]
    fn days_times_and_combinations_resolve_locally() {
        for (quote, expected, default_time) in [
            ("tomorrow", "2026-11-13 09:00", true),
            ("tomorrow at 4 PM", "2026-11-13 16:00", false),
            ("4pm tomorrow", "2026-11-13 16:00", false),
            ("tomorrow around 615 PM", "2026-11-13 18:15", false),
            ("Tomorrow, 5:30 pm", "2026-11-13 17:30", false),
            ("tomorrow morning", "2026-11-13 09:00", false),
            ("tomorrow evening", "2026-11-13 18:00", false),
            ("tonight", "2026-11-12 20:00", false),
            ("6 PM", "2026-11-12 18:00", false),
            ("at 9am", "2026-11-13 09:00", false),
            ("noon", "2026-11-13 12:00", false),
            ("at 5", "2026-11-12 17:00", false),
            ("Friday", "2026-11-13 09:00", true),
            ("on Thursday", "2026-11-19 09:00", true),
            ("next Monday at noon", "2026-11-16 12:00", false),
            ("Monday 3pm", "2026-11-16 15:00", false),
            ("December 5", "2026-12-05 09:00", true),
            ("Dec 5 at 1 PM", "2026-12-05 13:00", false),
            ("5th of December", "2026-12-05 09:00", true),
            ("23 November 1PM", "2026-11-23 13:00", false),
            ("January 3", "2027-01-03 09:00", true),
            ("2027-02-01", "2027-02-01 09:00", true),
            ("the day after tomorrow at 5 am", "2026-11-14 05:00", false),
            ("in 3 days", "2026-11-15 09:00", true),
            ("in two weeks", "2026-11-26 09:00", true),
            ("in 20 minutes", "2026-11-12 14:50", false),
            ("2 hours from now", "2026-11-12 16:30", false),
            ("half an hour", "2026-11-12 15:00", false),
            ("today", "2026-11-12 15:30", true),
            ("today at 18:45", "2026-11-12 18:45", false),
        ] {
            assert_eq!(
                parse_deadline(quote, at(NOW)),
                Some(Deadline {
                    at: at(expected),
                    default_time
                }),
                "{quote}"
            );
        }
    }

    #[test]
    fn unknown_ambiguous_or_past_deadlines_are_rejected() {
        for quote in [
            "",
            "sometime next month",
            "soonish",
            "yesterday",
            "tomorrow and Friday",
            "February 30",
            "25:00",
            "13pm",
            "1230",
            "in 20 minutes tomorrow",
            "6.30pm",
        ] {
            assert_eq!(parse_deadline(quote, at(NOW)), None, "{quote}");
        }
        assert_eq!(parse_deadline("today at 9am", at(NOW)), None);
    }
}
