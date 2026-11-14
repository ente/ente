use std::f64::consts::PI;

use crate::Coordinate;

pub const EARTH_RADIUS_KM: f64 = 6371.0;
pub const KILOMETERS_PER_DEGREE: f64 = 111.16;

impl Coordinate {
    pub fn distance_km(self, other: Self) -> f64 {
        let latitude_from = self.latitude * (PI / 180.0);
        let latitude_to = other.latitude * (PI / 180.0);
        let longitude_from = self.longitude * (PI / 180.0);
        let longitude_to = other.longitude * (PI / 180.0);
        let half_latitude = (latitude_to - latitude_from) / 2.0;
        let half_longitude = (longitude_to - longitude_from) / 2.0;
        let a = half_latitude.sin() * half_latitude.sin()
            + latitude_from.cos() * latitude_to.cos() * half_longitude.sin() * half_longitude.sin();
        EARTH_RADIUS_KM * (2.0 * a.sqrt().atan2((1.0 - a).sqrt()))
    }

    pub fn is_within_radius_km(self, center: Self, radius_km: f64) -> bool {
        let latitude_scale = 1.0 / (center.latitude * (PI / 180.0)).cos();
        let latitude_radius = (radius_km * latitude_scale) / KILOMETERS_PER_DEGREE;
        let longitude_radius = radius_km / KILOMETERS_PER_DEGREE;
        let latitude_delta = center.latitude - self.latitude;
        let longitude_delta = center.longitude - self.longitude;
        (latitude_delta * latitude_delta) / (latitude_radius * latitude_radius)
            + (longitude_delta * longitude_delta) / (longitude_radius * longitude_radius)
            <= 1.0
    }
}

pub fn indices_within_radius_km(
    points: &[Coordinate],
    center: Coordinate,
    radius_km: f64,
) -> Vec<usize> {
    points
        .iter()
        .enumerate()
        .filter(|(_, point)| point.is_within_radius_km(center, radius_km))
        .map(|(index, _)| index)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::indices_within_radius_km;
    use crate::Coordinate;

    #[test]
    fn radius_checks_bound_each_axis_in_degrees_at_the_equator() {
        let center = Coordinate::new(0.0, 0.0);
        let within = |latitude: f64, longitude: f64| {
            Coordinate::new(latitude, longitude).is_within_radius_km(center, 111.16)
        };
        assert!(within(0.0, 0.0));
        assert!(within(0.999, 0.0));
        assert!(within(-1.0, 0.0));
        assert!(!within(1.001, 0.0));
        assert!(within(0.0, -0.999));
        assert!(within(0.0, 1.0));
        assert!(!within(0.0, -1.001));
        assert!(!within(0.8, 0.8));
    }

    #[test]
    fn the_centre_latitude_stretches_the_latitude_axis_like_the_apps() {
        let center = Coordinate::new(60.0, 0.0);
        assert!(Coordinate::new(61.5, 0.0).is_within_radius_km(center, 111.16));
        assert!(!Coordinate::new(62.5, 0.0).is_within_radius_km(center, 111.16));
        assert!(!Coordinate::new(60.0, 1.5).is_within_radius_km(center, 111.16));
    }

    #[test]
    fn a_pole_centre_bounds_longitude_only_and_a_zero_radius_matches_nothing() {
        let pole = Coordinate::new(90.0, 0.0);
        assert!(Coordinate::new(0.0, 0.5).is_within_radius_km(pole, 111.16));
        assert!(!Coordinate::new(90.0, 1.5).is_within_radius_km(pole, 111.16));
        let center = Coordinate::new(48.8566, 2.3522);
        assert!(!center.is_within_radius_km(center, 0.0));
        assert!(!Coordinate::new(48.86, 2.3522).is_within_radius_km(center, 0.0));
    }

    #[test]
    fn batched_checks_keep_the_matching_indices_in_order() {
        let paris = Coordinate::new(48.8566, 2.3522);
        let points = [
            paris,
            Coordinate::new(51.5074, -0.1278),
            Coordinate::new(48.95, 2.3522),
            Coordinate::new(48.8566, 2.70),
            Coordinate::new(48.80, 2.40),
        ];
        assert_eq!(indices_within_radius_km(&points, paris, 25.0), [0, 2, 4]);
        assert_eq!(
            indices_within_radius_km(&points, paris, 400.0),
            [0, 1, 2, 3, 4]
        );
        assert!(indices_within_radius_km(&points, paris, 0.0).is_empty());
        assert!(indices_within_radius_km(&[], paris, 25.0).is_empty());
    }

    #[test]
    fn distances_follow_the_haversine_great_circle() {
        let paris = Coordinate::new(48.8566, 2.3522);
        let london = Coordinate::new(51.5074, -0.1278);
        assert!((paris.distance_km(london) - 343.5).abs() < 1.0);
        assert_eq!(paris.distance_km(london), london.distance_km(paris));
        assert_eq!(paris.distance_km(paris), 0.0);
    }
}
