use std::collections::{HashMap, HashSet};

use ente_exif::DateTime;
use ente_location::Coordinate;

use super::input::{RewindFile, RewindFileType, RewindRequest, RewindVisibility};
use super::{Error, Result};
use crate::memories::LocalDate;
use crate::ml_store::MlStore;

const MICROS_PER_SECOND: i64 = 1_000_000;
const MICROS_PER_HOUR: i64 = 3600 * MICROS_PER_SECOND;
const MICROS_PER_DAY: i64 = 24 * MICROS_PER_HOUR;

pub(super) struct Library<'r> {
    files: Vec<YearFile<'r>>,
    positions: HashMap<i64, usize>,
    start: i64,
    year_has_ended: bool,
}

#[derive(Clone, Copy, Debug)]
pub(super) struct YearFile<'r> {
    pub(super) file: &'r RewindFile,
    pub(super) local_time: i64,
    pub(super) day: i64,
    pub(super) month: u32,
    pub(super) day_of_month: u32,
    pub(super) weekday: u32,
    pub(super) hour: u32,
}

impl<'r> Library<'r> {
    pub(super) fn of_year(request: &'r RewindRequest) -> Result<Self> {
        let start = start_of_year(request.year)?;
        let end = start_of_year(request.year + 1)?;
        let local_now = request.now + i64::from(request.utc_offset_seconds) * MICROS_PER_SECOND;
        let mut seen = HashSet::new();
        let files: Vec<YearFile<'r>> = request
            .files
            .iter()
            .filter(|file| seen.insert(file.id))
            .map(YearFile::new)
            .filter(|file| (start..end).contains(&file.local_time))
            .collect();
        let positions = files
            .iter()
            .enumerate()
            .map(|(position, file)| (file.file.id, position))
            .collect();
        Ok(Self {
            files,
            positions,
            start,
            year_has_ended: local_now >= end,
        })
    }

    pub(super) fn files(&self) -> &[YearFile<'r>] {
        &self.files
    }

    pub(super) fn get(&self, id: i64) -> Option<&YearFile<'r>> {
        self.positions
            .get(&id)
            .and_then(|&position| self.files.get(position))
    }

    pub(super) fn eligible(&self) -> impl Iterator<Item = &YearFile<'r>> {
        self.files.iter().filter(|file| file.is_eligible())
    }

    pub(super) fn taken(&self) -> impl Iterator<Item = &YearFile<'r>> {
        self.files.iter().filter(|file| file.is_taken())
    }

    pub(super) fn start(&self) -> i64 {
        self.start
    }

    pub(super) fn year_has_ended(&self) -> bool {
        self.year_has_ended
    }

    pub(super) fn ml_coverage(&self, store: &MlStore) -> Result<f32> {
        let indexed = store.db().get_fully_indexed_file_ids(false)?;
        let indexable: Vec<i64> = self
            .files
            .iter()
            .filter(|file| file.file.file_type != RewindFileType::Other)
            .map(|file| file.file.id)
            .collect();
        if indexable.is_empty() {
            return Ok(1.0);
        }
        let covered = indexable.iter().filter(|id| indexed.contains(id)).count();
        Ok(covered as f32 / indexable.len() as f32)
    }
}

impl<'r> YearFile<'r> {
    fn new(file: &'r RewindFile) -> Self {
        let local_time = local_time(file);
        let day = local_time.div_euclid(MICROS_PER_DAY);
        let date = LocalDate::of_local_time(local_time);
        Self {
            file,
            local_time,
            day,
            month: date.month.unsigned_abs(),
            day_of_month: date.day.unsigned_abs(),
            weekday: ((day + 3).rem_euclid(7) + 1) as u32,
            hour: (local_time.rem_euclid(MICROS_PER_DAY) / MICROS_PER_HOUR) as u32,
        }
    }

    pub(super) fn id(&self) -> i64 {
        self.file.id
    }

    pub(super) fn is_eligible(&self) -> bool {
        self.file.visibility != RewindVisibility::Hidden
            && self.file.file_type != RewindFileType::Other
    }

    pub(super) fn is_taken(&self) -> bool {
        self.is_eligible() && !self.file.is_junk
    }

    pub(super) fn is_image(&self) -> bool {
        matches!(
            self.file.file_type,
            RewindFileType::Image | RewindFileType::LivePhoto
        )
    }

    pub(super) fn location(&self) -> Option<Coordinate> {
        self.file
            .location
            .map(|location| Coordinate::new(location.latitude, location.longitude))
            .filter(|coordinate| coordinate.is_valid())
    }
}

pub(super) fn local_time(file: &RewindFile) -> i64 {
    file.local_date_time
        .as_deref()
        .and_then(wall_clock_micros)
        .unwrap_or(file.creation_time + i64::from(file.utc_offset_seconds) * MICROS_PER_SECOND)
}

fn start_of_year(year: i32) -> Result<i64> {
    u16::try_from(year)
        .ok()
        .and_then(|year| {
            DateTime {
                year,
                month: 1,
                day: 1,
                hour: 0,
                minute: 0,
                second: 0,
                nanosecond: 0,
                offset_minutes: Some(0),
            }
            .unix_micros()
        })
        .ok_or(Error::UnsupportedYear(year))
}

fn wall_clock_micros(date_time: &str) -> Option<i64> {
    DateTime {
        offset_minutes: Some(0),
        ..DateTime::parse(date_time)?
    }
    .unix_micros()
}
