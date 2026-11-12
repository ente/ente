use ente_location::{CityIndex, Coordinate, UrbanCenterIndex};
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Location(#[from] ente_location::Error),
    #[error(transparent)]
    Serde(#[from] swb::Error),
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, None)
    }
}

#[derive(Deserialize, Tsify)]
pub struct LocationCoordinate {
    latitude: f64,
    longitude: f64,
}

#[derive(Deserialize, Tsify)]
pub struct LocationQuery {
    coordinates: Vec<LocationCoordinate>,
}

#[derive(Serialize, Tsify)]
pub struct LocationCity {
    name: String,
    country: String,
    latitude: f64,
    longitude: f64,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct LocationCityGroup {
    city: LocationCity,
    coordinate_indices: Vec<u32>,
}

#[derive(Serialize, Tsify)]
pub struct LocationCityGroups {
    groups: Vec<LocationCityGroup>,
}

#[wasm_bindgen]
pub struct LocationIndex {
    cities: CityIndex,
    urban_centers: UrbanCenterIndex,
}

#[wasm_bindgen]
impl LocationIndex {
    #[wasm_bindgen(constructor)]
    pub fn new(cities: &[u8], urban_centers: &[u8]) -> Result<LocationIndex, Error> {
        Ok(Self {
            cities: CityIndex::from_bytes(cities)?,
            urban_centers: UrbanCenterIndex::from_bytes(urban_centers)?,
        })
    }

    #[wasm_bindgen(js_name = groupCities)]
    pub fn group_cities(
        &self,
        input: <LocationQuery as Tsify>::JsType,
    ) -> Result<<LocationCityGroups as Tsify>::JsType, Error> {
        let input = LocationQuery::from_js(input)?;
        let coordinates: Vec<_> = input
            .coordinates
            .into_iter()
            .map(|coordinate| Coordinate::new(coordinate.latitude, coordinate.longitude))
            .collect();
        let groups = self
            .urban_centers
            .match_coordinates_with_cities(&self.cities, &coordinates, "")
            .into_iter()
            .map(|group| LocationCityGroup {
                city: LocationCity {
                    name: group.city.name,
                    country: group.city.country_name,
                    latitude: group.city.latitude,
                    longitude: group.city.longitude,
                },
                coordinate_indices: group.coordinate_indices,
            })
            .collect();
        LocationCityGroups { groups }.into_js().map_err(Into::into)
    }
}
