use ente_exif::DateTime;
use ente_location::Coordinate;

use super::calendar::{LocalDate, MICROS_PER_SECOND};
use super::input::MemoryFile;

#[derive(Debug)]
pub(super) struct Photo {
    pub(super) id: i64,
    pub(super) creation_time: i64,
    pub(super) local_time: i64,
    pub(super) date: LocalDate,
    pub(super) collection_id: Option<i64>,
    pub(super) location: Option<Coordinate>,
}

pub(super) fn prepare(files: &[MemoryFile]) -> Vec<Photo> {
    let mut photos: Vec<Photo> = files.iter().map(Photo::new).collect();
    photos.sort_by_key(|photo| (photo.creation_time, photo.id));
    photos
}

pub(super) fn sort_chronologically(photos: &mut [&Photo]) {
    photos.sort_by_key(|photo| (photo.creation_time, photo.id));
}

impl Photo {
    fn new(file: &MemoryFile) -> Self {
        let local_time = file
            .local_date_time
            .as_deref()
            .and_then(wall_clock_micros)
            .unwrap_or(file.creation_time + i64::from(file.utc_offset_seconds) * MICROS_PER_SECOND);
        Self {
            id: file.id,
            creation_time: file.creation_time,
            local_time,
            date: LocalDate::of_local_time(local_time),
            collection_id: file.collection_id,
            location: file
                .location
                .filter(|location| location.latitude != 0.0 || location.longitude != 0.0),
        }
    }
}

fn wall_clock_micros(date_time: &str) -> Option<i64> {
    DateTime {
        offset_minutes: Some(0),
        ..DateTime::parse(date_time)?
    }
    .unix_micros()
}

#[cfg(test)]
mod tests {
    use super::prepare;
    use crate::memories::calendar::LocalDate;
    use crate::memories::tests::{file, micros};

    #[test]
    fn local_dates_prefer_the_capture_wall_clock_and_fall_back_to_the_device_offset() {
        let creation_time = micros("2024-03-10T23:30:00");
        let with_wall_clock = |local_date_time: &str| {
            let mut photo = file(1, "2024-03-10T23:30:00");
            photo.local_date_time = Some(local_date_time.to_owned());
            photo.utc_offset_seconds = 3600;
            prepare(&[photo]).remove(0)
        };

        let tokyo = with_wall_clock("2024-03-11T08:30:00.000");
        assert_eq!(tokyo.date, LocalDate::new(2024, 3, 11));
        assert_eq!(tokyo.creation_time, creation_time);

        assert_eq!(
            with_wall_clock("2024-03-10T18:30:00-05:00").date,
            LocalDate::new(2024, 3, 10)
        );
        assert_eq!(
            with_wall_clock("not a date").date,
            LocalDate::new(2024, 3, 11)
        );

        let mut without_wall_clock = file(2, "2024-03-10T23:30:00");
        without_wall_clock.utc_offset_seconds = -3600;
        assert_eq!(
            prepare(&[without_wall_clock])[0].date,
            LocalDate::new(2024, 3, 10)
        );
    }

    #[test]
    fn photos_are_ordered_by_creation_time_then_id() {
        let photos = prepare(&[
            file(3, "2024-01-02T00:00:00"),
            file(2, "2024-01-01T00:00:00"),
            file(1, "2024-01-02T00:00:00"),
        ]);
        let ids: Vec<i64> = photos.iter().map(|photo| photo.id).collect();
        assert_eq!(ids, [2, 1, 3]);
    }
}
