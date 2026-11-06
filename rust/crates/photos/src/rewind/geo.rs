use std::collections::HashMap;

use ente_location::Coordinate;

const EARTH_RADIUS_KM: f64 = 6371.0;
const KILOMETERS_PER_DEGREE: f64 = 111.195;
const GRID_CELL_MARGIN: f64 = 1.01;
const GRID_MAX_LATITUDE: f64 = 80.0;

pub(super) fn distance_km(from: Coordinate, to: Coordinate) -> f64 {
    let latitude_from = from.latitude.to_radians();
    let latitude_to = to.latitude.to_radians();
    let half_latitude = (latitude_to - latitude_from) / 2.0;
    let half_longitude = (to.longitude - from.longitude).to_radians() / 2.0;
    let a = half_latitude.sin().powi(2)
        + latitude_from.cos() * latitude_to.cos() * half_longitude.sin().powi(2);
    EARTH_RADIUS_KM * 2.0 * a.sqrt().atan2((1.0 - a).sqrt())
}

pub(super) fn cluster(points: &[Coordinate], radius_km: f64) -> Vec<Vec<usize>> {
    let mut clusters: Vec<Cluster> = Vec::new();
    let mut grid = Grid::new(radius_km);
    for (position, &point) in points.iter().enumerate() {
        let nearest = grid
            .near(point)
            .map(|id| (id, distance_km(clusters[id].center, point)))
            .filter(|&(_, distance)| distance <= radius_km)
            .min_by(|first, second| first.1.total_cmp(&second.1).then(first.0.cmp(&second.0)));
        match nearest {
            Some((id, _)) => {
                let from = clusters[id].center;
                clusters[id].add(position, point);
                grid.relocate(id, from, clusters[id].center);
            }
            None => {
                grid.insert(clusters.len(), point);
                clusters.push(Cluster::new(position, point));
            }
        }
    }
    clusters
        .into_iter()
        .map(|cluster| cluster.members)
        .collect()
}

struct Cluster {
    members: Vec<usize>,
    latitude_sum: f64,
    longitude_sum: f64,
    center: Coordinate,
}

impl Cluster {
    fn new(position: usize, point: Coordinate) -> Self {
        Self {
            members: vec![position],
            latitude_sum: point.latitude,
            longitude_sum: point.longitude,
            center: point,
        }
    }

    fn add(&mut self, position: usize, point: Coordinate) {
        self.members.push(position);
        self.latitude_sum += point.latitude;
        self.longitude_sum += point.longitude;
        let count = self.members.len() as f64;
        self.center = Coordinate::new(self.latitude_sum / count, self.longitude_sum / count);
    }
}

struct Grid {
    row_height: f64,
    column_width: f64,
    cells: HashMap<(i64, i64), Vec<usize>>,
    off_grid: Vec<usize>,
}

impl Grid {
    fn new(radius_km: f64) -> Self {
        let row_height = radius_km / KILOMETERS_PER_DEGREE * GRID_CELL_MARGIN;
        Self {
            row_height,
            column_width: row_height / GRID_MAX_LATITUDE.to_radians().cos(),
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

    fn relocate(&mut self, id: usize, from: Coordinate, to: Coordinate) {
        if self.cell(from) == self.cell(to) {
            return;
        }
        let ids = match self.cell(from) {
            Some(cell) => self.cells.get_mut(&cell),
            None => Some(&mut self.off_grid),
        };
        if let Some(ids) = ids {
            ids.retain(|&other| other != id);
        }
        self.insert(id, to);
    }

    fn near(&self, at: Coordinate) -> impl Iterator<Item = usize> + '_ {
        let cells: Vec<&Vec<usize>> = match self.cell(at) {
            Some((row, column)) => (row - 1..=row + 1)
                .flat_map(|row| (column - 1..=column + 1).map(move |column| (row, column)))
                .filter_map(|cell| self.cells.get(&cell))
                .collect(),
            None => self.cells.values().collect(),
        };
        cells.into_iter().flatten().chain(&self.off_grid).copied()
    }
}

#[cfg(test)]
mod tests {
    use ente_location::Coordinate;

    use super::{cluster, distance_km};

    #[test]
    fn distances_follow_the_great_circle_across_the_antimeridian() {
        let amsterdam = Coordinate::new(52.3676, 4.9041);
        let paris = Coordinate::new(48.8566, 2.3522);
        assert!((distance_km(amsterdam, paris) - 430.0).abs() < 5.0);
        let east = Coordinate::new(0.0, 179.999);
        let west = Coordinate::new(0.0, -179.999);
        assert!(distance_km(east, west) < 0.3);
    }

    #[test]
    fn points_join_the_nearest_cluster_within_the_radius() {
        let home = Coordinate::new(52.0, 4.0);
        let cafe = Coordinate::new(52.0, 4.006);
        let between = Coordinate::new(52.0, 4.0034);
        let far = Coordinate::new(53.0, 4.0);
        let polar = Coordinate::new(89.5, 10.0);

        let clusters = cluster(&[home, cafe, between, far, polar, polar], 0.3);

        assert_eq!(clusters, [vec![0], vec![1, 2], vec![3], vec![4, 5]]);
    }
}
