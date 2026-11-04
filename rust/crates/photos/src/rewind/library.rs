use ente_exif::DateTime;

use super::input::{RewindFile, RewindFileType, RewindRequest};
use super::{Error, Result};
use crate::ml_store::MlStore;

const MICROS_PER_SECOND: i64 = 1_000_000;

pub(super) struct Library<'r> {
    files: Vec<&'r RewindFile>,
    year_has_ended: bool,
}

impl<'r> Library<'r> {
    pub(super) fn of_year(request: &'r RewindRequest) -> Result<Self> {
        let start = start_of_year(request.year)?;
        let end = start_of_year(request.year + 1)?;
        let local_now = request.now + i64::from(request.utc_offset_seconds) * MICROS_PER_SECOND;
        Ok(Self {
            files: request
                .files
                .iter()
                .filter(|file| (start..end).contains(&local_time(file)))
                .collect(),
            year_has_ended: local_now >= end,
        })
    }

    pub(super) fn files(&self) -> &[&'r RewindFile] {
        &self.files
    }

    pub(super) fn year_has_ended(&self) -> bool {
        self.year_has_ended
    }

    pub(super) fn ml_coverage(&self, store: &MlStore) -> Result<f32> {
        let indexed = store.db().get_fully_indexed_file_ids(false)?;
        let indexable: Vec<i64> = self
            .files
            .iter()
            .filter(|file| file.file_type != RewindFileType::Other)
            .map(|file| file.id)
            .collect();
        if indexable.is_empty() {
            return Ok(1.0);
        }
        let covered = indexable.iter().filter(|id| indexed.contains(id)).count();
        Ok(covered as f32 / indexable.len() as f32)
    }
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

fn local_time(file: &RewindFile) -> i64 {
    file.local_date_time
        .as_deref()
        .and_then(wall_clock_micros)
        .unwrap_or(file.creation_time + i64::from(file.utc_offset_seconds) * MICROS_PER_SECOND)
}

fn wall_clock_micros(date_time: &str) -> Option<i64> {
    DateTime {
        offset_minutes: Some(0),
        ..DateTime::parse(date_time)?
    }
    .unix_micros()
}
