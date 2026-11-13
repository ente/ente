use std::env;
use std::error::Error;
use std::path::PathBuf;

use ente_location_dataset::{BuildOptions, RemoteSources, SourcePaths, build};

const USAGE: &str = concat!(
    "usage: ente-location-dataset build --output <directory> [--cache <directory>] ",
    "[--cities <file> --country-info <file> --alternate-names <zip> ",
    "--urban-centres <gpkg> --populated-places <dbf> --countries <shp> ",
    "--disputes <shp> --admin1 <shp>]"
);

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let Arguments {
        output,
        cache,
        cities,
        country_info,
        alternate_names,
        urban_centres,
        populated_places,
        countries,
        disputes,
        admin1,
    } = Arguments::parse()?;
    let sources = match (
        cities,
        country_info,
        alternate_names,
        urban_centres,
        populated_places,
        countries,
        disputes,
        admin1,
    ) {
        (None, None, None, None, None, None, None, None) => RemoteSources::new(cache).fetch()?,
        (
            Some(cities),
            Some(country_info),
            Some(alternate_names),
            Some(urban_centres),
            Some(populated_places),
            Some(countries),
            Some(disputes),
            Some(admin1),
        ) => SourcePaths {
            cities,
            country_info,
            alternate_names,
            urban_centres,
            populated_places,
            countries,
            disputes,
            admin1,
        },
        _ => return Err("local generation requires all eight source paths".into()),
    };
    let result = build(&BuildOptions { sources, output })?;
    println!("cities: {}", result.city_count);
    println!("urban centers: {}", result.urban_center_count);
    println!("Priority-1 territories: {}", result.territory_count);
    println!("bytes: {}", result.byte_length);
    for file in result.files {
        println!(
            "{}: {} bytes, sha256 {}",
            file.name, file.byte_length, file.sha256
        );
    }
    Ok(())
}

struct Arguments {
    output: PathBuf,
    cache: PathBuf,
    cities: Option<PathBuf>,
    country_info: Option<PathBuf>,
    alternate_names: Option<PathBuf>,
    urban_centres: Option<PathBuf>,
    populated_places: Option<PathBuf>,
    countries: Option<PathBuf>,
    disputes: Option<PathBuf>,
    admin1: Option<PathBuf>,
}

impl Arguments {
    fn parse() -> Result<Self, Box<dyn Error>> {
        let mut args = env::args().skip(1);
        if args.next().as_deref() != Some("build") {
            return Err(USAGE.into());
        }
        let mut output = None;
        let mut cache = None;
        let mut cities = None;
        let mut country_info = None;
        let mut alternate_names = None;
        let mut urban_centres = None;
        let mut populated_places = None;
        let mut countries = None;
        let mut disputes = None;
        let mut admin1 = None;
        while let Some(argument) = args.next() {
            let value = args.next().ok_or(USAGE)?;
            match argument.as_str() {
                "--output" => output = Some(value.into()),
                "--cache" => cache = Some(value.into()),
                "--cities" => cities = Some(value.into()),
                "--country-info" => country_info = Some(value.into()),
                "--alternate-names" => alternate_names = Some(value.into()),
                "--urban-centres" => urban_centres = Some(value.into()),
                "--populated-places" => populated_places = Some(value.into()),
                "--countries" => countries = Some(value.into()),
                "--disputes" => disputes = Some(value.into()),
                "--admin1" => admin1 = Some(value.into()),
                _ => return Err(USAGE.into()),
            }
        }
        Ok(Self {
            output: output.ok_or(USAGE)?,
            cache: cache.unwrap_or_else(default_cache),
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
}

fn default_cache() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/location-dataset/sources")
}
