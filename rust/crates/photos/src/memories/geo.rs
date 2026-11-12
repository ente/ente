use std::collections::HashMap;
use std::f64::consts::PI;

use ente_location::Coordinate;

use super::photo::Photo;

const EARTH_RADIUS_KM: f64 = 6371.0;
const KILOMETERS_PER_DEGREE: f64 = 111.16;
const GRID_MAX_LATITUDE: f64 = 80.0;
const GRID_CELL_MARGIN: f64 = 1.01;

#[derive(Clone, Copy, Debug)]
pub(super) struct Located<'p> {
    pub(super) photo: &'p Photo,
    pub(super) location: Coordinate,
}

#[derive(Debug)]
pub(super) struct Cluster<'p> {
    pub(super) members: Vec<Located<'p>>,
    latitude_sum: f64,
    longitude_sum: f64,
    pub(super) center: Coordinate,
}

impl<'p> Cluster<'p> {
    fn new(member: Located<'p>) -> Self {
        Self {
            members: vec![member],
            latitude_sum: member.location.latitude,
            longitude_sum: member.location.longitude,
            center: member.location,
        }
    }

    pub(super) fn from_members(members: Vec<Located<'p>>) -> Self {
        let mut cluster = Self {
            members: Vec::new(),
            latitude_sum: 0.0,
            longitude_sum: 0.0,
            center: Coordinate::new(0.0, 0.0),
        };
        for member in members {
            cluster.add(member);
        }
        cluster
    }

    fn add(&mut self, member: Located<'p>) {
        self.members.push(member);
        self.latitude_sum += member.location.latitude;
        self.longitude_sum += member.location.longitude;
        self.recenter();
    }

    pub(super) fn absorb(&mut self, other: Cluster<'p>) {
        self.members.extend(other.members);
        self.latitude_sum += other.latitude_sum;
        self.longitude_sum += other.longitude_sum;
        self.recenter();
    }

    pub(super) fn first_creation_time(&self) -> i64 {
        self.members
            .iter()
            .map(|member| member.photo.creation_time)
            .min()
            .unwrap_or_default()
    }

    pub(super) fn last_creation_time(&self) -> i64 {
        self.members
            .iter()
            .map(|member| member.photo.creation_time)
            .max()
            .unwrap_or_default()
    }

    fn recenter(&mut self) {
        let count = self.members.len() as f64;
        self.center = Coordinate::new(self.latitude_sum / count, self.longitude_sum / count);
    }
}

pub(super) fn located(photos: &[Photo]) -> Vec<Located<'_>> {
    photos
        .iter()
        .filter_map(|photo| photo.location.map(|location| Located { photo, location }))
        .collect()
}

pub(super) fn cluster_by_location<'p>(
    members: impl IntoIterator<Item = Located<'p>>,
    radius_km: f64,
) -> Vec<Cluster<'p>> {
    let mut clusters: Vec<Cluster> = Vec::new();
    let mut grid = Grid::for_ellipses(radius_km);
    for member in members {
        let nearby = grid.first_near(member.location, |&id| {
            is_within(clusters[id].center, member.location, radius_km)
        });
        match nearby {
            Some(id) => {
                let center = clusters[id].center;
                clusters[id].add(member);
                grid.relocate(id, center, clusters[id].center);
            }
            None => {
                grid.insert(clusters.len(), member.location);
                clusters.push(Cluster::new(member));
            }
        }
    }
    clusters
}

pub(super) fn merge_nearby_clusters(
    clusters: Vec<Cluster<'_>>,
    radius_km: f64,
) -> Vec<Cluster<'_>> {
    let mut centers: Vec<Coordinate> = clusters.iter().map(|cluster| cluster.center).collect();
    let mut grid = Grid::for_great_circles(radius_km);
    for (id, &center) in centers.iter().enumerate() {
        grid.insert(id, center);
    }
    let mut clusters: Vec<Option<Cluster>> = clusters.into_iter().map(Some).collect();
    let mut into = 0;
    while into < clusters.len() {
        let nearby = clusters[into].as_ref().and_then(|_| {
            grid.first_near(centers[into], |&other| {
                other != into
                    && distance_km(centers[into.min(other)], centers[into.max(other)]) <= radius_km
            })
        });
        let Some(other) = nearby else {
            into += 1;
            continue;
        };
        let (kept, absorbed) = (into.min(other), into.max(other));
        grid.remove(absorbed, centers[absorbed]);
        let absorbed = clusters[absorbed].take();
        if let (Some(cluster), Some(absorbed)) = (clusters[kept].as_mut(), absorbed) {
            cluster.absorb(absorbed);
            grid.relocate(kept, centers[kept], cluster.center);
            centers[kept] = cluster.center;
        }
        into = kept;
    }
    clusters.into_iter().flatten().collect()
}

struct Grid {
    row_height: f64,
    column_width: f64,
    cells: HashMap<(i64, i64), Vec<usize>>,
    off_grid: Vec<usize>,
}

impl Grid {
    fn for_ellipses(radius_km: f64) -> Self {
        let longitude_reach = radius_km / KILOMETERS_PER_DEGREE;
        Self::new(
            longitude_reach / GRID_MAX_LATITUDE.to_radians().cos(),
            longitude_reach,
        )
    }

    fn for_great_circles(radius_km: f64) -> Self {
        let half_angle = radius_km / (2.0 * EARTH_RADIUS_KM);
        let longitude_half_angle = (half_angle.sin() / GRID_MAX_LATITUDE.to_radians().cos())
            .min(1.0)
            .asin();
        Self::new(
            (2.0 * half_angle).to_degrees(),
            (2.0 * longitude_half_angle).to_degrees(),
        )
    }

    fn new(latitude_reach: f64, longitude_reach: f64) -> Self {
        Self {
            row_height: latitude_reach * GRID_CELL_MARGIN,
            column_width: longitude_reach * GRID_CELL_MARGIN,
            cells: HashMap::new(),
            off_grid: Vec::new(),
        }
    }

    fn cell(&self, at: Coordinate) -> Option<(i64, i64)> {
        (at.latitude.abs() <= GRID_MAX_LATITUDE && at.longitude.abs() <= 180.0 - self.column_width)
            .then(|| {
                (
                    (at.latitude / self.row_height).floor() as i64,
                    (at.longitude / self.column_width).floor() as i64,
                )
            })
    }

    fn insert(&mut self, id: usize, at: Coordinate) {
        match self.cell(at) {
            Some(cell) => self.cells.entry(cell).or_default().push(id),
            None => self.off_grid.push(id),
        }
    }

    fn remove(&mut self, id: usize, at: Coordinate) {
        let ids = match self.cell(at) {
            Some(cell) => self.cells.get_mut(&cell),
            None => Some(&mut self.off_grid),
        };
        if let Some(ids) = ids {
            ids.retain(|&other| other != id);
        }
    }

    fn relocate(&mut self, id: usize, from: Coordinate, to: Coordinate) {
        if self.cell(from) != self.cell(to) {
            self.remove(id, from);
            self.insert(id, to);
        }
    }

    fn first_near(&self, at: Coordinate, matches: impl FnMut(&usize) -> bool) -> Option<usize> {
        let nearby: Vec<&Vec<usize>> = match self.cell(at) {
            Some((row, column)) => (row.saturating_sub(1)..=row.saturating_add(1))
                .flat_map(|row| {
                    (column.saturating_sub(1)..=column.saturating_add(1))
                        .map(move |column| (row, column))
                })
                .filter_map(|cell| self.cells.get(&cell))
                .collect(),
            None => self.cells.values().collect(),
        };
        nearby
            .into_iter()
            .flatten()
            .chain(&self.off_grid)
            .copied()
            .filter(matches)
            .min()
    }
}

pub(super) fn mean_location(members: &[Located]) -> Coordinate {
    let (latitude_sum, longitude_sum) =
        members
            .iter()
            .fold((0.0, 0.0), |(latitude, longitude), member| {
                (
                    latitude + member.location.latitude,
                    longitude + member.location.longitude,
                )
            });
    let count = members.len() as f64;
    Coordinate::new(latitude_sum / count, longitude_sum / count)
}

pub(super) fn distance_km(from: Coordinate, to: Coordinate) -> f64 {
    let latitude_from = from.latitude * (PI / 180.0);
    let latitude_to = to.latitude * (PI / 180.0);
    let longitude_from = from.longitude * (PI / 180.0);
    let longitude_to = to.longitude * (PI / 180.0);
    let half_latitude = (latitude_to - latitude_from) / 2.0;
    let half_longitude = (longitude_to - longitude_from) / 2.0;
    let a = half_latitude.sin() * half_latitude.sin()
        + latitude_from.cos() * latitude_to.cos() * half_longitude.sin() * half_longitude.sin();
    EARTH_RADIUS_KM * (2.0 * a.sqrt().atan2((1.0 - a).sqrt()))
}

pub(super) fn is_within(center: Coordinate, point: Coordinate, radius_km: f64) -> bool {
    let latitude_scale = 1.0 / (center.latitude * (PI / 180.0)).cos();
    let latitude_radius = (radius_km * latitude_scale) / KILOMETERS_PER_DEGREE;
    let longitude_radius = radius_km / KILOMETERS_PER_DEGREE;
    let latitude_delta = center.latitude - point.latitude;
    let longitude_delta = center.longitude - point.longitude;
    (latitude_delta * latitude_delta) / (latitude_radius * latitude_radius)
        + (longitude_delta * longitude_delta) / (longitude_radius * longitude_radius)
        <= 1.0
}

pub(super) fn two_decimals(value: f64) -> String {
    let eighths = value * 8.0;
    let is_tie = eighths.fract() == 0.0 && eighths.rem_euclid(2.0) == 1.0;
    if !is_tie {
        return format!("{value:.2}");
    }
    let hundredths = (value.abs() * 100.0).round() as i64;
    let sign = if value < 0.0 { "-" } else { "" };
    format!("{sign}{}.{:02}", hundredths / 100, hundredths % 100)
}

#[cfg(test)]
mod tests {
    use ente_location::Coordinate;

    use super::{
        Cluster, Located, cluster_by_location, distance_km, is_within, located,
        merge_nearby_clusters, two_decimals,
    };
    use crate::memories::calendar::LocalDate;
    use crate::memories::photo::Photo;
    use crate::memories::rng::Rng;

    fn photo(id: i64, location: Coordinate) -> Photo {
        Photo {
            id,
            creation_time: id,
            local_time: id,
            date: LocalDate::of_local_time(id),
            collection_id: None,
            location: Some(location),
            shared: false,
        }
    }

    fn scattered_photos(count: i64) -> Vec<Photo> {
        let anchors = [
            (52.37, 4.89, 0.02),
            (52.39, 4.92, 0.003),
            (40.71, -74.0, 0.3),
            (-33.87, 151.21, 0.05),
            (64.15, -21.94, 0.05),
            (79.99, 15.65, 0.02),
            (89.99, 0.0, 0.05),
            (-89.99, 120.0, 0.05),
            (-16.5, 179.995, 0.01),
            (-16.5, -179.995, 0.01),
            (10.0, 179.9, 0.3),
            (0.0, 0.0, 2.0),
        ];
        let mut rng = Rng::new(11);
        (0..count)
            .map(|id| {
                let (latitude, longitude, spread) = anchors[rng.below(anchors.len())];
                let mut offset = || spread * (rng.below(2_000_001) as f64 / 1_000_000.0 - 1.0);
                photo(
                    id,
                    Coordinate::new(latitude + offset(), longitude + offset()),
                )
            })
            .collect()
    }

    fn linear_clusters<'p>(members: &[Located<'p>], radius_km: f64) -> Vec<Cluster<'p>> {
        let mut clusters: Vec<Cluster> = Vec::new();
        for &member in members {
            match clusters
                .iter_mut()
                .find(|cluster| is_within(cluster.center, member.location, radius_km))
            {
                Some(cluster) => cluster.add(member),
                None => clusters.push(Cluster::new(member)),
            }
        }
        clusters
    }

    fn pairwise_merged(mut clusters: Vec<Cluster<'_>>, radius_km: f64) -> Vec<Cluster<'_>> {
        while let Some((into, from)) = (0..clusters.len()).find_map(|into| {
            (into + 1..clusters.len())
                .find(|&from| {
                    distance_km(clusters[into].center, clusters[from].center) <= radius_km
                })
                .map(|from| (into, from))
        }) {
            let merged = clusters.remove(from);
            clusters[into].absorb(merged);
        }
        clusters
    }

    fn member_ids(cluster: &Cluster) -> Vec<i64> {
        cluster
            .members
            .iter()
            .map(|member| member.photo.id)
            .collect()
    }

    fn summary(clusters: &[Cluster]) -> Vec<(Vec<i64>, [u64; 2])> {
        clusters
            .iter()
            .map(|cluster| {
                (
                    member_ids(cluster),
                    [
                        cluster.center.latitude.to_bits(),
                        cluster.center.longitude.to_bits(),
                    ],
                )
            })
            .collect()
    }

    #[test]
    fn grid_clustering_and_merging_match_plain_scans_over_every_pair() {
        let photos = scattered_photos(1500);
        let members = located(&photos);
        for (radius_km, merge_radius_km) in [(0.6, 1.5), (25.0, 25.0)] {
            let clusters = cluster_by_location(members.iter().copied(), radius_km);
            let expected = linear_clusters(&members, radius_km);
            assert_eq!(summary(&clusters), summary(&expected));
            let expected = pairwise_merged(expected, merge_radius_km);
            assert!(expected.len() < clusters.len());
            assert_eq!(
                summary(&merge_nearby_clusters(clusters, merge_radius_km)),
                summary(&expected)
            );
        }
    }

    #[test]
    fn a_merge_that_moves_a_center_next_to_an_earlier_cluster_merges_that_one_too() {
        let kilometers = |north: f64, east: f64| Coordinate::new(north / 111.195, east / 111.195);
        let photos = [
            photo(1, kilometers(0.0, 0.0)),
            photo(2, kilometers(0.7, 1.45)),
            photo(3, kilometers(-0.7, 1.45)),
            photo(4, kilometers(0.0, 5.0)),
        ];
        let clusters = || located(&photos).into_iter().map(Cluster::new).collect();

        let merged = merge_nearby_clusters(clusters(), 1.5);

        assert_eq!(summary(&merged), summary(&pairwise_merged(clusters(), 1.5)));
        let members: Vec<Vec<i64>> = merged.iter().map(member_ids).collect();
        assert_eq!(members, [vec![1, 2, 3], vec![4]]);
    }

    #[test]
    fn merging_reaches_across_the_antimeridian_and_the_poles() {
        let photos = [
            photo(1, Coordinate::new(-16.5, 179.9999)),
            photo(2, Coordinate::new(-16.5, -179.9999)),
            photo(3, Coordinate::new(89.995, 0.0)),
            photo(4, Coordinate::new(89.995, 120.0)),
            photo(5, Coordinate::new(89.995, -120.0)),
        ];
        let clusters = cluster_by_location(located(&photos), 0.6);
        assert_eq!(clusters.len(), 5);

        let merged = merge_nearby_clusters(clusters, 1.5);

        let members: Vec<Vec<i64>> = merged.iter().map(member_ids).collect();
        assert_eq!(members, [vec![1, 2], vec![3, 4, 5]]);
    }

    #[test]
    fn two_decimals_round_like_dart_including_exact_ties() {
        for (value, expected) in [
            (0.125, "0.13"),
            (0.375, "0.38"),
            (0.625, "0.63"),
            (1.125, "1.13"),
            (-0.125, "-0.13"),
            (37.125, "37.13"),
            (-122.375, "-122.38"),
            (2.5, "2.50"),
            (0.005, "0.01"),
            (1.005, "1.00"),
            (0.145, "0.14"),
            (-0.001, "-0.00"),
            (-0.0, "-0.00"),
            (179.995, "180.00"),
            (48.8566, "48.86"),
        ] {
            assert_eq!(two_decimals(value), expected, "{value}");
        }
    }

    #[test]
    fn distances_use_the_haversine_great_circle_and_an_ellipse_for_radius_checks() {
        let paris = Coordinate::new(48.8566, 2.3522);
        let london = Coordinate::new(51.5074, -0.1278);
        assert!((distance_km(paris, london) - 343.5).abs() < 1.0);
        assert!(is_within(paris, Coordinate::new(48.95, 2.3522), 25.0));
        assert!(!is_within(paris, Coordinate::new(48.8566, 2.70), 25.0));
    }
}
