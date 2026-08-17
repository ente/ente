use std::collections::HashMap;
use std::f64::consts::PI;

const MINIMUM_MARKER_DISTANCE_PIXELS: f64 = 100.0;
const WEB_MERCATOR_TILE_SIZE: f64 = 256.0;
const MERCATOR_LATITUDE_LIMIT: f64 = 85.051_128_78;

#[derive(Clone, Copy)]
pub struct MapPoint {
    pub image_index: u32,
    pub latitude: f64,
    pub longitude: f64,
}

pub struct MapViewport {
    pub north: f64,
    pub south: f64,
    pub east: f64,
    pub west: f64,
    pub zoom: f64,
    pub marker_min_x: f64,
    pub marker_min_y: f64,
    pub marker_max_x: f64,
    pub marker_max_y: f64,
}

pub struct MapMarkerGroup {
    pub image_index: u32,
    pub latitude: f64,
    pub longitude: f64,
    pub image_count: u32,
    pub north: f64,
    pub south: f64,
    pub east: f64,
    pub west: f64,
}

pub struct MapViewportResult {
    pub visible_image_indexes: Vec<u32>,
    pub marker_groups: Vec<MapMarkerGroup>,
}

pub struct MapClusterer {
    points: Vec<MapPoint>,
}

impl MapClusterer {
    pub fn new(points: Vec<MapPoint>) -> Self {
        Self { points }
    }

    pub fn cluster(&self, viewport: MapViewport) -> MapViewportResult {
        let mut visible_image_indexes = Vec::new();
        let mut visible_points = Vec::new();
        let mut buffered_points = Vec::new();
        let scale = WEB_MERCATOR_TILE_SIZE * 2.0_f64.powf(viewport.zoom);

        for point in &self.points {
            let is_visible = point.longitude >= viewport.west
                && point.longitude <= viewport.east
                && point.latitude >= viewport.south
                && point.latitude <= viewport.north;
            if is_visible {
                visible_image_indexes.push(point.image_index);
            }

            let latitude = point
                .latitude
                .clamp(-MERCATOR_LATITUDE_LIMIT, MERCATOR_LATITUDE_LIMIT);
            let sin_latitude = (latitude * PI / 180.0).sin();
            let x = (point.longitude + 180.0) / 360.0 * scale;
            let y = (0.5 - ((1.0 + sin_latitude) / (1.0 - sin_latitude)).ln() / (4.0 * PI)) * scale;
            if x < viewport.marker_min_x
                || x > viewport.marker_max_x
                || y < viewport.marker_min_y
                || y > viewport.marker_max_y
            {
                continue;
            }

            let projected_point = ProjectedMapPoint {
                point: *point,
                x,
                y,
            };
            if is_visible {
                visible_points.push(projected_point);
            } else {
                buffered_points.push(projected_point);
            }
        }

        let mut groups_by_cell = HashMap::<(i64, i64), Vec<usize>>::new();
        let mut groups = Vec::<ProjectedMarkerGroup>::new();
        for point in visible_points.iter().chain(&buffered_points) {
            add_to_marker_group(*point, &mut groups_by_cell, &mut groups);
        }

        MapViewportResult {
            visible_image_indexes,
            marker_groups: groups
                .into_iter()
                .map(ProjectedMarkerGroup::into_marker_group)
                .collect(),
        }
    }
}

#[derive(Clone, Copy)]
struct ProjectedMapPoint {
    point: MapPoint,
    x: f64,
    y: f64,
}

struct ProjectedMarkerGroup {
    image_index: u32,
    latitude: f64,
    longitude: f64,
    x: f64,
    y: f64,
    image_count: u32,
    north: f64,
    south: f64,
    east: f64,
    west: f64,
}

impl ProjectedMarkerGroup {
    fn new(point: ProjectedMapPoint) -> Self {
        Self {
            image_index: point.point.image_index,
            latitude: point.point.latitude,
            longitude: point.point.longitude,
            x: point.x,
            y: point.y,
            image_count: 1,
            north: point.point.latitude,
            south: point.point.latitude,
            east: point.point.longitude,
            west: point.point.longitude,
        }
    }

    fn add(&mut self, point: MapPoint) {
        self.image_count += 1;
        self.north = self.north.max(point.latitude);
        self.south = self.south.min(point.latitude);
        self.east = self.east.max(point.longitude);
        self.west = self.west.min(point.longitude);
    }

    fn into_marker_group(self) -> MapMarkerGroup {
        MapMarkerGroup {
            image_index: self.image_index,
            latitude: self.latitude,
            longitude: self.longitude,
            image_count: self.image_count,
            north: self.north,
            south: self.south,
            east: self.east,
            west: self.west,
        }
    }
}

fn add_to_marker_group(
    point: ProjectedMapPoint,
    groups_by_cell: &mut HashMap<(i64, i64), Vec<usize>>,
    groups: &mut Vec<ProjectedMarkerGroup>,
) {
    let cell = (
        (point.x / MINIMUM_MARKER_DISTANCE_PIXELS).floor() as i64,
        (point.y / MINIMUM_MARKER_DISTANCE_PIXELS).floor() as i64,
    );
    let mut closest_group_index = None;
    let mut closest_distance_squared = f64::INFINITY;

    for x_offset in -1..=1 {
        for y_offset in -1..=1 {
            let Some(nearby_group_indexes) =
                groups_by_cell.get(&(cell.0 + x_offset, cell.1 + y_offset))
            else {
                continue;
            };

            for group_index in nearby_group_indexes {
                let group = &groups[*group_index];
                let x_distance = point.x - group.x;
                let y_distance = point.y - group.y;
                let distance_squared = x_distance * x_distance + y_distance * y_distance;
                if distance_squared
                    <= MINIMUM_MARKER_DISTANCE_PIXELS * MINIMUM_MARKER_DISTANCE_PIXELS
                    && distance_squared < closest_distance_squared
                {
                    closest_group_index = Some(*group_index);
                    closest_distance_squared = distance_squared;
                }
            }
        }
    }

    if let Some(group_index) = closest_group_index {
        groups[group_index].add(point.point);
        return;
    }

    let group_index = groups.len();
    groups.push(ProjectedMarkerGroup::new(point));
    groups_by_cell.entry(cell).or_default().push(group_index);
}
