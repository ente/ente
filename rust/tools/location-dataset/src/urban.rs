use std::collections::BTreeMap;
use std::f64::consts::{PI, SQRT_2};
use std::path::Path;

use ente_location::{City, CityIndex, Coordinate, UrbanCenterIndex, normalize_search_text};
use geo::{BoundingRect, Coord, Distance, Haversine, LineString, MultiPolygon, Point, Polygon};
use rusqlite::{Connection, OpenFlags};

use crate::city::{read_countries, string_table_u32};
use crate::{Result, invalid};

const QUERY: &str = concat!(
    "SELECT u.ID_UC_G0, u.GC_UCN_MAI_2025, u.GC_CNT_UNN_2025, ",
    "c.GC_UCC_LON_2025, c.GC_UCC_LAT_2025, u.geom ",
    "FROM GHSL_UCDB_THEME_GENERAL_CHARACTERISTICS_GLOBE_R2024A u ",
    "JOIN UC_centroids c USING (ID_UC_G0) ",
    "WHERE u.GC_PLS_SCR_2025 IN ('High', 'Medium') ",
    "AND trim(u.GC_UCN_MAI_2025) != '' ORDER BY u.ID_UC_G0"
);
const COLUMNS: u16 = 360;
const ROWS: u16 = 180;
const HEADER_LEN: usize = 72;
const RECORD_LEN: usize = 41;
const BLOCK_SIZE: usize = 64;
const BLOCK_LEN: usize = 12;
const BOUNDS_PADDING: f64 = 0.0001;
const MOLLWEIDE_RADIUS: f64 = 6_378_137.0;
const GHSL_SOURCE_BIT: u32 = 1 << 31;
const MAX_NAME_MATCH_DISTANCE_METERS: f64 = 30_000.0;

struct SourceCenter {
    source_id: u32,
    name: String,
    country_code: [u8; 2],
    centroid: Coordinate,
    geometry: MultiPolygon<f64>,
}

#[derive(Clone, Copy)]
struct Bounds {
    minimum_longitude: f64,
    minimum_latitude: f64,
    maximum_longitude: f64,
    maximum_latitude: f64,
}

pub(crate) fn build(
    path: &Path,
    country_info_path: &Path,
    city_index: &CityIndex,
) -> Result<Vec<u8>> {
    let countries = read_countries(country_info_path)?;
    let mut cities_by_name = BTreeMap::<([u8; 2], String), Vec<City>>::new();
    for city in city_index.search("", usize::MAX) {
        cities_by_name
            .entry((
                city.country_code.as_bytes(),
                normalize_search_text(&city.name),
            ))
            .or_default()
            .push(city);
    }
    let connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let mut statement = connection.prepare(QUERY)?;
    let rows = statement.query_map([], |row| {
        Ok((
            row.get::<_, u32>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, f64>(3)?,
            row.get::<_, f64>(4)?,
            row.get::<_, Vec<u8>>(5)?,
        ))
    })?;
    let mut centers = Vec::new();
    for row in rows {
        let (source_id, name, country, centroid_x, centroid_y, geometry) = row?;
        if source_id & GHSL_SOURCE_BIT != 0 {
            return Err(invalid("GHSL urban center ID exceeds 31 bits"));
        }
        let country_code = resolve_country(&country, &countries)
            .ok_or_else(|| invalid(format!("unknown GHSL country {country}")))?;
        let centroid = mollweide_to_wgs84(centroid_x, centroid_y)?;
        let geometry = decode_geopackage_geometry(&geometry)?;
        let key = (country_code, normalize_search_text(&name));
        let named = canonical_name_city(
            cities_by_name
                .get(&key)
                .map(Vec::as_slice)
                .unwrap_or_default(),
            centroid,
        );
        centers.push(match named {
            Some(city) => SourceCenter {
                source_id: city.source_id,
                name: city.name.clone(),
                country_code,
                centroid: Coordinate::new(city.latitude, city.longitude),
                geometry,
            },
            None => SourceCenter {
                source_id: source_id | GHSL_SOURCE_BIT,
                name,
                country_code,
                centroid,
                geometry,
            },
        });
    }
    encode(&centers, &countries)
}

fn canonical_name_city(cities: &[City], centroid: Coordinate) -> Option<&City> {
    let centroid = Point::new(centroid.longitude, centroid.latitude);
    cities
        .iter()
        .map(|city| {
            let distance = Haversine.distance(centroid, Point::new(city.longitude, city.latitude));
            (city, distance)
        })
        .filter(|(_, distance)| *distance <= MAX_NAME_MATCH_DISTANCE_METERS)
        .min_by(|left, right| left.1.total_cmp(&right.1))
        .map(|(city, _)| city)
}

fn encode(
    centers: &[SourceCenter],
    source_countries: &BTreeMap<[u8; 2], String>,
) -> Result<Vec<u8>> {
    if centers.is_empty() || centers.len() > usize::from(u16::MAX) {
        return Err(invalid("urban center count does not fit the index"));
    }

    let countries: BTreeMap<[u8; 2], &str> = centers
        .iter()
        .map(|center| {
            (
                center.country_code,
                source_countries[&center.country_code].as_str(),
            )
        })
        .collect();
    if countries.len() > 256 {
        return Err(invalid("urban center country count exceeds 256"));
    }
    let country_indices: BTreeMap<[u8; 2], u8> = countries
        .keys()
        .copied()
        .enumerate()
        .map(|(index, code)| (code, index as u8))
        .collect();
    let bounds: Vec<Bounds> = centers
        .iter()
        .map(|center| geometry_bounds(&center.geometry))
        .collect::<Result<_>>()?;

    let mut names = Vec::new();
    let mut name_offsets = Vec::with_capacity(centers.len());
    for center in centers {
        if center.name.contains('\0') {
            return Err(invalid("urban center name contains NUL"));
        }
        name_offsets.push(names.len());
        names.extend_from_slice(center.name.as_bytes());
        names.push(0);
    }

    let mut geometry = Vec::new();
    let mut geometry_offsets = Vec::with_capacity(centers.len() + 1);
    geometry_offsets.push(0);
    for (center, &bounds) in centers.iter().zip(&bounds) {
        encode_geometry(&mut geometry, &center.geometry, bounds)?;
        geometry_offsets.push(geometry.len());
    }

    let (country_offsets, country_names) = string_table_u32(countries.values().copied())?;
    let country_codes: Vec<u8> = countries.keys().flatten().copied().collect();
    let cells = grid(&bounds)?;
    let block_count = cells.len().div_ceil(BLOCK_SIZE);
    let nonempty_count = cells.iter().filter(|cell| !cell.is_empty()).count();
    let reference_count: usize = cells.iter().map(Vec::len).sum();

    let records_offset = HEADER_LEN;
    let names_offset = records_offset + centers.len() * RECORD_LEN;
    let geometry_offset = names_offset + names.len();
    let country_offsets_offset = geometry_offset + geometry.len();
    let countries_offset = country_offsets_offset + country_offsets.len();
    let country_codes_offset = countries_offset + country_names.len();
    let blocks_offset = country_codes_offset + country_codes.len();
    let cell_offsets_offset = blocks_offset + block_count * BLOCK_LEN;
    let references_offset = cell_offsets_offset + (nonempty_count + 1) * 4;
    let file_length = references_offset + reference_count * 2;

    let mut output = Vec::with_capacity(file_length);
    output.extend_from_slice(b"URBN");
    push_u16(&mut output, 1);
    push_u16(&mut output, HEADER_LEN as u16);
    push_len(&mut output, centers.len())?;
    push_u16(&mut output, countries.len() as u16);
    push_u16(&mut output, COLUMNS);
    push_u16(&mut output, ROWS);
    push_u16(&mut output, BLOCK_SIZE as u16);
    for value in [
        block_count,
        nonempty_count,
        records_offset,
        names_offset,
        geometry_offset,
        country_offsets_offset,
        countries_offset,
        country_codes_offset,
        blocks_offset,
        cell_offsets_offset,
        references_offset,
        file_length,
        reference_count,
    ] {
        push_len(&mut output, value)?;
    }
    debug_assert_eq!(output.len(), HEADER_LEN);

    for (index, center) in centers.iter().enumerate() {
        let bounds = bounds[index];
        for value in [
            bounds.minimum_longitude,
            bounds.minimum_latitude,
            bounds.maximum_longitude,
            bounds.maximum_latitude,
            center.centroid.latitude,
            center.centroid.longitude,
        ] {
            output.extend_from_slice(&(value as f32).to_le_bytes());
        }
        push_len(&mut output, names_offset + name_offsets[index])?;
        push_len(&mut output, geometry_offset + geometry_offsets[index])?;
        push_len(&mut output, geometry_offset + geometry_offsets[index + 1])?;
        output.extend_from_slice(&center.source_id.to_le_bytes());
        output.push(country_indices[&center.country_code]);
    }
    output.extend_from_slice(&names);
    output.extend_from_slice(&geometry);
    output.extend_from_slice(&country_offsets);
    output.extend_from_slice(&country_names);
    output.extend_from_slice(&country_codes);

    let mut dense_start = 0;
    for block in cells.chunks(BLOCK_SIZE) {
        let mask = block.iter().enumerate().fold(0_u64, |mask, (bit, cell)| {
            mask | ((!cell.is_empty()) as u64) << bit
        });
        output.extend_from_slice(&mask.to_le_bytes());
        push_len(&mut output, dense_start)?;
        dense_start += mask.count_ones() as usize;
    }
    let mut reference_offset = 0;
    push_len(&mut output, reference_offset)?;
    for cell in cells.iter().filter(|cell| !cell.is_empty()) {
        reference_offset += cell.len();
        push_len(&mut output, reference_offset)?;
    }
    for cell in cells.iter().filter(|cell| !cell.is_empty()) {
        for &reference in cell {
            push_u16(&mut output, reference);
        }
    }
    debug_assert_eq!(output.len(), file_length);
    UrbanCenterIndex::from_bytes(output.as_slice())?;
    Ok(output)
}

fn geometry_bounds(geometry: &MultiPolygon<f64>) -> Result<Bounds> {
    let bounds = geometry
        .bounding_rect()
        .ok_or_else(|| invalid("urban center has empty geometry"))?;
    Ok(Bounds {
        minimum_longitude: (bounds.min().x - BOUNDS_PADDING).max(-180.0),
        minimum_latitude: (bounds.min().y - BOUNDS_PADDING).max(-90.0),
        maximum_longitude: (bounds.max().x + BOUNDS_PADDING).min(180.0),
        maximum_latitude: (bounds.max().y + BOUNDS_PADDING).min(90.0),
    })
}

fn encode_geometry(
    output: &mut Vec<u8>,
    geometry: &MultiPolygon<f64>,
    bounds: Bounds,
) -> Result<()> {
    push_count(output, geometry.0.len(), "too many urban center polygons")?;
    for polygon in geometry {
        push_count(
            output,
            polygon.interiors().len() + 1,
            "too many urban center rings",
        )?;
        for ring in std::iter::once(polygon.exterior()).chain(polygon.interiors()) {
            push_count(output, ring.0.len(), "urban center ring is too long")?;
            for coordinate in &ring.0 {
                push_u16(
                    output,
                    quantize(
                        coordinate.x,
                        bounds.minimum_longitude,
                        bounds.maximum_longitude,
                    ),
                );
                push_u16(
                    output,
                    quantize(
                        coordinate.y,
                        bounds.minimum_latitude,
                        bounds.maximum_latitude,
                    ),
                );
            }
        }
    }
    Ok(())
}

fn grid(bounds: &[Bounds]) -> Result<Vec<Vec<u16>>> {
    let mut cells = vec![Vec::new(); usize::from(COLUMNS) * usize::from(ROWS)];
    for (index, bounds) in bounds.iter().enumerate() {
        let index = u16::try_from(index).map_err(|_| invalid("too many urban centers"))?;
        for row in latitude_row(bounds.maximum_latitude)..=latitude_row(bounds.minimum_latitude) {
            for column in longitude_column(bounds.minimum_longitude)
                ..=longitude_column(bounds.maximum_longitude)
            {
                cells[row * usize::from(COLUMNS) + column].push(index);
            }
        }
    }
    Ok(cells)
}

fn longitude_column(longitude: f64) -> usize {
    (((longitude + 180.0) / 360.0) * f64::from(COLUMNS))
        .floor()
        .clamp(0.0, f64::from(COLUMNS - 1)) as usize
}

fn latitude_row(latitude: f64) -> usize {
    (((90.0 - latitude) / 180.0) * f64::from(ROWS))
        .floor()
        .clamp(0.0, f64::from(ROWS - 1)) as usize
}

fn quantize(value: f64, minimum: f64, maximum: f64) -> u16 {
    (((value - minimum) * f64::from(u16::MAX) / (maximum - minimum))
        .clamp(0.0, f64::from(u16::MAX))) as u16
}

fn resolve_country(name: &str, countries: &BTreeMap<[u8; 2], String>) -> Option<[u8; 2]> {
    countries
        .iter()
        .find_map(|(&code, country)| (country == name).then_some(code))
        .or_else(|| country_alias(name).filter(|code| countries.contains_key(code)))
}

fn country_alias(name: &str) -> Option<[u8; 2]> {
    Some(*match name {
        "Bolivia (Plurinational State of)" => b"BO",
        "Brunei Darussalam" => b"BN",
        "China, Taiwan Province of China" => b"TW",
        "Congo" => b"CG",
        "CuraÃ§ao" => b"CW",
        "CÃ´te d'Ivoire" => b"CI",
        "Dem. People's Republic of Korea" => b"KP",
        "Iran (Islamic Republic of)" => b"IR",
        "Kosovo (under UNSC res. 1244)" => b"XK",
        "Lao People's Democratic Republic" => b"LA",
        "Netherlands" => b"NL",
        "Republic of Korea" => b"KR",
        "Republic of Moldova" => b"MD",
        "Russian Federation" => b"RU",
        "RÃ©union" => b"RE",
        "State of Palestine" => b"PS",
        "Syrian Arab Republic" => b"SY",
        "Timor-Leste" => b"TL",
        "United Republic of Tanzania" => b"TZ",
        "United States of America" => b"US",
        "Venezuela (Bolivarian Republic of)" => b"VE",
        "Viet Nam" => b"VN",
        _ => return None,
    })
}

fn decode_geopackage_geometry(bytes: &[u8]) -> Result<MultiPolygon<f64>> {
    let Some(&[b'G', b'P', 0, flags, srs @ ..]) = bytes.first_chunk::<8>() else {
        return Err(invalid("invalid GHSL GeoPackage geometry header"));
    };
    if flags & 1 == 0 || flags & 0x10 != 0 {
        return Err(invalid("unsupported GHSL GeoPackage geometry flags"));
    }
    let srs = i32::from_le_bytes(srs);
    if srs != 54_009 {
        return Err(invalid(format!("unexpected GHSL spatial reference {srs}")));
    }
    let envelope_length = match (flags >> 1) & 7 {
        0 => 0,
        1 => 32,
        2 | 3 => 48,
        4 => 64,
        _ => return Err(invalid("invalid GHSL GeoPackage envelope")),
    };
    let mut reader = WkbReader::new(
        bytes
            .get(8 + envelope_length..)
            .ok_or_else(|| invalid("truncated GHSL GeoPackage geometry"))?,
    );
    let geometry = reader.multi_polygon()?;
    if reader.position != reader.bytes.len() {
        return Err(invalid("GHSL geometry has trailing bytes"));
    }
    Ok(geometry)
}

struct WkbReader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> WkbReader<'a> {
    const fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, position: 0 }
    }

    fn multi_polygon(&mut self) -> Result<MultiPolygon<f64>> {
        let endian = self.header(6)?;
        let count = self.u32(endian)? as usize;
        let polygons = (0..count)
            .map(|_| self.polygon())
            .collect::<Result<Vec<_>>>()?;
        Ok(MultiPolygon::new(polygons))
    }

    fn polygon(&mut self) -> Result<Polygon<f64>> {
        let endian = self.header(3)?;
        let count = self.u32(endian)? as usize;
        if count == 0 {
            return Err(invalid("GHSL polygon has no rings"));
        }
        let mut rings = (0..count)
            .map(|_| self.ring(endian))
            .collect::<Result<Vec<_>>>()?;
        Ok(Polygon::new(rings.remove(0), rings))
    }

    fn ring(&mut self, endian: Endian) -> Result<LineString<f64>> {
        let count = self.u32(endian)? as usize;
        if count < 4 {
            return Err(invalid("GHSL polygon ring is too short"));
        }
        let coordinates = (0..count)
            .map(|_| {
                let x = self.f64(endian)?;
                let y = self.f64(endian)?;
                let coordinate = mollweide_to_wgs84(x, y)?;
                Ok(Coord {
                    x: coordinate.longitude,
                    y: coordinate.latitude,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(LineString::new(coordinates))
    }

    fn header(&mut self, expected_type: u32) -> Result<Endian> {
        let endian = match self.byte()? {
            0 => Endian::Big,
            1 => Endian::Little,
            _ => return Err(invalid("invalid GHSL WKB byte order")),
        };
        let geometry_type = self.u32(endian)?;
        if geometry_type != expected_type {
            return Err(invalid(format!(
                "unexpected GHSL WKB geometry type {geometry_type}"
            )));
        }
        Ok(endian)
    }

    fn byte(&mut self) -> Result<u8> {
        let byte = *self
            .bytes
            .get(self.position)
            .ok_or_else(|| invalid("truncated GHSL WKB geometry"))?;
        self.position += 1;
        Ok(byte)
    }

    fn u32(&mut self, endian: Endian) -> Result<u32> {
        let bytes = self.take::<4>()?;
        Ok(match endian {
            Endian::Little => u32::from_le_bytes(bytes),
            Endian::Big => u32::from_be_bytes(bytes),
        })
    }

    fn f64(&mut self, endian: Endian) -> Result<f64> {
        let bytes = self.take::<8>()?;
        Ok(match endian {
            Endian::Little => f64::from_le_bytes(bytes),
            Endian::Big => f64::from_be_bytes(bytes),
        })
    }

    fn take<const N: usize>(&mut self) -> Result<[u8; N]> {
        let bytes = self
            .bytes
            .get(self.position..)
            .and_then(|bytes| bytes.first_chunk::<N>())
            .ok_or_else(|| invalid("truncated GHSL WKB geometry"))?;
        self.position += N;
        Ok(*bytes)
    }
}

#[derive(Clone, Copy)]
enum Endian {
    Little,
    Big,
}

fn mollweide_to_wgs84(x: f64, y: f64) -> Result<Coordinate> {
    let theta = (y / (MOLLWEIDE_RADIUS * SQRT_2)).asin();
    let latitude = ((2.0 * theta + (2.0 * theta).sin()) / PI).asin();
    let longitude = PI * x / (2.0 * MOLLWEIDE_RADIUS * SQRT_2 * theta.cos());
    let coordinate = Coordinate::new(latitude.to_degrees(), longitude.to_degrees());
    coordinate
        .is_valid()
        .then_some(coordinate)
        .ok_or_else(|| invalid("GHSL geometry has an invalid coordinate"))
}

fn push_count(output: &mut Vec<u8>, value: usize, message: &str) -> Result<()> {
    push_u16(output, u16::try_from(value).map_err(|_| invalid(message))?);
    Ok(())
}

fn push_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn push_len(output: &mut Vec<u8>, value: usize) -> Result<()> {
    output.extend_from_slice(
        &u32::try_from(value)
            .map_err(|_| invalid("urban center index exceeds 4 GiB"))?
            .to_le_bytes(),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use ente_location::CountryCode;

    use super::*;

    #[test]
    fn encoded_geometry_preserves_polygons_holes_and_metadata() {
        let centers = vec![
            center(
                7,
                "Donut",
                vec![
                    Polygon::new(square(0.0, 0.0, 2.0, 2.0), vec![square(0.5, 0.5, 1.5, 1.5)]),
                    Polygon::new(square(5.0, 5.0, 6.0, 6.0), Vec::new()),
                ],
            ),
            center(
                8,
                "Neighbour",
                vec![Polygon::new(square(3.0, 3.0, 4.0, 4.0), Vec::new())],
            ),
            center(
                7,
                "Donut",
                vec![Polygon::new(square(7.0, 7.0, 8.0, 8.0), Vec::new())],
            ),
        ];
        let countries = BTreeMap::from([(*b"AA", "Testland".to_owned())]);
        let index = UrbanCenterIndex::from_bytes(encode(&centers, &countries).unwrap()).unwrap();
        let coordinates = [
            Coordinate::new(0.25, 0.25),
            Coordinate::new(1.0, 1.0),
            Coordinate::new(3.5, 3.5),
            Coordinate::new(-0.01, -0.01),
            Coordinate::new(5.5, 5.5),
            Coordinate::new(91.0, 0.0),
            Coordinate::new(7.5, 7.5),
        ];

        let matches = index.match_coordinates(&coordinates, "");

        assert_eq!(matches.len(), 2);
        assert_eq!(matches[0].city.name, "Donut");
        assert_eq!(matches[0].city.source_id, 7);
        assert_eq!(
            matches[0].city.country_code,
            CountryCode::from_bytes(*b"AA").unwrap()
        );
        assert_eq!(matches[0].coordinate_indices, [0, 4, 6]);
        assert_eq!(matches[1].city.name, "Neighbour");
        assert_eq!(matches[1].coordinate_indices, [2]);

        let filtered = index.match_coordinates(&coordinates, "NEIGH");
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].city.name, "Neighbour");
        assert_eq!(filtered[0].coordinate_indices, [2]);
    }

    #[test]
    fn inverse_mollweide_matches_published_apia_centroid() {
        let coordinate = mollweide_to_wgs84(-16_907_128.97, -1_704_473.775).unwrap();
        assert!((coordinate.latitude - -13.836858).abs() < 0.000001);
        assert!((coordinate.longitude - -171.790524).abs() < 0.000001);
    }

    #[test]
    fn canonical_name_city_uses_a_nearby_matching_place() {
        let cities = [city(1, 47.5, 8.5), city(2, 47.3667, 8.55)];

        assert_eq!(
            canonical_name_city(&cities, Coordinate::new(47.37, 8.54))
                .unwrap()
                .source_id,
            2
        );
        assert!(canonical_name_city(&cities, Coordinate::new(0.0, 0.0)).is_none());
    }

    #[test]
    fn decodes_geopackage_multipolygon_wkb() {
        let mut bytes = b"GP\0\x01".to_vec();
        bytes.extend_from_slice(&54_009_i32.to_le_bytes());
        bytes.push(1);
        bytes.extend_from_slice(&6_u32.to_le_bytes());
        bytes.extend_from_slice(&1_u32.to_le_bytes());
        bytes.push(1);
        bytes.extend_from_slice(&3_u32.to_le_bytes());
        bytes.extend_from_slice(&1_u32.to_le_bytes());
        bytes.extend_from_slice(&4_u32.to_le_bytes());
        for (x, y) in [(0.0_f64, 0.0_f64), (1000.0, 0.0), (0.0, 1000.0), (0.0, 0.0)] {
            bytes.extend_from_slice(&x.to_le_bytes());
            bytes.extend_from_slice(&y.to_le_bytes());
        }

        let geometry = decode_geopackage_geometry(&bytes).unwrap();

        assert_eq!(geometry.0.len(), 1);
        assert_eq!(geometry.0[0].exterior().0.len(), 4);
        assert!(geometry.0[0].exterior().0[1].x > 0.0);
        assert!(geometry.0[0].exterior().0[2].y > 0.0);
    }

    fn center(source_id: u32, name: &str, polygons: Vec<Polygon<f64>>) -> SourceCenter {
        SourceCenter {
            source_id,
            name: name.to_owned(),
            country_code: *b"AA",
            centroid: Coordinate::new(0.25, 0.25),
            geometry: MultiPolygon::new(polygons),
        }
    }

    fn city(source_id: u32, latitude: f64, longitude: f64) -> City {
        City {
            point_index: source_id,
            source_id,
            name: "Example".to_owned(),
            country_name: "Testland".to_owned(),
            country_code: CountryCode::from_bytes(*b"AA").unwrap(),
            latitude,
            longitude,
            rank: 0,
        }
    }

    fn square(minimum_x: f64, minimum_y: f64, maximum_x: f64, maximum_y: f64) -> LineString<f64> {
        LineString::from(vec![
            (minimum_x, minimum_y),
            (maximum_x, minimum_y),
            (maximum_x, maximum_y),
            (minimum_x, maximum_y),
            (minimum_x, minimum_y),
        ])
    }
}
