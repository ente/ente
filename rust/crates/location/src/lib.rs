use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::path::Path;
use std::str::FromStr;

mod binary;
mod city;
pub mod cluster;
mod country;
mod dispute;
mod error;

pub use city::{City, CityIndex, CityMatch};
pub use dispute::{CountryView, DisputeMatch, TerritoryId};
pub use error::{Error, Result};

use country::CountryGeometry;
use dispute::DisputeIndex;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Coordinate {
    pub latitude: f64,
    pub longitude: f64,
}

impl Coordinate {
    pub const fn new(latitude: f64, longitude: f64) -> Self {
        Self {
            latitude,
            longitude,
        }
    }

    pub fn is_valid(self) -> bool {
        self.latitude.is_finite()
            && (-90.0..=90.0).contains(&self.latitude)
            && self.longitude.is_finite()
            && (-180.0..=180.0).contains(&self.longitude)
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct CountryCode([u8; 2]);

impl CountryCode {
    pub fn from_bytes(bytes: [u8; 2]) -> std::result::Result<Self, InvalidCountryCode> {
        if bytes.iter().all(u8::is_ascii_uppercase) {
            Ok(Self(bytes))
        } else {
            Err(InvalidCountryCode)
        }
    }

    pub const fn as_bytes(self) -> [u8; 2] {
        self.0
    }

    pub fn as_str(&self) -> &str {
        std::str::from_utf8(&self.0).expect("country code is ASCII")
    }

    pub(crate) const fn from_validated(bytes: [u8; 2]) -> Self {
        Self(bytes)
    }
}

impl fmt::Display for CountryCode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl FromStr for CountryCode {
    type Err = InvalidCountryCode;

    fn from_str(value: &str) -> std::result::Result<Self, Self::Err> {
        let bytes = value
            .as_bytes()
            .try_into()
            .map_err(|_| InvalidCountryCode)?;
        Self::from_bytes(bytes)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
#[error("country codes must contain two uppercase ASCII letters")]
pub struct InvalidCountryCode;

pub struct CountryIndex {
    countries: CountryGeometry,
    disputes: DisputeIndex,
}

impl CountryIndex {
    pub fn from_paths(countries: impl AsRef<Path>, disputes: impl AsRef<Path>) -> Result<Self> {
        Self::from_bytes(fs::read(countries)?, fs::read(disputes)?)
    }

    pub fn from_bytes(
        countries: impl Into<Box<[u8]>>,
        disputes: impl Into<Box<[u8]>>,
    ) -> Result<Self> {
        let countries = CountryGeometry::from_bytes(countries)?;
        let disputes = DisputeIndex::from_bytes(disputes)?;
        if countries.columns() != 360 || countries.rows() != 180 {
            return Err(Error::invalid(
                "country index",
                "country grid must be 360 by 180",
            ));
        }
        Ok(Self {
            countries,
            disputes,
        })
    }

    pub fn lookup(&self, coordinate: Coordinate) -> Result<CountryClassification<'_>> {
        let cell = self
            .countries
            .prepare_cell(coordinate.latitude, coordinate.longitude)?;
        Ok(CountryClassification {
            countries: self.countries.lookup_prepared(cell)?,
            disputes: self.disputes.lookup_prepared(cell)?,
        })
    }

    pub fn group(&self, coordinates: &[Coordinate], view: CountryView) -> Result<CountryGrouping> {
        let mut countries = BTreeMap::<CountryCode, Vec<u32>>::new();
        let mut disputes = BTreeMap::<TerritoryId, DisputeGroup>::new();
        let mut unclassified_coordinate_indices = Vec::new();

        for (coordinate_index, &coordinate) in coordinates.iter().enumerate() {
            let coordinate_index = coordinate_index as u32;
            let classification = match self.lookup(coordinate) {
                Ok(classification) => classification,
                Err(Error::InvalidCoordinate) => {
                    unclassified_coordinate_indices.push(coordinate_index);
                    continue;
                }
                Err(error) => return Err(error),
            };
            if classification.disputes.is_empty() {
                if classification.countries.is_empty() {
                    unclassified_coordinate_indices.push(coordinate_index);
                }
                for country in classification.countries {
                    countries.entry(country).or_default().push(coordinate_index);
                }
                continue;
            }

            let mut resolved = Vec::new();
            for dispute in classification.disputes {
                let country = dispute.resolve(view);
                disputes
                    .entry(dispute.territory_id())
                    .or_insert_with(|| DisputeGroup {
                        territory: dispute.territory_id(),
                        name: dispute.name().to_owned(),
                        possible_countries: dispute.possible_countries().collect(),
                        resolved_country: country,
                        coordinate_indices: Vec::new(),
                    })
                    .coordinate_indices
                    .push(coordinate_index);
                if let Some(country) = country
                    && !resolved.contains(&country)
                {
                    resolved.push(country);
                }
            }
            for country in resolved {
                countries.entry(country).or_default().push(coordinate_index);
            }
        }

        Ok(CountryGrouping {
            countries: countries
                .into_iter()
                .map(|(country, coordinate_indices)| CountryGroup {
                    country,
                    coordinate_indices,
                })
                .collect(),
            disputes: disputes.into_values().collect(),
            unclassified_coordinate_indices,
        })
    }
}

#[derive(Debug)]
pub struct CountryClassification<'a> {
    pub countries: Vec<CountryCode>,
    pub disputes: Vec<DisputeMatch<'a>>,
}

#[derive(Debug, Eq, PartialEq)]
pub struct CountryGrouping {
    pub countries: Vec<CountryGroup>,
    pub disputes: Vec<DisputeGroup>,
    pub unclassified_coordinate_indices: Vec<u32>,
}

#[derive(Debug, Eq, PartialEq)]
pub struct CountryGroup {
    pub country: CountryCode,
    pub coordinate_indices: Vec<u32>,
}

#[derive(Debug, Eq, PartialEq)]
pub struct DisputeGroup {
    pub territory: TerritoryId,
    pub name: String,
    pub possible_countries: Vec<CountryCode>,
    pub resolved_country: Option<CountryCode>,
    pub coordinate_indices: Vec<u32>,
}
