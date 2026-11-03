use std::path::Path;

use ente_assets::download::CancellationToken;
use ente_assets::{Asset, AssetFile, AssetStore};
use ente_location::{
    CityIndex, CityMatch, Coordinate, CountryCode, CountryIndex, CountryView, UrbanCenterIndex,
};

const ASSET_URL: &str = "https://assets.ente.com/location/v2";
const CITY_FILE: &str = "cities.bin";
const URBAN_CENTER_FILE: &str = "urban-centres.bin";
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
    urban_centers: UrbanCenterIndex,
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
            urban_centers: UrbanCenterIndex::from_path(directory.join(URBAN_CENTER_FILE))?,
            countries: CountryIndex::from_paths(
                directory.join(COUNTRY_FILE),
                directory.join(DISPUTE_FILE),
            )?,
        })
    }

    pub fn is_downloaded(asset_root: impl AsRef<Path>) -> bool {
        asset().is_ok_and(|asset| AssetStore::new(asset_root.as_ref()).is_downloaded(&asset))
    }

    pub fn cities(&self) -> Vec<ente_location::City> {
        self.cities.search("", usize::MAX)
    }

    pub fn group_cities(&self, coordinates: &[Coordinate], query: &str) -> Vec<CityMatch> {
        self.urban_centers
            .match_coordinates_with_cities(&self.cities, coordinates, query)
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

    pub fn country_names(&self) -> impl Iterator<Item = (CountryCode, &str)> {
        self.cities.country_names()
    }

    pub fn country_name(&self, code: CountryCode) -> Option<&str> {
        self.cities.country_name(code)
    }
}

fn asset() -> Result<Asset, ente_assets::download::Error> {
    Asset::files(
        vec!["location".into(), "v2".into()],
        vec![
            file(
                CITY_FILE,
                2_809_615,
                "898dca892a71fd601ae8e75e5c55fd6d4591e4c98de335d9b33e7f076aa668f5",
            ),
            file(
                URBAN_CENTER_FILE,
                1_825_064,
                "e981b0383e6502ede56b52d5be96cda66f53d7352492e677d8978467c106dab0",
            ),
            file(
                COUNTRY_FILE,
                2_504_017,
                "3ead1ef2bb03b4ffa95813df4316cf149d37c82d16a322352bd6e3b19218c796",
            ),
            file(
                DISPUTE_FILE,
                61_543,
                "c44d0af6ad40a3b195bc10cb87512c16998a20e837af190ff1a46b00170dfd7b",
            ),
        ],
    )
}

fn file(name: &str, size: u64, sha256: &str) -> AssetFile {
    AssetFile {
        name: name.into(),
        url: format!("{ASSET_URL}/{name}"),
        size,
        sha256: sha256.into(),
    }
}
