pub(super) const MICROS_PER_SECOND: i64 = 1_000_000;
pub(super) const MICROS_PER_MINUTE: i64 = 60 * MICROS_PER_SECOND;
pub(super) const MICROS_PER_DAY: i64 = 24 * 60 * MICROS_PER_MINUTE;

const DAYS_PER_ERA: i64 = 146_097;
const DAYS_FROM_ERA_START_TO_UNIX_EPOCH: i64 = 719_468;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct LocalDate {
    pub year: i32,
    pub month: i32,
    pub day: i32,
}

impl LocalDate {
    pub(super) fn new(year: i32, month: i32, day: i32) -> Self {
        let months = i64::from(year) * 12 + i64::from(month) - 1;
        let first_of_month = Self {
            year: months.div_euclid(12) as i32,
            month: months.rem_euclid(12) as i32 + 1,
            day: 1,
        };
        first_of_month.plus_days(i64::from(day) - 1)
    }

    pub(super) fn from_days(days_since_epoch: i64) -> Self {
        let days = days_since_epoch + DAYS_FROM_ERA_START_TO_UNIX_EPOCH;
        let era = days.div_euclid(DAYS_PER_ERA);
        let day_of_era = days.rem_euclid(DAYS_PER_ERA);
        let year_of_era =
            (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
        let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
        let shifted_month = (5 * day_of_year + 2) / 153;
        let day = day_of_year - (153 * shifted_month + 2) / 5 + 1;
        let month = if shifted_month < 10 {
            shifted_month + 3
        } else {
            shifted_month - 9
        };
        Self {
            year: (era * 400 + year_of_era + i64::from(month <= 2)) as i32,
            month: month as i32,
            day: day as i32,
        }
    }

    pub(super) fn days_since_epoch(self) -> i64 {
        let year = i64::from(self.year) - i64::from(self.month <= 2);
        let era = year.div_euclid(400);
        let year_of_era = year.rem_euclid(400);
        let month = i64::from(self.month);
        let shifted_month = if month > 2 { month - 3 } else { month + 9 };
        let day_of_year = (153 * shifted_month + 2) / 5 + i64::from(self.day) - 1;
        let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
        era * DAYS_PER_ERA + day_of_era - DAYS_FROM_ERA_START_TO_UNIX_EPOCH
    }

    pub(super) fn of_local_time(local_micros: i64) -> Self {
        Self::from_days(local_micros.div_euclid(MICROS_PER_DAY))
    }

    pub(super) fn plus_days(self, days: i64) -> Self {
        Self::from_days(self.days_since_epoch() + days)
    }

    pub(super) fn days_until(self, other: Self) -> i64 {
        other.days_since_epoch() - self.days_since_epoch()
    }

    pub(super) fn weekday(self) -> i64 {
        (self.days_since_epoch() + 3).rem_euclid(7) + 1
    }

    pub(super) fn week_of_year(self) -> i64 {
        Self::new(self.year, 1, 1).days_until(self) / 7 + 1
    }

    pub(super) fn is_in_leap_year(self) -> bool {
        self.year % 4 == 0 && (self.year % 100 != 0 || self.year % 400 == 0)
    }
}

pub(super) struct Anniversary {
    pub(super) days_from_today: i64,
    pub(super) years_ago: i32,
}

pub(super) fn upcoming_anniversary(
    date: LocalDate,
    today: LocalDate,
    window_days: i64,
) -> Option<Anniversary> {
    [today.year, today.year + 1].into_iter().find_map(|year| {
        let days_from_today = today.days_until(LocalDate::new(year, date.month, date.day));
        (0..window_days)
            .contains(&days_from_today)
            .then_some(Anniversary {
                days_from_today,
                years_ago: year - date.year,
            })
    })
}

#[cfg(test)]
mod tests {
    use super::{LocalDate, upcoming_anniversary};

    fn date(year: i32, month: i32, day: i32) -> LocalDate {
        LocalDate { year, month, day }
    }

    #[test]
    fn days_round_trip_across_centuries_and_before_the_epoch() {
        for (value, days) in [
            (date(1970, 1, 1), 0),
            (date(1969, 12, 31), -1),
            (date(2000, 2, 29), 11_016),
            (date(1900, 3, 1), -25_508),
            (date(2400, 12, 31), 157_419),
        ] {
            assert_eq!(value.days_since_epoch(), days, "{value:?}");
            assert_eq!(LocalDate::from_days(days), value);
        }
    }

    #[test]
    fn new_rolls_overflowing_months_and_days_like_dart() {
        assert_eq!(LocalDate::new(2025, 13, 1), date(2026, 1, 1));
        assert_eq!(LocalDate::new(2025, 0, 1), date(2024, 12, 1));
        assert_eq!(LocalDate::new(2024, 3, 0), date(2024, 2, 29));
        assert_eq!(LocalDate::new(2025, 2, 29), date(2025, 3, 1));
        assert_eq!(LocalDate::new(2025, 1, 32), date(2025, 2, 1));
    }

    #[test]
    fn weeks_are_seven_day_blocks_from_january_first() {
        assert_eq!(date(2026, 10, 26).weekday(), 1);
        assert_eq!(date(2026, 11, 1).weekday(), 7);
        assert_eq!(date(2026, 1, 7).week_of_year(), 1);
        assert_eq!(date(2026, 1, 8).week_of_year(), 2);
        assert_eq!(date(2024, 12, 30).week_of_year(), 53);
    }

    #[test]
    fn anniversaries_cross_the_year_end_and_move_leap_days_to_march_first() {
        let new_year = upcoming_anniversary(date(2020, 1, 1), date(2025, 12, 31), 3).unwrap();
        assert_eq!((new_year.days_from_today, new_year.years_ago), (1, 6));

        let leap_day = upcoming_anniversary(date(2024, 2, 29), date(2025, 2, 28), 3).unwrap();
        assert_eq!((leap_day.days_from_today, leap_day.years_ago), (1, 1));

        assert!(upcoming_anniversary(date(2020, 10, 26), date(2026, 10, 28), 3).is_none());
        assert!(upcoming_anniversary(date(2020, 11, 1), date(2026, 10, 29), 3).is_none());
    }
}
