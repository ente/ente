use std::collections::HashMap;
use std::f64::consts::PI;

use crate::{Coordinate, Error, Result};

const WEB_MERCATOR_TILE_SIZE: f64 = 256.0;
const MERCATOR_LATITUDE_LIMIT: f64 = 85.051_128_78;

#[derive(Clone, Copy, Debug)]
pub struct MapPoint {
    pub item_index: u32,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct GeoBounds {
    north: f64,
    south: f64,
    east: f64,
    west: f64,
}

impl GeoBounds {
    pub fn new(north: f64, south: f64, east: f64, west: f64) -> Result<Self> {
        if !north.is_finite()
            || !south.is_finite()
            || !east.is_finite()
            || !west.is_finite()
            || !(-90.0..=90.0).contains(&north)
            || !(-90.0..=90.0).contains(&south)
            || north < south
            || !(-180.0..=180.0).contains(&east)
            || !(-180.0..=180.0).contains(&west)
        {
            return Err(Error::InvalidViewport);
        }
        Ok(Self {
            north,
            south,
            east,
            west,
        })
    }
}

#[derive(Clone, Copy, Debug)]
pub struct PixelBounds {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
}

impl PixelBounds {
    pub fn new(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> Result<Self> {
        if [min_x, min_y, max_x, max_y]
            .iter()
            .any(|value| !value.is_finite())
            || min_x > max_x
            || min_y > max_y
        {
            return Err(Error::InvalidViewport);
        }
        Ok(Self {
            min_x,
            min_y,
            max_x,
            max_y,
        })
    }
}

#[derive(Clone, Copy, Debug)]
pub struct MapViewport {
    bounds: GeoBounds,
    zoom: f64,
    markers: PixelBounds,
}

impl MapViewport {
    pub fn new(bounds: GeoBounds, zoom: f64, markers: PixelBounds) -> Result<Self> {
        let scale = 2.0_f64.powf(zoom);
        if !zoom.is_finite() || !scale.is_finite() || scale == 0.0 {
            return Err(Error::InvalidViewport);
        }
        Ok(Self {
            bounds,
            zoom,
            markers,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MapMarkerGroup {
    pub item_index: u32,
    pub latitude: f64,
    pub longitude: f64,
    pub item_count: u32,
    pub north: f64,
    pub south: f64,
    pub east: f64,
    pub west: f64,
}

#[derive(Debug, PartialEq)]
pub struct MapViewportResult {
    pub visible_item_indices: Vec<u32>,
    pub marker_groups: Vec<MapMarkerGroup>,
}

pub struct MapClusterer {
    points: Vec<MapPoint>,
    minimum_marker_distance: f64,
}

impl MapClusterer {
    pub fn new(points: Vec<MapPoint>, minimum_marker_distance: f64) -> Result<Self> {
        if !minimum_marker_distance.is_finite() || minimum_marker_distance <= 0.0 {
            return Err(Error::InvalidMarkerDistance);
        }
        if let Some((index, _)) = points
            .iter()
            .enumerate()
            .find(|(_, point)| !Coordinate::new(point.latitude, point.longitude).is_valid())
        {
            return Err(Error::InvalidMapPoint(index));
        }
        Ok(Self {
            points,
            minimum_marker_distance,
        })
    }

    pub fn cluster(&self, viewport: MapViewport) -> MapViewportResult {
        let mut visible_item_indices = Vec::new();
        let mut visible_points = Vec::new();
        let mut buffered_points = Vec::new();
        let world_size = WEB_MERCATOR_TILE_SIZE * 2.0_f64.powf(viewport.zoom);
        let viewport_center_x = (viewport.markers.min_x + viewport.markers.max_x) / 2.0;

        for point in &self.points {
            let is_visible =
                longitude_is_visible(point.longitude, viewport.bounds.west, viewport.bounds.east)
                    && point.latitude >= viewport.bounds.south
                    && point.latitude <= viewport.bounds.north;
            if is_visible {
                visible_item_indices.push(point.item_index);
            }

            let latitude = point
                .latitude
                .clamp(-MERCATOR_LATITUDE_LIMIT, MERCATOR_LATITUDE_LIMIT);
            let sin_latitude = (latitude * PI / 180.0).sin();
            let canonical_x = (point.longitude + 180.0) / 360.0 * world_size;
            let x =
                canonical_x + ((viewport_center_x - canonical_x) / world_size).round() * world_size;
            let y = (0.5 - ((1.0 + sin_latitude) / (1.0 - sin_latitude)).ln() / (4.0 * PI))
                * world_size;
            if x < viewport.markers.min_x
                || x > viewport.markers.max_x
                || y < viewport.markers.min_y
                || y > viewport.markers.max_y
            {
                continue;
            }

            let projected = ProjectedPoint {
                point: *point,
                x,
                y,
            };
            if is_visible {
                visible_points.push(projected);
            } else {
                buffered_points.push(projected);
            }
        }

        let mut groups_by_cell = HashMap::<(i64, i64), Vec<usize>>::new();
        let mut groups = Vec::new();
        for point in visible_points.into_iter().chain(buffered_points) {
            self.add_to_group(point, &mut groups_by_cell, &mut groups);
        }

        MapViewportResult {
            visible_item_indices,
            marker_groups: groups.into_iter().map(ProjectedGroup::finish).collect(),
        }
    }

    fn add_to_group(
        &self,
        point: ProjectedPoint,
        groups_by_cell: &mut HashMap<(i64, i64), Vec<usize>>,
        groups: &mut Vec<ProjectedGroup>,
    ) {
        let distance = self.minimum_marker_distance;
        let cell = (
            (point.x / distance).floor() as i64,
            (point.y / distance).floor() as i64,
        );
        let mut closest = None;
        let mut closest_distance_squared = f64::INFINITY;

        for x_offset in -1..=1 {
            for y_offset in -1..=1 {
                let Some(nearby) = groups_by_cell.get(&(cell.0 + x_offset, cell.1 + y_offset))
                else {
                    continue;
                };
                for &group_index in nearby {
                    let group = &groups[group_index];
                    let x_distance = point.x - group.x;
                    let y_distance = point.y - group.y;
                    let distance_squared = x_distance * x_distance + y_distance * y_distance;
                    if distance_squared <= distance * distance
                        && distance_squared < closest_distance_squared
                    {
                        closest = Some(group_index);
                        closest_distance_squared = distance_squared;
                    }
                }
            }
        }

        if let Some(index) = closest {
            groups[index].add(point.point);
        } else {
            let index = groups.len();
            groups.push(ProjectedGroup::new(point));
            groups_by_cell.entry(cell).or_default().push(index);
        }
    }
}

#[derive(Clone, Copy)]
struct ProjectedPoint {
    point: MapPoint,
    x: f64,
    y: f64,
}

struct ProjectedGroup {
    item_index: u32,
    latitude: f64,
    longitude: f64,
    x: f64,
    y: f64,
    item_count: u32,
    north: f64,
    south: f64,
    east: f64,
    west: f64,
}

impl ProjectedGroup {
    fn new(point: ProjectedPoint) -> Self {
        Self {
            item_index: point.point.item_index,
            latitude: point.point.latitude,
            longitude: point.point.longitude,
            x: point.x,
            y: point.y,
            item_count: 1,
            north: point.point.latitude,
            south: point.point.latitude,
            east: point.point.longitude,
            west: point.point.longitude,
        }
    }

    fn add(&mut self, point: MapPoint) {
        self.item_count += 1;
        self.north = self.north.max(point.latitude);
        self.south = self.south.min(point.latitude);
        let longitude = unwrap_longitude(point.longitude, self.longitude);
        self.east = self.east.max(longitude);
        self.west = self.west.min(longitude);
    }

    fn finish(self) -> MapMarkerGroup {
        MapMarkerGroup {
            item_index: self.item_index,
            latitude: self.latitude,
            longitude: self.longitude,
            item_count: self.item_count,
            north: self.north,
            south: self.south,
            east: normalize_longitude(self.east),
            west: normalize_longitude(self.west),
        }
    }
}

fn unwrap_longitude(longitude: f64, origin: f64) -> f64 {
    origin + (longitude - origin + 180.0).rem_euclid(360.0) - 180.0
}

fn normalize_longitude(longitude: f64) -> f64 {
    (longitude + 180.0).rem_euclid(360.0) - 180.0
}

fn longitude_is_visible(longitude: f64, west: f64, east: f64) -> bool {
    if west <= east {
        (west..=east).contains(&longitude)
    } else {
        longitude >= west || longitude <= east
    }
}

#[cfg(test)]
mod tests {
    use super::{GeoBounds, MapClusterer, MapPoint, MapViewport, PixelBounds};

    #[test]
    fn clusters_visible_points_across_the_antimeridian() {
        let clusterer = MapClusterer::new(
            vec![
                point(1, 0.0, 179.9),
                point(2, 0.0, -179.9),
                point(3, 0.0, 0.0),
            ],
            10.0,
        )
        .unwrap();
        let viewport = viewport(
            [10.0, -10.0, -170.0, 170.0],
            2.0,
            [0.0, 0.0, 2048.0, 1024.0],
        );

        let result = clusterer.cluster(viewport);

        assert_eq!(result.visible_item_indices, [1, 2]);
        assert_eq!(result.marker_groups[0].item_index, 1);
        assert_eq!(result.marker_groups[0].item_count, 2);
        assert!(result.marker_groups[0].west > result.marker_groups[0].east);
    }

    fn point(item_index: u32, latitude: f64, longitude: f64) -> MapPoint {
        MapPoint {
            item_index,
            latitude,
            longitude,
        }
    }

    fn viewport(bounds: [f64; 4], zoom: f64, markers: [f64; 4]) -> MapViewport {
        MapViewport::new(
            GeoBounds::new(bounds[0], bounds[1], bounds[2], bounds[3]).unwrap(),
            zoom,
            PixelBounds::new(markers[0], markers[1], markers[2], markers[3]).unwrap(),
        )
        .unwrap()
    }
}
