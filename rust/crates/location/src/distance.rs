use std::f64::consts::PI;

use crate::Coordinate;

pub const EARTH_RADIUS_KM: f64 = 6371.0;
const RADIANS_PER_DEGREE: f64 = PI / 180.0;
const LATITUDE_KM_PER_DEGREE_LOWER_BOUND: f64 = 111.0;

fn haversine(half_latitude: f64, half_longitude: f64, latitude_cosine_product: f64) -> f64 {
    let latitude_sine = half_latitude.sin();
    let longitude_sine = half_longitude.sin();
    (latitude_sine * latitude_sine + latitude_cosine_product * longitude_sine * longitude_sine)
        .clamp(0.0, 1.0)
}

fn distance_from_haversine(value: f64) -> f64 {
    EARTH_RADIUS_KM * (2.0 * value.sqrt().atan2((1.0 - value).sqrt()))
}

fn half_latitude_limit(center_latitude: f64, radius_km: f64) -> f64 {
    if center_latitude.abs() <= 90.0 {
        radius_km * (RADIANS_PER_DEGREE / (2.0 * LATITUDE_KM_PER_DEGREE_LOWER_BOUND))
    } else {
        f64::INFINITY
    }
}

fn outside_latitude_limit(latitude: f64, half_latitude: f64, limit: f64) -> bool {
    half_latitude.abs() > limit && latitude.abs() <= 90.0
}

impl Coordinate {
    pub fn distance_km(self, other: Self) -> f64 {
        let latitude_from = self.latitude * RADIANS_PER_DEGREE;
        let latitude_to = other.latitude * RADIANS_PER_DEGREE;
        let longitude_from = self.longitude * RADIANS_PER_DEGREE;
        let longitude_to = other.longitude * RADIANS_PER_DEGREE;
        distance_from_haversine(haversine(
            (latitude_to - latitude_from) / 2.0,
            (longitude_to - longitude_from) / 2.0,
            latitude_from.cos() * latitude_to.cos(),
        ))
    }

    pub fn is_within_radius_km(self, center: Self, radius_km: f64) -> bool {
        let half_latitude =
            (center.latitude * RADIANS_PER_DEGREE - self.latitude * RADIANS_PER_DEGREE) / 2.0;
        radius_km > 0.0
            && !outside_latitude_limit(
                self.latitude,
                half_latitude,
                half_latitude_limit(center.latitude, radius_km),
            )
            && self.distance_km(center) <= radius_km
    }
}

pub fn indices_within_radius_km(
    points: &[Coordinate],
    center: Coordinate,
    radius_km: f64,
) -> Vec<usize> {
    if points.is_empty() || radius_km <= 0.0 || radius_km.is_nan() {
        return Vec::new();
    }
    let center_latitude = center.latitude * RADIANS_PER_DEGREE;
    let center_longitude = center.longitude * RADIANS_PER_DEGREE;
    let center_cosine = center_latitude.cos();
    let latitude_limit = half_latitude_limit(center.latitude, radius_km);

    let threshold = (radius_km.min(PI * EARTH_RADIUS_KM) / (2.0 * EARTH_RADIUS_KM))
        .sin()
        .powi(2);
    // Verify both bounds with the same rounding used by the distance check.
    let slack = threshold * (8.0 * f64::EPSILON);
    let lower = (threshold - slack).max(0.0);
    let upper = (threshold + slack).min(1.0);
    let accept = if distance_from_haversine(lower) <= radius_km {
        lower
    } else {
        0.0
    };
    let reject = if distance_from_haversine(upper) > radius_km {
        upper
    } else {
        f64::INFINITY
    };

    points
        .iter()
        .enumerate()
        .filter(|(_, point)| {
            let latitude = point.latitude * RADIANS_PER_DEGREE;
            let half_latitude = (center_latitude - latitude) / 2.0;
            if outside_latitude_limit(point.latitude, half_latitude, latitude_limit) {
                return false;
            }
            let longitude = point.longitude * RADIANS_PER_DEGREE;
            let value = haversine(
                half_latitude,
                (center_longitude - longitude) / 2.0,
                latitude.cos() * center_cosine,
            );
            value <= accept || (value < reject && distance_from_haversine(value) <= radius_km)
        })
        .map(|(index, _)| index)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::indices_within_radius_km;
    use crate::Coordinate;

    #[test]
    fn a_radius_uses_ground_distance_in_all_directions() {
        let center = Coordinate::new(60.0, 10.0);
        let north = Coordinate::new(60.54, 10.0);
        let east = Coordinate::new(60.0, 10.54);

        assert!(!north.is_within_radius_km(center, 40.0));
        assert!(east.is_within_radius_km(center, 40.0));
        assert!(north.is_within_radius_km(center, north.distance_km(center)));
        assert!(east.is_within_radius_km(center, east.distance_km(center)));
    }

    #[test]
    fn radius_checks_work_across_the_antimeridian_and_at_the_pole() {
        let dateline = Coordinate::new(0.0, 179.9);
        let across_dateline = Coordinate::new(0.0, -179.9);
        let wrapped_longitude = Coordinate::new(0.0, 180.1);
        assert!(across_dateline.is_within_radius_km(dateline, 40.0));
        assert!(wrapped_longitude.is_within_radius_km(dateline, 40.0));
        assert_eq!(
            indices_within_radius_km(&[across_dateline, wrapped_longitude], dateline, 40.0),
            [0, 1]
        );

        let pole = Coordinate::new(90.0, 0.0);
        assert!(Coordinate::new(89.9, 180.0).is_within_radius_km(pole, 40.0));
        assert!(!Coordinate::new(0.0, 0.5).is_within_radius_km(pole, 40.0));
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
        assert!(indices_within_radius_km(&points, paris, f64::NAN).is_empty());
        assert!(indices_within_radius_km(&[], paris, 25.0).is_empty());
    }

    #[test]
    fn batched_radius_check_uses_the_same_cutoff_as_distance() {
        let center = Coordinate::new(60.0, 10.0);
        for point in [
            Coordinate::new(60.01, 10.04),
            Coordinate::new(60.01, 10.07),
            Coordinate::new(-60.0, -170.0),
        ] {
            let radius = point.distance_km(center);
            assert!(indices_within_radius_km(&[point], center, radius.next_down()).is_empty());
            assert_eq!(indices_within_radius_km(&[point], center, radius), [0]);
            assert_eq!(
                indices_within_radius_km(&[point], center, radius.next_up()),
                [0]
            );
        }
    }

    #[test]
    fn distances_follow_the_haversine_great_circle() {
        let paris = Coordinate::new(48.8566, 2.3522);
        let london = Coordinate::new(51.5074, -0.1278);
        assert!((paris.distance_km(london) - 343.5).abs() < 1.0);
        assert_eq!(paris.distance_km(london), london.distance_km(paris));
        assert_eq!(paris.distance_km(paris), 0.0);
    }

    #[test]
    fn antipodal_points_are_half_a_circumference_apart() {
        let south = Coordinate::new(-89.88, 0.0);
        let north = Coordinate::new(89.88, 180.0);
        assert!((south.distance_km(north) - 20_015.087).abs() < 0.001);
    }
}
