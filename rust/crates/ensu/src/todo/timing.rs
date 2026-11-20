use chrono::{
    Datelike, Days, Duration, NaiveDate, NaiveDateTime, NaiveTime, TimeZone, Timelike, Weekday,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Deadline {
    pub at: NaiveDateTime,
    pub default_time: bool,
    relative: Option<Duration>,
}

impl Deadline {
    pub fn millis(&self, now_ms: i64, zone: &impl TimeZone) -> Option<i64> {
        match self.relative {
            Some(after) => now_ms.checked_add(after.num_milliseconds()),
            None => local_millis(self.at, zone),
        }
    }
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
    bare_hour: Option<(u32, u32)>,
    after: Option<Duration>,
    period: Option<u32>,
    next_week: bool,
}

const END_OF_DAY_HOUR: u32 = 17;

fn past_or_to(words: &[&str]) -> Option<(usize, u32, u32, bool)> {
    let minutes = match (words.first().copied()?, words.get(1).copied()?) {
        ("half", "past") => 30,
        ("quarter", "past") => 15,
        ("quarter", "to") => -15,
        _ => return None,
    };
    let rest = &words[2..];
    let (used, hour, explicit) = match clock(rest) {
        Some((used, time)) if time.minute() == 0 => (used, time.hour(), true),
        Some(_) => return None,
        None => {
            let hour = u32::try_from(number_word(rest.first()?)?).ok()?;
            ((1..=12).contains(&hour)).then_some((1, hour, false))?
        }
    };
    let (hour, minute) = if minutes < 0 {
        let before = if explicit {
            hour.checked_sub(1)?
        } else if hour == 1 {
            12
        } else {
            hour - 1
        };
        (before, 45)
    } else {
        (hour, minutes as u32)
    };
    Some((2 + used, hour, minute, explicit))
}

pub(crate) fn number_word(word: &str) -> Option<i64> {
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

fn bare_clock(word: &str, next: Option<&str>) -> Option<(u32, u32)> {
    if matches!(next, Some("am" | "a.m" | "pm" | "p.m")) {
        return None;
    }
    let (h, m) = word.split_once(':')?;
    if h.starts_with('0') || m.len() != 2 {
        return None;
    }
    let (hour, minute) = (h.parse::<u32>().ok()?, m.parse::<u32>().ok()?);
    ((1..=12).contains(&hour) && minute <= 59).then_some((hour, minute))
}

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
    let separated = digits
        .split_once(':')
        .or_else(|| digits.split_once('.').filter(|_| meridiem.is_some()));
    let (hour, minute) = match separated {
        Some((h, m)) if m.len() == 2 => (h.parse::<u32>().ok()?, m.parse::<u32>().ok()?),
        Some(_) => return None,
        None if digits.contains('.') => return None,
        None if digits.len() == 3 || digits.len() == 4 => {
            meridiem?;
            if !digits.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            let (h, m) = digits.split_at(digits.len() - 2);
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

const SKIPPED: &[&str] = &[
    "at", "on", "by", "the", "this", "of", "around", "about", "before", "until", "till", "due",
    "for", "coming", "o'clock", "oclock",
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
        if let Some((used, hour, minute, explicit)) = past_or_to(&words[i..]) {
            if explicit {
                if parts
                    .time
                    .replace(NaiveTime::from_hms_opt(hour, minute, 0)?)
                    .is_some()
                {
                    return None;
                }
            } else if parts.bare_hour.replace((hour, minute)).is_some() {
                return None;
            }
            i += used;
            continue;
        }
        let end_of_day = match (
            word,
            next,
            words.get(i + 2).copied(),
            words.get(i + 3).copied(),
        ) {
            ("eod" | "cob", ..) => Some(1),
            ("end", Some("of"), Some("day"), _) | ("close", Some("of"), Some("business"), _) => {
                Some(3)
            }
            ("end", Some("of"), Some("the"), Some("day")) => Some(4),
            _ => None,
        };
        if let Some(used) = end_of_day {
            let time = NaiveTime::from_hms_opt(END_OF_DAY_HOUR, 0, 0)?;
            if parts.time.replace(time).is_some() {
                return None;
            }
            i += used;
            continue;
        }
        let amount = if word == "half" && matches!(next, Some("an" | "a")) {
            Some((30, i + 2, true))
        } else {
            number_word(word).map(|n| (n, i + 1, false))
        };
        if let Some((n, unit_at, half_hour)) = amount {
            let unit = words.get(unit_at).copied().unwrap_or("");
            let unit = unit.strip_suffix('s').unwrap_or(unit);
            let after_in =
                words[..i].iter().rev().find(|word| !SKIPPED.contains(word)) == Some(&"in");
            let counted = !matches!(word, "a" | "an" | "one")
                || after_in
                || words.get(unit_at + 1) == Some(&"from");
            let duration = match (unit, half_hour) {
                ("hour", true) => Some(Duration::minutes(n)),
                ("minute" | "min", false) => Some(Duration::minutes(n)),
                ("hour" | "hr", false) => Some(Duration::hours(n)),
                ("day" | "week", false) if !counted => None,
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
        if let Some(bare) = bare_clock(word, next) {
            if parts.bare_hour.replace(bare).is_some() {
                return None;
            }
            i += 1;
            continue;
        }
        if let Some((used, time)) = clock(&words[i..]) {
            if parts.time.replace(time).is_some() {
                return None;
            }
            i += used;
            continue;
        }
        let month_has_day = words.get(i + 2).copied().and_then(day_of_month).is_some();
        let names_day = next.and_then(month).is_some() && !month_has_day
            || next == Some("of") && words.get(i + 2).copied().and_then(month).is_some();
        if let Ok(hour) = word.parse::<u32>()
            && (1..=12).contains(&hour)
            && i > 0
            && matches!(words[i - 1], "at" | "around" | "about" | "by" | "before")
            && !names_day
        {
            if parts.bare_hour.replace((hour, 0)).is_some() {
                return None;
            }
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
            "next" => parts.next_week = true,
            "weekend" => set_day(&mut parts, Day::Weekday(Weekday::Sat))?,
            "week" if parts.next_week => set_day(&mut parts, Day::Weekday(Weekday::Mon))?,
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
            _ if SKIPPED.contains(&word) => {}
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
                } else {
                    return None;
                }
            }
        }
        i += 1;
    }
    Some(parts)
}

fn period_end(period: u32) -> u32 {
    match period {
        9 => 12,
        15 => 18,
        18 => 22,
        _ => 24,
    }
}

fn next_weekday(now: NaiveDateTime, target: Weekday, time: NaiveTime) -> Option<NaiveDate> {
    let today = now.date();
    let offset = (7 + target.num_days_from_monday() - today.weekday().num_days_from_monday()) % 7;
    let offset = if offset == 0 && time <= now.time() {
        7
    } else {
        offset
    };
    today.checked_add_days(Days::new(u64::from(offset)))
}

const TIME_WORDS: &[&str] = &[
    "someday",
    "sometime",
    "soon",
    "later",
    "asap",
    "eventually",
    "today",
    "tonight",
    "tomorrow",
    "tmrw",
    "yesterday",
    "morning",
    "afternoon",
    "evening",
    "night",
    "noon",
    "midday",
    "midnight",
    "week",
    "weekend",
    "weeks",
    "hour",
    "hours",
    "hr",
    "minute",
    "minutes",
    "min",
    "mins",
    "day",
    "days",
    "month",
    "months",
    "year",
    "eod",
    "cob",
    "am",
    "pm",
    "a.m",
    "p.m",
    "o'clock",
    "oclock",
];

pub fn mentions_time(quote: &str) -> bool {
    quote
        .to_lowercase()
        .split(|c: char| c.is_whitespace() || matches!(c, ',' | ';' | '!' | '?'))
        .map(|word| word.trim_matches(|c: char| c == '.' || c == '"' || c == '\''))
        .any(|word| {
            word.chars().any(|c| c.is_ascii_digit())
                || weekday(word).is_some()
                || month(word).is_some()
                || TIME_WORDS.contains(&word)
                || word.ends_with("am") && word[..word.len() - 2].parse::<u32>().is_ok()
        })
}

pub fn parse_deadline(quote: &str, now: NaiveDateTime) -> Option<Deadline> {
    let parts = parse_parts(quote)?;
    if let Some(after) = parts.after {
        if parts.day.is_some() || parts.time.is_some() || parts.bare_hour.is_some() {
            return None;
        }
        return Some(Deadline {
            at: now.checked_add_signed(after)?,
            default_time: false,
            relative: Some(after),
        });
    }
    let today = now.date();
    let end_of_day = NaiveTime::from_hms_opt(23, 59, 0)?;
    let evening = parts.period.is_some_and(|period| period >= 18);
    let night = parts.period.is_some_and(|period| period >= 20);
    let time = match (parts.time, parts.bare_hour) {
        (Some(time), _) if evening && time == NaiveTime::MIN => Some(end_of_day),
        (Some(time), _) if night && time.hour() < 5 => return None,
        (Some(time), _) => Some(time),
        (None, Some((hour, minute))) => {
            let (hour, minute) = match parts.period {
                Some(_) if evening && hour == 12 => {
                    if minute != 0 {
                        return None;
                    }
                    (23, 59)
                }
                Some(_) if night && hour < 5 => return None,
                Some(period) if period >= 12 && hour < 12 => (hour + 12, minute),
                Some(_) => (hour, minute),
                None if hour < 7 => (hour + 12, minute),
                None => (hour, minute),
            };
            Some(NaiveTime::from_hms_opt(hour, minute, 0)?)
        }
        (None, None) => None,
    };
    let date = match parts.day {
        None => None,
        Some(Day::Offset(n)) => Some(today.checked_add_days(Days::new(n))?),
        Some(Day::Weekday(target)) if parts.next_week => {
            let next_monday = 7 - u64::from(today.weekday().num_days_from_monday());
            let offset = next_monday + u64::from(target.num_days_from_monday());
            Some(today.checked_add_days(Days::new(offset))?)
        }
        Some(Day::Weekday(target)) => Some(next_weekday(
            now,
            target,
            time.unwrap_or(NaiveTime::from_hms_opt(
                parts.period.unwrap_or(DEFAULT_HOUR),
                0,
                0,
            )?),
        )?),
        Some(Day::Date { month, day, year }) => {
            let year_now = today.year();
            match year {
                Some(year) => Some(NaiveDate::from_ymd_opt(year, month, day)?),
                None => Some((year_now..=year_now + 8).find_map(|year| {
                    NaiveDate::from_ymd_opt(year, month, day).filter(|date| *date >= today)
                })?),
            }
        }
    };
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
                (
                    now.checked_add_signed(Duration::hours(1))?
                        .min(today.and_time(end_of_day)),
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
            } else if now.hour() < period_end(hour) {
                (
                    now.checked_add_signed(Duration::hours(1))?
                        .min(today.and_time(end_of_day)),
                    false,
                )
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
    (at > now).then_some(Deadline {
        at,
        default_time,
        relative: None,
    })
}

pub fn local_millis(at: NaiveDateTime, zone: &impl TimeZone) -> Option<i64> {
    zone.from_local_datetime(&at)
        .earliest()
        .or_else(|| {
            zone.from_local_datetime(&(at + Duration::hours(1)))
                .earliest()
        })
        .map(|instant| instant.timestamp_millis())
}

pub fn local_time(ms: i64, zone: &impl TimeZone) -> Option<NaiveDateTime> {
    zone.timestamp_millis_opt(ms)
        .single()
        .map(|instant| instant.naive_local())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(s: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M").unwrap()
    }

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
            ("next Friday", "2026-11-20 09:00", true),
            ("this Friday", "2026-11-13 09:00", true),
            ("next Thursday at 3pm", "2026-11-19 15:00", false),
            ("next week", "2026-11-16 09:00", true),
            ("this weekend", "2026-11-14 09:00", true),
            ("next weekend", "2026-11-21 09:00", true),
            ("end of day", "2026-11-12 17:00", false),
            ("by end of the day tomorrow", "2026-11-13 17:00", false),
            ("EOD Friday", "2026-11-13 17:00", false),
            ("close of business", "2026-11-12 17:00", false),
            ("6.30pm", "2026-11-12 18:30", false),
            ("tomorrow at 7.15 am", "2026-11-13 07:15", false),
            ("half past 5", "2026-11-12 17:30", false),
            ("quarter past nine tomorrow", "2026-11-13 09:15", false),
            ("quarter to 1", "2026-11-13 12:45", false),
            ("half past 8pm", "2026-11-12 20:30", false),
            ("in the next 20 minutes", "2026-11-12 14:50", false),
            ("at 5:30", "2026-11-12 17:30", false),
            ("tomorrow 5:30", "2026-11-13 17:30", false),
            ("at 9:15", "2026-11-13 09:15", false),
            ("tomorrow evening at 7:30", "2026-11-13 19:30", false),
            ("at 05:30", "2026-11-13 05:30", false),
            ("by 5 December", "2026-12-05 09:00", true),
            ("before 8 January", "2027-01-08 09:00", true),
            ("by the 5th of December", "2026-12-05 09:00", true),
            ("by 5 on December 6", "2026-12-06 17:00", false),
            ("by 5 Dec 6", "2026-12-06 17:00", false),
            ("tonight at 12", "2026-11-12 23:59", false),
            ("tomorrow night at 12", "2026-11-13 23:59", false),
            ("tonight at 12am", "2026-11-12 23:59", false),
            ("tomorrow night at 12am", "2026-11-13 23:59", false),
            ("this evening at 5", "2026-11-12 17:00", false),
            ("tonight at 9", "2026-11-12 21:00", false),
            ("tonight at 5", "2026-11-12 17:00", false),
            ("at 5:30 tonight", "2026-11-12 17:30", false),
            ("in about a week", "2026-11-19 09:00", true),
            ("in around a day", "2026-11-13 09:00", true),
            ("tomorrow afternoon at 12", "2026-11-13 12:00", false),
            ("in a week", "2026-11-19 09:00", true),
            ("a week from now", "2026-11-19 09:00", true),
            ("in one day", "2026-11-13 09:00", true),
            ("February 29", "2028-02-29 09:00", true),
            ("this morning", "2026-11-13 09:00", false),
        ] {
            assert_eq!(
                parse_deadline(quote, at(NOW)).map(|d| (d.at, d.default_time)),
                Some((at(expected), default_time)),
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
            "6.30",
            "this week",
            "next month",
            "half past",
            "quarter to 15",
            "end of the week",
            "next week Friday",
            "one day",
            "a day",
            "tomorrow night at 12:30",
            "tomorrow night at 1",
            "tomorrow night at 1am",
            "Friday night at 00:30",
            "tomorrow —",
            "tomorrow …",
            "tomorrow 🙏",
            "für tomorrow",
            "día 5",
            "明日",
            "é pm",
            "—pm",
            "5pm 🙏",
        ] {
            assert_eq!(parse_deadline(quote, at(NOW)), None, "{quote}");
        }
        assert_eq!(parse_deadline("today at 9am", at(NOW)), None);
    }

    #[test]
    fn deadlines_resolve_at_other_times_of_the_week_and_year() {
        let resolve = |quote: &str, now: &str| parse_deadline(quote, at(now)).map(|d| d.at);
        for (now, quote, expected) in [
            ("2026-11-19 14:30", "Thursday at 5 PM", "2026-11-19 17:00"),
            (
                "2026-11-19 14:30",
                "this Thursday at 5 PM",
                "2026-11-19 17:00",
            ),
            ("2026-11-19 08:00", "this Thursday", "2026-11-19 09:00"),
            (
                "2026-11-19 14:30",
                "next Thursday at 5 PM",
                "2026-11-26 17:00",
            ),
            ("2026-11-19 14:30", "Thursday at 9 AM", "2026-11-26 09:00"),
            ("2026-11-19 17:00", "Thursday at 5 PM", "2026-11-26 17:00"),
            ("2026-11-19 14:30", "Thursday at 5", "2026-11-19 17:00"),
            ("2026-11-19 14:30", "Thursday evening", "2026-11-19 18:00"),
            ("2026-11-14 08:00", "today", "2026-11-14 09:00"),
            ("2026-11-14 08:00", "at 5", "2026-11-14 17:00"),
            ("2026-11-14 08:00", "at 9", "2026-11-14 09:00"),
            ("2026-11-14 08:00", "this morning", "2026-11-14 09:00"),
            ("2026-11-14 08:00", "tonight", "2026-11-14 20:00"),
            ("2026-11-14 08:00", "Monday", "2026-11-16 09:00"),
            ("2026-11-14 08:00", "Friday", "2026-11-20 09:00"),
            ("2026-11-14 08:00", "next Friday", "2026-11-20 09:00"),
            ("2026-11-15 23:30", "Monday", "2026-11-16 09:00"),
            ("2026-11-15 23:30", "today", "2026-11-15 23:59"),
            ("2026-11-15 23:30", "tonight", "2026-11-15 23:59"),
            ("2026-11-15 23:30", "next Friday", "2026-11-20 09:00"),
            ("2026-11-15 23:30", "tomorrow at 8am", "2026-11-16 08:00"),
            ("2026-11-15 23:30", "in 45 minutes", "2026-11-16 00:15"),
            ("2026-12-31 22:00", "tomorrow", "2027-01-01 09:00"),
            ("2026-12-31 22:00", "in 3 days", "2027-01-03 09:00"),
            ("2026-12-31 22:00", "at 5", "2027-01-01 17:00"),
            ("2026-12-31 22:00", "in 2 hours", "2027-01-01 00:00"),
            ("2026-12-31 22:00", "January 1", "2027-01-01 09:00"),
            ("2026-12-31 22:00", "December 30", "2027-12-30 09:00"),
            ("2026-12-31 22:00", "Saturday", "2027-01-02 09:00"),
            ("2026-12-31 22:00", "next week", "2027-01-04 09:00"),
            ("2028-02-28 10:00", "tomorrow", "2028-02-29 09:00"),
            ("2028-02-28 10:00", "in 2 days", "2028-03-01 09:00"),
            ("2027-02-28 10:00", "tomorrow", "2027-03-01 09:00"),
            ("2027-01-31 10:00", "tomorrow", "2027-02-01 09:00"),
            ("2026-11-12 13:00", "this afternoon", "2026-11-12 15:00"),
            ("2026-11-12 15:30", "this afternoon", "2026-11-12 16:30"),
            ("2026-11-12 19:00", "this afternoon", "2026-11-13 15:00"),
            ("2026-11-12 19:00", "this evening", "2026-11-12 20:00"),
            ("2026-11-12 10:15", "in the morning", "2026-11-12 11:15"),
            ("2026-11-12 14:30", "in the morning", "2026-11-13 09:00"),
            ("2027-06-01 10:00", "Feb 29", "2028-02-29 09:00"),
            ("2028-01-10 10:00", "Feb 29", "2028-02-29 09:00"),
            ("2028-03-01 10:00", "Feb 29", "2032-02-29 09:00"),
            ("2026-12-31 23:30", "January 2", "2027-01-02 09:00"),
            ("2026-12-31 08:00", "December 31", "2026-12-31 09:00"),
        ] {
            assert_eq!(resolve(quote, now), Some(at(expected)), "{quote} at {now}");
        }
        assert_eq!(resolve("February 29 2027", NOW), None);
    }

    #[test]
    fn lengths_of_time_are_added_to_the_instant() {
        let now_ms = 1_800_000_000_000;
        let now = at(NOW);
        let zone = chrono::FixedOffset::east_opt(5 * 3600 + 1800).unwrap();
        let relative = parse_deadline("in 2 hours", now).unwrap();
        assert_eq!(relative.millis(now_ms, &zone), Some(now_ms + 2 * 3_600_000));
        let absolute = parse_deadline("tomorrow at 4 PM", now).unwrap();
        let due = absolute.millis(now_ms, &zone).unwrap();
        assert_eq!(due, at("2026-11-13 10:30").and_utc().timestamp_millis());
        assert_eq!(local_time(due, &zone), Some(absolute.at));
    }
}
