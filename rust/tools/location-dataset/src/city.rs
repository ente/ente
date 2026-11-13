use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use ente_location::{CountryCode, normalize_search_text};
use shapefile::dbase::{FieldValue, Reader};
use zip::ZipArchive;

use crate::{Result, invalid};

const HEADER_LEN: usize = 76;
const NODE_LEN: usize = 3;
const POINT_LEN: usize = 15;
const NAME_OFFSET_LEN: usize = 3;
const MAX_U24: u32 = 0x00ff_ffff;
const ALTERNATE_NAMES_FILE: &str = "alternateNamesV2.txt";

struct SourceCity {
    source_id: u32,
    name: String,
    ascii_name: String,
    aliases: Vec<String>,
    country_code: [u8; 2],
    latitude: f64,
    longitude: f64,
    population: u64,
    importance: u8,
}

impl SourceCity {
    fn rank(&self) -> u8 {
        if self.importance == 0 || self.population >= 5_000_000 {
            4
        } else if self.importance == 1 || self.population >= 1_000_000 {
            3
        } else if self.importance == 2 || self.population >= 250_000 {
            2
        } else if self.population >= 50_000 {
            1
        } else {
            0
        }
    }
}

pub(crate) fn build(
    cities_path: &Path,
    country_info_path: &Path,
    alternate_names_path: &Path,
    populated_places_path: &Path,
) -> Result<Vec<u8>> {
    let countries = read_countries(country_info_path)?;
    let languages = read_country_languages(country_info_path)?;
    let mut cities = read_cities(cities_path, &countries)?;
    read_alternate_names(alternate_names_path, &mut cities, &languages)?;
    let override_ids = read_override_ids(populated_places_path)?;
    cities.sort_by(compare_priority);
    encode(&cities, &countries, &override_ids)
}

fn read_override_ids(path: &Path) -> Result<HashSet<u32>> {
    let mut reader = Reader::from_path(path).map_err(shapefile::Error::from)?;
    let mut ids = HashSet::new();
    for record in reader.iter_records() {
        let record = record.map_err(shapefile::Error::from)?;
        if let Some(FieldValue::Numeric(Some(id))) = record.get("GEONAMESID")
            && *id > 0.0
            && id.fract() == 0.0
        {
            ids.insert(*id as u32);
        }
    }
    if ids.is_empty() {
        return Err(invalid(
            "Natural Earth populated places contain no GeoNames IDs",
        ));
    }
    Ok(ids)
}

pub(crate) fn read_countries(path: &Path) -> Result<BTreeMap<[u8; 2], String>> {
    let reader = BufReader::new(File::open(path)?);
    let mut countries = BTreeMap::new();
    for line in reader.lines() {
        let line = line?;
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 5 {
            return Err(invalid("GeoNames countryInfo row has too few fields"));
        }
        let code = code(fields[0])?;
        let name = fields[4].trim();
        if name.is_empty() || countries.insert(code, name.to_owned()).is_some() {
            return Err(invalid(
                "GeoNames countryInfo contains an invalid duplicate",
            ));
        }
    }
    Ok(countries)
}

fn read_cities(path: &Path, countries: &BTreeMap<[u8; 2], String>) -> Result<Vec<SourceCity>> {
    let reader = BufReader::new(File::open(path)?);
    let mut cities = Vec::new();
    let mut source_ids = HashSet::new();
    for (line_index, line) in reader.lines().enumerate() {
        let line = line?;
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 19 {
            return Err(invalid(format!(
                "GeoNames city row {} has too few fields",
                line_index + 1
            )));
        }
        let feature_code = fields[7];
        if !is_current_place(feature_code) {
            continue;
        }
        let source_id = parse(fields[0], "GeoNames ID", line_index)?;
        let name = fields[1].trim();
        let ascii_name = fields[2].trim();
        let latitude: f64 = parse(fields[4], "latitude", line_index)?;
        let longitude: f64 = parse(fields[5], "longitude", line_index)?;
        let country_code = code(fields[8])?;
        let population = parse(fields[14], "population", line_index)?;
        if !countries.contains_key(&country_code) {
            return Err(invalid(format!(
                "GeoNames city row {} has unknown country {}",
                line_index + 1,
                fields[8]
            )));
        }
        if name.is_empty()
            || name.contains('\0')
            || ascii_name.contains('\0')
            || source_id > MAX_U24
            || !latitude.is_finite()
            || !(-90.0..=90.0).contains(&latitude)
            || !longitude.is_finite()
            || !(-180.0..=180.0).contains(&longitude)
            || !source_ids.insert(source_id)
        {
            return Err(invalid(format!(
                "GeoNames city row {} is invalid",
                line_index + 1
            )));
        }
        let importance = match feature_code {
            "PPLC" => 0,
            "PPLA" => 1,
            "PPLA2" | "PPLA3" | "PPLA4" => 2,
            _ => 3,
        };
        cities.push(SourceCity {
            source_id,
            name: name.to_owned(),
            ascii_name: ascii_name.to_owned(),
            aliases: Vec::new(),
            country_code,
            latitude,
            longitude,
            population,
            importance,
        });
    }
    if cities.is_empty() {
        return Err(invalid("GeoNames city source is empty"));
    }
    Ok(cities)
}

fn read_country_languages(path: &Path) -> Result<BTreeMap<[u8; 2], BTreeSet<String>>> {
    let reader = BufReader::new(File::open(path)?);
    let mut countries = BTreeMap::new();
    for line in reader.lines() {
        let line = line?;
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 16 {
            return Err(invalid("GeoNames countryInfo row has too few fields"));
        }
        let code = code(fields[0])?;
        let languages = fields[15]
            .split(',')
            .filter(|language| !language.is_empty())
            .map(language_base)
            .map(str::to_owned)
            .collect();
        countries.insert(code, languages);
    }
    Ok(countries)
}

fn read_alternate_names(
    path: &Path,
    cities: &mut [SourceCity],
    country_languages: &BTreeMap<[u8; 2], BTreeSet<String>>,
) -> Result<()> {
    let positions: HashMap<u32, usize> = cities
        .iter()
        .enumerate()
        .map(|(index, city)| (city.source_id, index))
        .collect();
    let mut archive = ZipArchive::new(File::open(path)?)?;
    let source = archive.by_name(ALTERNATE_NAMES_FILE)?;
    apply_alternate_names(
        BufReader::new(source),
        cities,
        &positions,
        country_languages,
    )?;
    finalize_aliases(cities);
    Ok(())
}

fn finalize_aliases(cities: &mut [SourceCity]) {
    for city in cities {
        city.aliases.sort_unstable();
        city.aliases.dedup();
        let name = normalize_search_text(&city.name);
        let ascii_name = normalize_search_text(&city.ascii_name);
        city.aliases
            .retain(|alias| alias != &name && alias != &ascii_name);
    }
}

fn apply_alternate_names(
    reader: impl BufRead,
    cities: &mut [SourceCity],
    positions: &HashMap<u32, usize>,
    country_languages: &BTreeMap<[u8; 2], BTreeSet<String>>,
) -> Result<()> {
    for (line_index, line) in reader.lines().enumerate() {
        let line = line?;
        let mut fields = line.split('\t');
        fields.next();
        let source_id: u32 = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?
            .parse()
            .map_err(|_| {
                invalid(format!(
                    "GeoNames alternate-name row {} has invalid ID",
                    line_index + 1
                ))
            })?;
        let Some(&city_index) = positions.get(&source_id) else {
            continue;
        };
        let language = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?;
        let name = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?
            .trim();
        let preferred = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?;
        fields.next();
        let colloquial = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?;
        let historic = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?;
        fields.next();
        let to = fields
            .next()
            .ok_or_else(|| invalid("GeoNames alternate-name row has too few fields"))?;
        let city = &mut cities[city_index];
        if !name.is_empty()
            && !name.contains('\0')
            && colloquial != "1"
            && historic != "1"
            && to.is_empty()
            && is_search_language(
                language,
                preferred == "1",
                &country_languages[&city.country_code],
            )
        {
            let alias = normalize_search_text(name);
            if !alias.is_empty() {
                city.aliases.push(alias);
            }
        }
    }
    Ok(())
}

fn is_search_language(
    language: &str,
    preferred: bool,
    country_languages: &BTreeSet<String>,
) -> bool {
    !matches!(
        language,
        "abbr" | "faac" | "iata" | "icao" | "link" | "post" | "unlc" | "wkdt"
    ) && (preferred
        || language_base(language) == "en"
        || country_languages.contains(language_base(language)))
}

fn language_base(language: &str) -> &str {
    language.split_once('-').map_or(language, |(base, _)| base)
}

fn is_current_place(feature_code: &str) -> bool {
    !matches!(feature_code, "PPLH" | "PPLQ" | "PPLW")
}

fn compare_priority(left: &SourceCity, right: &SourceCity) -> Ordering {
    right
        .rank()
        .cmp(&left.rank())
        .then_with(|| left.importance.cmp(&right.importance))
        .then_with(|| right.population.cmp(&left.population))
        .then_with(|| left.country_code.cmp(&right.country_code))
        .then_with(|| left.source_id.cmp(&right.source_id))
}

fn encode(
    cities: &[SourceCity],
    countries: &BTreeMap<[u8; 2], String>,
    override_ids: &HashSet<u32>,
) -> Result<Vec<u8>> {
    if cities.len() > MAX_U24 as usize {
        return Err(invalid("city index exceeds 24-bit point indices"));
    }
    let rank_ends = [4, 3, 2, 1].map(|rank| cities.partition_point(|city| city.rank() >= rank));
    let nodes = build_tree(cities, (0..cities.len()).collect());
    let override_nodes = build_tree(
        cities,
        cities
            .iter()
            .enumerate()
            .filter_map(|(index, city)| {
                (city.rank() >= 2 && override_ids.contains(&city.source_id)).then_some(index)
            })
            .collect(),
    );
    let mut names = Vec::<String>::new();
    let mut name_indices = HashMap::<String, u32>::new();
    let mut point_names = Vec::with_capacity(cities.len());
    for city in cities {
        let mut key = city.name.clone();
        if !city.ascii_name.is_empty() && city.ascii_name != city.name {
            key.push('\0');
            key.push_str(&city.ascii_name.to_lowercase());
        }
        for alias in &city.aliases {
            key.push('\0');
            key.push_str(alias);
        }
        let next = names.len() as u32;
        let index = *name_indices.entry(key.clone()).or_insert_with(|| {
            names.push(key);
            next
        });
        point_names.push(index);
    }

    let country_codes: Vec<[u8; 2]> = countries.keys().copied().collect();
    if country_codes.len() > 256 {
        return Err(invalid("city country table exceeds one-byte indices"));
    }
    let country_indices: BTreeMap<[u8; 2], u8> = country_codes
        .iter()
        .copied()
        .enumerate()
        .map(|(index, code)| (code, index as u8))
        .collect();
    let name_table = string_table_u24(names.iter().map(String::as_str))?;
    let country_table = string_table_u32(countries.values().map(String::as_str))?;
    let nodes_offset = HEADER_LEN;
    let override_nodes_offset = nodes_offset + nodes.len() * NODE_LEN;
    let points_offset = override_nodes_offset + override_nodes.len() * NODE_LEN;
    let name_offsets_offset = points_offset + cities.len() * POINT_LEN;
    let names_offset = name_offsets_offset + name_table.0.len();
    let country_offsets_offset = names_offset + name_table.1.len();
    let countries_offset = country_offsets_offset + country_table.0.len();
    let country_codes_offset = countries_offset + country_table.1.len();
    let file_length = country_codes_offset + country_codes.len() * 2;
    let mut output = vec![0; file_length];

    output[..4].copy_from_slice(b"CITY");
    put_u16(&mut output, 4, 2);
    put_u16(&mut output, 6, HEADER_LEN as u16);
    put_len(&mut output, 8, cities.len())?;
    put_len(&mut output, 12, names.len())?;
    put_u16(
        &mut output,
        16,
        u16::try_from(country_codes.len()).map_err(|_| invalid("too many countries"))?,
    );
    put_u16(&mut output, 18, POINT_LEN as u16);
    put_u16(&mut output, 20, NODE_LEN as u16);
    put_u16(&mut output, 22, NAME_OFFSET_LEN as u16);
    for (field, value) in [
        (24, nodes_offset),
        (28, points_offset),
        (32, name_offsets_offset),
        (36, names_offset),
        (40, country_offsets_offset),
        (44, countries_offset),
        (48, country_codes_offset),
        (52, file_length),
    ] {
        put_len(&mut output, field, value)?;
    }
    for (field, value) in [56, 60, 64, 68].into_iter().zip(rank_ends) {
        put_len(&mut output, field, value)?;
    }
    put_len(&mut output, 72, override_nodes.len())?;

    for (index, &point) in nodes.iter().enumerate() {
        let offset = nodes_offset + index * NODE_LEN;
        put_u24(&mut output, offset, point as u32);
    }
    for (index, &point) in override_nodes.iter().enumerate() {
        let offset = override_nodes_offset + index * NODE_LEN;
        put_u24(&mut output, offset, point as u32);
    }
    for (index, city) in cities.iter().enumerate() {
        let offset = points_offset + index * POINT_LEN;
        output[offset..offset + 4].copy_from_slice(&(city.latitude as f32).to_le_bytes());
        output[offset + 4..offset + 8].copy_from_slice(&(city.longitude as f32).to_le_bytes());
        put_u24(&mut output, offset + 8, point_names[index]);
        output[offset + 11] = country_indices[&city.country_code];
        put_u24(&mut output, offset + 12, city.source_id);
    }
    copy(&mut output, name_offsets_offset, &name_table.0);
    copy(&mut output, names_offset, &name_table.1);
    copy(&mut output, country_offsets_offset, &country_table.0);
    copy(&mut output, countries_offset, &country_table.1);
    for (index, code) in country_codes.iter().enumerate() {
        copy(&mut output, country_codes_offset + index * 2, code);
    }
    Ok(output)
}

fn build_tree(cities: &[SourceCity], mut points: Vec<usize>) -> Vec<usize> {
    fn build(cities: &[SourceCity], nodes: &mut Vec<usize>, points: &mut [usize], depth: usize) {
        if points.is_empty() {
            return;
        }
        let axis = depth % 2;
        let median = points.len() / 2;
        points.select_nth_unstable_by(median, |&left, &right| {
            let ordering = if axis == 0 {
                cities[left].latitude.total_cmp(&cities[right].latitude)
            } else {
                cities[left].longitude.total_cmp(&cities[right].longitude)
            };
            ordering.then_with(|| left.cmp(&right))
        });
        let point = points[median];
        nodes.push(point);
        let (left, right_with_median) = points.split_at_mut(median);
        #[expect(
            clippy::expect_used,
            reason = "The nonempty input slice contains its median element"
        )]
        let (_, right) = right_with_median
            .split_first_mut()
            .expect("nonempty median slice");
        build(cities, nodes, left, depth + 1);
        build(cities, nodes, right, depth + 1);
    }

    let mut nodes = Vec::with_capacity(points.len());
    build(cities, &mut nodes, &mut points, 0);
    nodes
}

fn string_table_u24<'a>(
    values: impl ExactSizeIterator<Item = &'a str>,
) -> Result<(Vec<u8>, Vec<u8>)> {
    let mut offsets = Vec::with_capacity((values.len() + 1) * NAME_OFFSET_LEN);
    let mut blob = Vec::new();
    for value in values {
        push_u24(&mut offsets, blob.len())?;
        blob.extend_from_slice(value.as_bytes());
    }
    push_u24(&mut offsets, blob.len())?;
    Ok((offsets, blob))
}

pub(crate) fn string_table_u32<'a>(
    values: impl ExactSizeIterator<Item = &'a str>,
) -> Result<(Vec<u8>, Vec<u8>)> {
    let mut offsets = Vec::with_capacity((values.len() + 1) * 4);
    let mut blob = Vec::new();
    for value in values {
        offsets.extend_from_slice(
            &u32::try_from(blob.len())
                .map_err(|_| invalid("string table exceeds 4 GiB"))?
                .to_le_bytes(),
        );
        blob.extend_from_slice(value.as_bytes());
    }
    offsets.extend_from_slice(
        &u32::try_from(blob.len())
            .map_err(|_| invalid("string table exceeds 4 GiB"))?
            .to_le_bytes(),
    );
    Ok((offsets, blob))
}

fn code(value: &str) -> Result<[u8; 2]> {
    value
        .trim()
        .parse::<CountryCode>()
        .map(CountryCode::as_bytes)
        .map_err(|_| invalid(format!("invalid country code {value:?}")))
}

fn parse<T: std::str::FromStr>(value: &str, field: &str, line_index: usize) -> Result<T> {
    value.parse().map_err(|_| {
        invalid(format!(
            "GeoNames city row {} has invalid {field}",
            line_index + 1
        ))
    })
}

fn put_u16(output: &mut [u8], offset: usize, value: u16) {
    output[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_u32(output: &mut [u8], offset: usize, value: u32) {
    output[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn put_u24(output: &mut [u8], offset: usize, value: u32) {
    output[offset..offset + 3].copy_from_slice(&value.to_le_bytes()[..3]);
}

fn push_u24(output: &mut Vec<u8>, value: usize) -> Result<()> {
    let value = u32::try_from(value).map_err(|_| invalid("city name table exceeds 16 MiB"))?;
    if value > MAX_U24 {
        return Err(invalid("city name table exceeds 16 MiB"));
    }
    output.extend_from_slice(&value.to_le_bytes()[..3]);
    Ok(())
}

fn put_len(output: &mut [u8], offset: usize, value: usize) -> Result<()> {
    put_u32(
        output,
        offset,
        u32::try_from(value).map_err(|_| invalid("city index exceeds 4 GiB"))?,
    );
    Ok(())
}

fn copy(output: &mut [u8], offset: usize, bytes: &[u8]) {
    output[offset..offset + bytes.len()].copy_from_slice(bytes);
}

#[cfg(test)]
mod tests {
    use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
    use std::io::Cursor;

    use ente_location::{CityIndex, Coordinate, CountryCode};

    use super::{SourceCity, apply_alternate_names, encode, finalize_aliases};

    #[test]
    fn round_trips_city_search_and_lookup() {
        let mut munich = city(3, "Munich", "Munich", *b"DE", 48.1374, 11.5755, 3);
        munich.aliases = vec!["garching bei munchen".to_owned(), "munchen".to_owned()];
        let cities = vec![
            city(1, "Delhi", "Delhi", *b"IN", 28.6139, 77.2090, 4),
            city(2, "Zürich", "Zuerich", *b"CH", 47.3667, 8.5500, 3),
            munich,
            city(4, "Small Town", "Small Town", *b"IN", 0.0, 0.0, 0),
        ];
        let countries = BTreeMap::from([
            (*b"CH", "Switzerland".to_owned()),
            (*b"DE", "Germany".to_owned()),
            (*b"IN", "India".to_owned()),
        ]);
        let bytes = encode(&cities, &countries, &HashSet::from([1, 2, 3])).unwrap();
        let index = CityIndex::from_bytes(bytes).unwrap();

        assert_eq!(index.search("zurich", 5)[0].name, "Zürich");
        assert_eq!(index.search("ZUERICH", 5)[0].name, "Zürich");
        assert_eq!(index.search("München", 5)[0].name, "Munich");
        assert_eq!(index.search("Garching bei München", 5)[0].name, "Munich");
        assert_eq!(
            index.match_coordinates(&[Coordinate::new(0.0, 0.0)], "")[0]
                .city
                .name,
            "Small Town"
        );
        assert!(
            index
                .match_override_coordinates(&[Coordinate::new(0.0, 0.0)], "")
                .is_empty()
        );
        assert!(
            index
                .match_override_coordinates(&[Coordinate::new(28.65, 77.209)], "")
                .is_empty()
        );
        assert_eq!(
            index.match_coordinates(&[Coordinate::new(28.71, 77.209)], "")[0]
                .city
                .name,
            "Delhi"
        );
        assert_eq!(
            index.match_override_coordinates(&[Coordinate::new(28.61, 77.21)], "")[0]
                .city
                .country_code,
            CountryCode::from_bytes(*b"IN").unwrap()
        );
    }

    #[test]
    fn keeps_current_preferred_and_local_aliases() {
        let mut cities = vec![city(1, "Munich", "Munich", *b"DE", 48.1, 11.5, 3)];
        let positions = HashMap::from([(1, 0)]);
        let languages = BTreeMap::from([(*b"DE", BTreeSet::from(["de".to_owned()]))]);
        let source = concat!(
            "1\t1\tde\tMünchen\t1\t\t\t\t\t\n",
            "2\t1\tde\tMuenchen\t\t\t\t\t\t\n",
            "3\t1\ten\tOld Munich\t\t\t\t1\t\t\n",
            "4\t1\tlink\thttps://example.com\t1\t\t\t\t\t\n"
        );

        apply_alternate_names(Cursor::new(source), &mut cities, &positions, &languages).unwrap();
        finalize_aliases(&mut cities);

        assert_eq!(cities[0].aliases, ["muenchen", "munchen"]);
    }

    fn city(
        source_id: u32,
        name: &str,
        ascii_name: &str,
        country_code: [u8; 2],
        latitude: f64,
        longitude: f64,
        rank: u8,
    ) -> SourceCity {
        SourceCity {
            source_id,
            name: name.to_owned(),
            ascii_name: ascii_name.to_owned(),
            aliases: Vec::new(),
            country_code,
            latitude,
            longitude,
            population: [10_000, 100_000, 300_000, 1_500_000, 6_000_000][usize::from(rank)],
            importance: 3,
        }
    }
}
