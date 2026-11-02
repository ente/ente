use std::f64::consts::PI;

use ente_location::Coordinate;

use super::photo::Photo;

const EARTH_RADIUS_KM: f64 = 6371.0;
const KILOMETERS_PER_DEGREE: f64 = 111.16;

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
    for member in members {
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

pub(super) fn merge_nearby_clusters(
    mut clusters: Vec<Cluster<'_>>,
    radius_km: f64,
) -> Vec<Cluster<'_>> {
    while let Some((into, from)) = first_pair_within(&clusters, radius_km) {
        let merged = clusters.remove(from);
        clusters[into].absorb(merged);
    }
    clusters
}

fn first_pair_within(clusters: &[Cluster], radius_km: f64) -> Option<(usize, usize)> {
    (0..clusters.len()).find_map(|into| {
        (into + 1..clusters.len())
            .find(|&from| distance_km(clusters[into].center, clusters[from].center) <= radius_km)
            .map(|from| (into, from))
    })
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

    use super::{distance_km, is_within, two_decimals};

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
