use ente_photos::map_cluster as core;
use flutter_rust_bridge::frb;

pub struct MapPoint {
    pub image_index: u32,
    pub latitude: f64,
    pub longitude: f64,
}

impl From<MapPoint> for core::MapPoint {
    fn from(point: MapPoint) -> Self {
        Self {
            image_index: point.image_index,
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

impl From<MapViewport> for core::MapViewport {
    fn from(viewport: MapViewport) -> Self {
        Self {
            north: viewport.north,
            south: viewport.south,
            east: viewport.east,
            west: viewport.west,
            zoom: viewport.zoom,
            marker_min_x: viewport.marker_min_x,
            marker_min_y: viewport.marker_min_y,
            marker_max_x: viewport.marker_max_x,
            marker_max_y: viewport.marker_max_y,
        }
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
            image_index: group.image_index,
            latitude: group.latitude,
            longitude: group.longitude,
            image_count: group.image_count,
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

pub fn create_map_clusterer(points: Vec<MapPoint>) -> MapClusterer {
    MapClusterer {
        inner: core::MapClusterer::new(points.into_iter().map(Into::into).collect()),
    }
}

impl MapClusterer {
    pub fn cluster(&self, viewport: MapViewport) -> MapViewportResult {
        let result = self.inner.cluster(viewport.into());

        MapViewportResult {
            visible_image_indexes: result.visible_image_indexes,
            marker_groups: result.marker_groups.into_iter().map(Into::into).collect(),
        }
    }
}
