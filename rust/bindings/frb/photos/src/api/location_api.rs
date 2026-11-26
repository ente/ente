use ente_location as core;
use flutter_rust_bridge::frb;

#[frb]
pub enum LocationError {
    Other { message: String },
}

impl From<core::Error> for LocationError {
    fn from(error: core::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

impl From<ente_photos::location::Error> for LocationError {
    fn from(error: ente_photos::location::Error) -> Self {
        Self::Other {
            message: ente_core::error::chain(&error),
        }
    }
}

#[frb(opaque)]
pub struct LocationIndex(pub(crate) ente_photos::location::LocationIndex);

#[derive(Clone, Debug)]
pub struct LocationCoordinate {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Clone, Debug)]
pub struct LocationCity {
    pub name: String,
    pub country: String,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug)]
pub struct LocationCityGroup {
    pub city: LocationCity,
    pub coordinate_indices: Vec<u32>,
}

#[derive(Debug)]
pub struct LocationCountryGroup {
    pub code: String,
    pub coordinate_indices: Vec<u32>,
}

#[frb(sync)]
pub fn is_within_radius_km(
    point: LocationCoordinate,
    center: LocationCoordinate,
    radius_km: f64,
) -> bool {
    core::Coordinate::from(point).is_within_radius_km(center.into(), radius_km)
}

#[frb(sync)]
pub fn indices_within_radius_km(
    points: Vec<LocationCoordinate>,
    center: LocationCoordinate,
    radius_km: f64,
) -> Vec<u32> {
    core::indices_within_radius_km(&core_coordinates(points), center.into(), radius_km)
        .into_iter()
        .map(|index| index as u32)
        .collect()
}

#[frb(sync)]
pub fn distance_km(from: LocationCoordinate, to: LocationCoordinate) -> f64 {
    core::Coordinate::from(from).distance_km(to.into())
}

pub async fn open_location_index(asset_root: String) -> Result<LocationIndex, LocationError> {
    Ok(LocationIndex(
        ente_photos::location::LocationIndex::open(asset_root).await?,
    ))
}

impl LocationIndex {
    pub fn cities(&self) -> Vec<LocationCity> {
        self.0.cities().into_iter().map(Into::into).collect()
    }

    pub fn group_cities(
        &self,
        coordinates: Vec<LocationCoordinate>,
        query: String,
    ) -> Vec<LocationCityGroup> {
        self.0
            .group_cities(&core_coordinates(coordinates), &query)
            .into_iter()
            .map(|group| LocationCityGroup {
                city: group.city.into(),
                coordinate_indices: group.coordinate_indices,
            })
            .collect()
    }

    pub fn group_countries(
        &self,
        coordinates: Vec<LocationCoordinate>,
        region: Option<String>,
    ) -> Result<Vec<LocationCountryGroup>, LocationError> {
        Ok(self
            .0
            .group_countries(&core_coordinates(coordinates), region.as_deref())?
            .into_iter()
            .map(|group| LocationCountryGroup {
                code: group.country.to_string(),
                coordinate_indices: group.coordinate_indices,
            })
            .collect())
    }
}

impl From<core::City> for LocationCity {
    fn from(city: core::City) -> Self {
        Self {
            name: city.name,
            country: city.country_name,
            latitude: city.latitude,
            longitude: city.longitude,
        }
    }
}

impl From<LocationCoordinate> for core::Coordinate {
    fn from(coordinate: LocationCoordinate) -> Self {
        Self::new(coordinate.latitude, coordinate.longitude)
    }
}

fn core_coordinates(coordinates: Vec<LocationCoordinate>) -> Vec<core::Coordinate> {
    coordinates.into_iter().map(Into::into).collect()
}
