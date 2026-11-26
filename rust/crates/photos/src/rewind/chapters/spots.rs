use std::cmp::Reverse;
use std::collections::HashSet;

use ente_location::Coordinate;

use super::count;
use crate::rewind::geo::cluster;
use crate::rewind::library::{Library, YearFile};
use crate::rewind::ranking::{Ranking, Spread};
use crate::rewind::report::Spots;

const SPOT_RADIUS_KM: f64 = 0.3;
const SPOT_MINIMUM_DAYS: usize = 3;
const SPOT_MINIMUM_PHOTOS: usize = 5;
const SPOT_RETURN_GAP_DAYS: i64 = 30;
const SPOTS: usize = 3;
const SPOTS_MINIMUM_CANDIDATES: usize = 5;
const SPOTS_CANDIDATES: usize = 18;

pub(in crate::rewind) struct Spot<'l, 'r> {
    pub(in crate::rewind) center: Coordinate,
    pub(in crate::rewind) files: Vec<&'l YearFile<'r>>,
    pub(in crate::rewind) days: usize,
}

pub(in crate::rewind) fn spots(library: &Library<'_>, ranking: &Ranking<'_>) -> Option<Spots> {
    let mut spots: Vec<Spot> = spots_of(library)
        .into_iter()
        .filter(|spot| {
            spot.days >= SPOT_MINIMUM_DAYS
                && spot.files.len() >= SPOT_MINIMUM_PHOTOS
                && visited_a_month_apart(spot)
        })
        .collect();
    if spots.len() < SPOTS {
        return None;
    }
    spots.sort_by_key(|spot| {
        (
            Reverse(spot.files.len()),
            Reverse(spot.days),
            spot.files.first().map(|file| file.file.creation_time),
        )
    });
    spots.truncate(SPOTS);
    let candidates: Vec<Vec<i64>> = spots
        .iter()
        .map(|spot| ranking.best(spot.files.iter().copied(), Spread::Days, SPOTS_CANDIDATES))
        .collect();
    let rounds = candidates.iter().map(Vec::len).max().unwrap_or(0);
    let file_ids: Vec<i64> = (0..rounds)
        .flat_map(|round| {
            candidates
                .iter()
                .filter_map(move |ids| ids.get(round).copied())
        })
        .take(SPOTS_CANDIDATES)
        .collect();
    (file_ids.len() >= SPOTS_MINIMUM_CANDIDATES).then(|| Spots {
        spot_count: count(spots.len()),
        photo_count: count(spots.iter().map(|spot| spot.files.len()).sum()),
        file_ids,
    })
}

fn visited_a_month_apart(spot: &Spot) -> bool {
    let days = spot.files.iter().map(|file| file.day);
    days.clone()
        .min()
        .zip(days.max())
        .is_some_and(|(first, last)| last - first >= SPOT_RETURN_GAP_DAYS)
}

pub(in crate::rewind) fn spots_of<'l, 'r>(library: &'l Library<'r>) -> Vec<Spot<'l, 'r>> {
    let mut located: Vec<(&YearFile, Coordinate)> = library
        .eligible()
        .filter_map(|file| Some((file, file.location()?)))
        .collect();
    located.sort_by_key(|(file, _)| (file.file.creation_time, file.id()));
    let coordinates: Vec<Coordinate> = located.iter().map(|&(_, location)| location).collect();
    cluster(&coordinates, SPOT_RADIUS_KM)
        .into_iter()
        .map(|members| {
            let files: Vec<&YearFile> = members.iter().map(|&member| located[member].0).collect();
            let center = mean(members.iter().map(|&member| located[member].1));
            let days = files
                .iter()
                .map(|file| file.day)
                .collect::<HashSet<_>>()
                .len();
            Spot {
                center,
                files,
                days,
            }
        })
        .collect()
}

fn mean(coordinates: impl ExactSizeIterator<Item = Coordinate>) -> Coordinate {
    let count = coordinates.len() as f64;
    let (latitude, longitude_sin, longitude_cos) = coordinates.fold(
        (0.0, 0.0, 0.0),
        |(latitude, longitude_sin, longitude_cos), point| {
            let (point_sin, point_cos) = point.longitude.to_radians().sin_cos();
            (
                latitude + point.latitude,
                longitude_sin + point_sin,
                longitude_cos + point_cos,
            )
        },
    );
    Coordinate::new(
        latitude / count,
        longitude_sin.atan2(longitude_cos).to_degrees(),
    )
}

#[cfg(test)]
mod tests {
    use ente_location::Coordinate;

    use crate::rewind::fixtures::{daily_photos, located, photos_every, request};
    use crate::rewind::input::RewindFile;
    use crate::rewind::library::Library;
    use crate::rewind::ranking::Ranking;

    use super::{spots, spots_of};

    #[test]
    fn regular_spots_crossing_the_antimeridian_stay_together() {
        for longitude in [179.9995, -179.9995] {
            let files = [52.0, 52.1, 52.2]
                .into_iter()
                .enumerate()
                .flat_map(|(spot, latitude)| {
                    photos_every(spot as i64 * 100 + 1, "2026-01-01T09:00:00", 6, 10)
                        .into_iter()
                        .enumerate()
                        .map(move |(day, file)| {
                            located(
                                file,
                                latitude,
                                if day % 2 == 0 { longitude } else { -longitude },
                            )
                        })
                })
                .collect();
            let request = request(files);
            let state = crate::rewind::compute_rewind(&request, None, None, None).unwrap();
            let crate::rewind::RewindStatus::Ready { report } = state.status else {
                panic!("the rewind should be ready");
            };
            let spots = report.spots.expect("three regular spots should be shown");
            assert_eq!(spots.spot_count, 3);
            assert_eq!(spots.photo_count, 18);
            assert_eq!(spots.file_ids.len(), 18);

            let library = Library::of_year(&request).unwrap();
            for spot in spots_of(&library) {
                assert!(
                    crate::rewind::geo::distance_km(
                        spot.center,
                        Coordinate::new(spot.center.latitude, 180.0)
                    ) < 0.001
                );
            }
        }
    }

    fn spot(first_id: i64, first_day: &str, visits: i64, latitude: f64) -> Vec<RewindFile> {
        photos_every(first_id, first_day, visits, 10)
            .into_iter()
            .map(|file| located(file, latitude, 4.9))
            .collect()
    }

    fn holiday(first_id: i64, first_day: &str, days: i64, latitude: f64) -> Vec<RewindFile> {
        daily_photos(first_id, first_day, days)
            .into_iter()
            .map(|file| located(file, latitude, 4.9))
            .collect()
    }

    #[test]
    fn the_three_biggest_spots_interleave_their_best_photos() {
        let mut files = spot(1, "2026-01-01T09:00:00", 8, 52.0);
        files.extend(spot(101, "2026-02-01T09:00:00", 6, 52.1));
        files.extend(spot(201, "2026-03-01T09:00:00", 5, 52.2));
        files.extend(spot(301, "2026-04-01T09:00:00", 7, 52.3));
        let mut same_day: Vec<RewindFile> = spot(401, "2026-05-01T09:00:00", 1, 52.4);
        for id in 402..=420 {
            let mut file = same_day[0].clone();
            file.id = id;
            file.creation_time += id * 60_000_000;
            same_day.push(file);
        }
        files.extend(same_day);
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        let spots = spots(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(spots.spot_count, 3);
        assert_eq!(spots.photo_count, 8 + 7 + 6);
        assert_eq!(&spots.file_ids[..6], [1, 301, 101, 2, 302, 102]);
        assert_eq!(spots.file_ids.len(), 18);
    }

    #[test]
    fn fewer_than_three_regular_spots_skip_the_chapter() {
        let mut files = spot(1, "2026-01-01T09:00:00", 8, 52.0);
        files.extend(spot(101, "2026-02-01T09:00:00", 6, 52.1));
        files.extend(spot(201, "2026-03-01T09:00:00", 4, 52.2));
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        assert_eq!(spots(&library, &Ranking::new(None, None)), None);
    }

    #[test]
    fn spots_never_revisited_a_month_later_are_skipped() {
        let mut files = spot(1, "2026-01-01T09:00:00", 6, 52.0);
        files.extend(spot(101, "2026-02-01T09:00:00", 5, 52.1));
        files.extend(spot(201, "2026-03-01T09:00:00", 5, 52.2));
        files.extend(holiday(301, "2026-07-01T09:00:00", 30, 52.3));
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        let spots = spots(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(spots.spot_count, 3);
        assert_eq!(spots.photo_count, 6 + 5 + 5);
        assert!(spots.file_ids.iter().all(|&id| id < 301));
    }

    #[test]
    fn a_spot_revisited_thirty_days_later_counts() {
        let mut files = spot(1, "2026-01-01T09:00:00", 6, 52.0);
        files.extend(spot(101, "2026-02-01T09:00:00", 5, 52.1));
        files.extend(holiday(301, "2026-07-01T09:00:00", 31, 52.3));
        let request = request(files);
        let library = Library::of_year(&request).unwrap();

        let spots = spots(&library, &Ranking::new(None, None)).unwrap();

        assert_eq!(spots.spot_count, 3);
        assert_eq!(spots.photo_count, 6 + 5 + 31);
    }
}
