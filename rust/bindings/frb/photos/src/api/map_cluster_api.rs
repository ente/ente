use ente_location::cluster as core;
use flutter_rust_bridge::frb;

use super::location_api::LocationError;

pub struct MapPoint {
    pub image_index: u32,
    pub latitude: f64,
    pub longitude: f64,
}

impl From<MapPoint> for core::MapPoint {
    fn from(point: MapPoint) -> Self {
        Self {
            item_index: point.image_index,
            latitude: point.latitude,
            longitude: point.longitude,
        }
    }
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

impl TryFrom<MapViewport> for core::MapViewport {
    type Error = LocationError;

    fn try_from(viewport: MapViewport) -> Result<Self, Self::Error> {
        Ok(Self::new(
            core::GeoBounds::new(viewport.north, viewport.south, viewport.east, viewport.west)?,
            viewport.zoom,
            core::PixelBounds::new(
                viewport.marker_min_x,
                viewport.marker_min_y,
                viewport.marker_max_x,
                viewport.marker_max_y,
            )?,
        )?)
    }
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

impl From<core::MapMarkerGroup> for MapMarkerGroup {
    fn from(group: core::MapMarkerGroup) -> Self {
        Self {
            image_index: group.item_index,
            latitude: group.latitude,
            longitude: group.longitude,
            image_count: group.item_count,
            north: group.north,
            south: group.south,
            east: group.east,
            west: group.west,
        }
    }
}

pub struct MapViewportResult {
    pub visible_image_indexes: Vec<u32>,
    pub marker_groups: Vec<MapMarkerGroup>,
}

#[frb(opaque)]
pub struct MapClusterer {
    inner: core::MapClusterer,
}

pub fn create_map_clusterer(
    points: Vec<MapPoint>,
    minimum_marker_distance: f64,
) -> Result<MapClusterer, LocationError> {
    Ok(MapClusterer {
        inner: core::MapClusterer::new(
            points.into_iter().map(Into::into).collect(),
            minimum_marker_distance,
        )?,
    })
}

impl MapClusterer {
    pub fn cluster(&self, viewport: MapViewport) -> Result<MapViewportResult, LocationError> {
        let result = self.inner.cluster(viewport.try_into()?);

        Ok(MapViewportResult {
            visible_image_indexes: result.visible_item_indices,
            marker_groups: result.marker_groups.into_iter().map(Into::into).collect(),
        })
    }
}
