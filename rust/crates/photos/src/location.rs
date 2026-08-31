use std::path::Path;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};
use ente_location::{CityIndex, CityMatch, Coordinate, CountryIndex, CountryView};

const ASSET_URL: &str = "https://assets.ente.com";
const CITY_FILE: &str = "cities.bin";
const COUNTRY_FILE: &str = "countries.bin";
const DISPUTE_FILE: &str = "disputes.bin";

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Asset(#[from] ente_assets::download::Error),
    #[error(transparent)]
    Location(#[from] ente_location::Error),
    #[error(transparent)]
    CountryCode(#[from] ente_location::InvalidCountryCode),
}

pub struct LocationIndex {
    cities: CityIndex,
    countries: CountryIndex,
}

impl LocationIndex {
    pub async fn open(asset_root: impl AsRef<Path>) -> Result<Self, Error> {
        let asset = asset()?;
        let store = AssetStore::new(asset_root.as_ref());
        let directory = store.asset_dir(&asset);
        store
            .download(&[asset], |_| {}, CancellationToken::new())
            .await?;
        Ok(Self {
            cities: CityIndex::from_path(directory.join(CITY_FILE))?,
            countries: CountryIndex::from_paths(
                directory.join(COUNTRY_FILE),
                directory.join(DISPUTE_FILE),
            )?,
        })
    }

    pub fn cities(&self) -> Vec<ente_location::City> {
        self.cities.search("", usize::MAX)
    }

    pub fn group_cities(&self, coordinates: &[Coordinate], query: &str) -> Vec<CityMatch> {
        self.cities.match_coordinates(coordinates, query)
    }

    pub fn group_countries(
        &self,
        coordinates: &[Coordinate],
        region: Option<&str>,
    ) -> Result<Vec<ente_location::CountryGroup>, Error> {
        let view = match region {
            Some(region) => CountryView::Region(region.parse()?),
            None => CountryView::SourceDefault,
        };
        Ok(self.countries.group(coordinates, view)?.countries)
    }
}

fn asset() -> Result<Asset, ente_assets::download::Error> {
    Asset::files(
        vec!["location".into(), "v1".into()],
        vec![
            file(
                CITY_FILE,
                "929a488aeac782d1cfc9e90b3eeb9536423977aab9f21cb1f86b9324ac53efbc",
            ),
            file(
                COUNTRY_FILE,
                "3ead1ef2bb03b4ffa95813df4316cf149d37c82d16a322352bd6e3b19218c796",
            ),
            file(
                DISPUTE_FILE,
                "c44d0af6ad40a3b195bc10cb87512c16998a20e837af190ff1a46b00170dfd7b",
            ),
        ],
    )
}

fn file(name: &str, sha256: &str) -> AssetFile {
    AssetFile {
        name: name.into(),
        url: format!("{ASSET_URL}/{name}"),
        sha256: sha256.into(),
    }
}
