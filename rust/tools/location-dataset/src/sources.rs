use std::path::PathBuf;

use reqwest::blocking::Client;

use crate::Result;
use crate::download::{download, extract};

const CITIES_URL: &str = "https://download.geonames.org/export/dump/cities5000.zip";
const COUNTRY_INFO_URL: &str = "https://download.geonames.org/export/dump/countryInfo.txt";
const ALTERNATE_NAMES_URL: &str = "https://download.geonames.org/export/dump/alternateNamesV2.zip";
const URBAN_CENTRES_FILE: &str = "GHS_UCDB_THEME_GENERAL_CHARACTERISTICS_GLOBE_R2024A.gpkg";
const URBAN_CENTRES_URL: &str = concat!(
    "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/",
    "GHS_UCDB_GLOBE_R2024A/GHS_UCDB_THEME_GLOBE_R2024A/",
    "GHS_UCDB_THEME_GENERAL_CHARACTERISTICS_GLOBE_R2024A/V1-2/",
    "GHS_UCDB_THEME_GENERAL_CHARACTERISTICS_GLOBE_R2024A_V1_2.zip"
);
const POPULATED_PLACES: &str = "ne_10m_populated_places";
const POPULATED_PLACES_URL: &str =
    "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_populated_places.zip";
const COUNTRIES: &str = "ne_10m_admin_0_countries";
const COUNTRIES_URL: &str =
    "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip";
const DISPUTES: &str = "ne_10m_admin_0_disputed_areas";
const DISPUTES_URL: &str =
    "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_disputed_areas.zip";
const ADMIN1: &str = "ne_10m_admin_1_states_provinces";
const ADMIN1_URL: &str =
    "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_1_states_provinces.zip";

#[derive(Clone, Debug)]
pub struct SourcePaths {
    pub cities: PathBuf,
    pub country_info: PathBuf,
    pub alternate_names: PathBuf,
    pub urban_centres: PathBuf,
    pub populated_places: PathBuf,
    pub countries: PathBuf,
    pub disputes: PathBuf,
    pub admin1: PathBuf,
}

#[derive(Clone, Debug)]
pub struct RemoteSources {
    cache: PathBuf,
}

impl RemoteSources {
    pub fn new(cache: impl Into<PathBuf>) -> Self {
        Self {
            cache: cache.into(),
        }
    }

    pub fn fetch(&self) -> Result<SourcePaths> {
        std::fs::create_dir_all(&self.cache)?;
        let client = Client::builder()
            .user_agent("ente-location-dataset")
            .build()?;
        let cities_archive = self.cache.join("cities5000.zip");
        let cities = self.cache.join("cities5000.txt");
        let country_info = self.cache.join("countryInfo.txt");
        let alternate_names = self.cache.join("alternateNamesV2.zip");
        download(&client, CITIES_URL, &cities_archive)?;
        download(&client, COUNTRY_INFO_URL, &country_info)?;
        download(&client, ALTERNATE_NAMES_URL, &alternate_names)?;
        extract(&cities_archive, &cities, "cities5000.txt")?;
        let urban_centres_archive = self.cache.join("ghsl-urban-centres-v1.2.zip");
        let urban_centres = self.cache.join(URBAN_CENTRES_FILE);
        download(&client, URBAN_CENTRES_URL, &urban_centres_archive)?;
        extract(&urban_centres_archive, &urban_centres, URBAN_CENTRES_FILE)?;
        let populated_places = self.fetch_dbf(&client, POPULATED_PLACES, POPULATED_PLACES_URL)?;
        let countries = self.fetch_shapefile(&client, COUNTRIES, COUNTRIES_URL)?;
        let disputes = self.fetch_shapefile(&client, DISPUTES, DISPUTES_URL)?;
        let admin1 = self.fetch_shapefile(&client, ADMIN1, ADMIN1_URL)?;
        Ok(SourcePaths {
            cities,
            country_info,
            alternate_names,
            urban_centres,
            populated_places,
            countries,
            disputes,
            admin1,
        })
    }

    fn fetch_dbf(&self, client: &Client, name: &str, url: &str) -> Result<PathBuf> {
        let archive = self.cache.join(format!("{name}.zip"));
        download(client, url, &archive)?;
        let file = format!("{name}.dbf");
        let path = self.cache.join(&file);
        extract(&archive, &path, &file)?;
        Ok(path)
    }

    fn fetch_shapefile(&self, client: &Client, name: &str, url: &str) -> Result<PathBuf> {
        let archive = self.cache.join(format!("{name}.zip"));
        download(client, url, &archive)?;
        for extension in ["shp", "shx", "dbf"] {
            let file = format!("{name}.{extension}");
            extract(&archive, &self.cache.join(&file), &file)?;
        }
        Ok(self.cache.join(format!("{name}.shp")))
    }
}
