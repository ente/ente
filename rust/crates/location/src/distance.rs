use std::f64::consts::PI;

use crate::Coordinate;

pub const EARTH_RADIUS_KM: f64 = 6371.0;

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
        let a = a.clamp(0.0, 1.0);
        EARTH_RADIUS_KM * (2.0 * a.sqrt().atan2((1.0 - a).sqrt()))
    }

    pub fn is_within_radius_km(self, center: Self, radius_km: f64) -> bool {
        radius_km > 0.0 && self.distance_km(center) <= radius_km
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
    fn a_radius_uses_ground_distance_in_all_directions() {
        let center = Coordinate::new(60.0, 10.0);
        let north = Coordinate::new(60.54, 10.0);
        let east = Coordinate::new(60.0, 10.54);

        assert!(!north.is_within_radius_km(center, 40.0));
        assert!(east.is_within_radius_km(center, 40.0));
        assert!(east.is_within_radius_km(center, east.distance_km(center)));
    }

    #[test]
    fn radius_checks_work_across_the_antimeridian_and_at_the_pole() {
        let dateline = Coordinate::new(0.0, 179.9);
        assert!(Coordinate::new(0.0, -179.9).is_within_radius_km(dateline, 40.0));

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

    #[test]
    fn antipodal_points_are_half_a_circumference_apart() {
        let south = Coordinate::new(-89.88, 0.0);
        let north = Coordinate::new(89.88, 180.0);
        assert!((south.distance_km(north) - 20_015.087).abs() < 0.001);
    }
}
