use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::binary::{ByteReader, f32_at, range, u16_at, u32_at};
use crate::city::SearchPattern;
use crate::geometry::{Point, Reader as GeometryReader};
use crate::{City, CityMatch, Coordinate, CountryCode, Error};

const MAGIC: &[u8; 4] = b"URBN";
const VERSION: u16 = 1;
const HEADER_LEN: usize = 72;
const RECORD_LEN: usize = 41;
const BLOCK_SIZE: usize = 64;
const BLOCK_LEN: usize = 12;
const SECTION: &str = "urban center index";

#[derive(Clone, Copy)]
struct Layout {
    feature_count: usize,
    country_count: usize,
    columns: usize,
    rows: usize,
    block_count: usize,
    nonempty_count: usize,
    reference_count: usize,
    records: usize,
    names: usize,
    geometry: usize,
    country_offsets: usize,
    countries: usize,
    country_codes: usize,
    blocks: usize,
    cell_offsets: usize,
    references: usize,
}

#[derive(Clone, Copy)]
struct Feature {
    minimum_longitude: f32,
    minimum_latitude: f32,
    maximum_longitude: f32,
    maximum_latitude: f32,
    latitude: f32,
    longitude: f32,
    name: usize,
    geometry_start: usize,
    geometry_end: usize,
    source_id: u32,
    country: usize,
}

pub struct UrbanCenterIndex {
    bytes: Box<[u8]>,
    layout: Layout,
}

impl UrbanCenterIndex {
    pub fn from_path(path: impl AsRef<Path>) -> crate::Result<Self> {
        Self::from_bytes(fs::read(path)?)
    }

    pub fn from_bytes(bytes: impl Into<Box<[u8]>>) -> crate::Result<Self> {
        let bytes = bytes.into();
        let layout = validate(&bytes)?;
        Ok(Self { bytes, layout })
    }

    pub const fn len(&self) -> usize {
        self.layout.feature_count
    }

    pub const fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn match_coordinates(&self, coordinates: &[Coordinate], query: &str) -> Vec<CityMatch> {
        let matching: Option<Vec<bool>> = SearchPattern::new(query).map(|pattern| {
            (0..self.layout.feature_count)
                .map(|feature| pattern.matches(self.name(self.feature(feature).name)))
                .collect()
        });
        if matching
            .as_ref()
            .is_some_and(|matching| !matching.iter().any(|&matched| matched))
        {
            return Vec::new();
        }
        let mut matches = BTreeMap::<usize, Vec<u32>>::new();
        for (coordinate_index, &coordinate) in coordinates.iter().enumerate() {
            if let Some(feature) = self.lookup(coordinate, matching.as_deref()) {
                matches
                    .entry(feature)
                    .or_default()
                    .push(coordinate_index as u32);
            }
        }
        let mut groups = BTreeMap::<u32, CityMatch>::new();
        for (feature, coordinate_indices) in matches {
            let city = self.city(feature);
            groups
                .entry(city.source_id)
                .and_modify(|group| {
                    group
                        .coordinate_indices
                        .extend_from_slice(&coordinate_indices);
                    group.coordinate_indices.sort_unstable();
                })
                .or_insert(CityMatch {
                    city,
                    coordinate_indices,
                });
        }
        groups.into_values().collect()
    }

    fn lookup(&self, coordinate: Coordinate, matching: Option<&[bool]>) -> Option<usize> {
        if !coordinate.is_valid() {
            return None;
        }
        let column = (((coordinate.longitude + 180.0) * self.layout.columns as f64 / 360.0).floor()
            as usize)
            .min(self.layout.columns - 1);
        let row = ((self.layout.rows as f64 * (90.0 - coordinate.latitude) / 180.0).ceil()
            as usize)
            .saturating_sub(1);
        let dense = self.dense_cell_index(row * self.layout.columns + column)?;
        let start = self.cell_offset(dense);
        let end = self.cell_offset(dense + 1);
        for reference in start..end {
            let feature = usize::from(
                ByteReader::at(&self.bytes, self.layout.references + reference * 2).u16(),
            );
            if matching.is_some_and(|matching| !matching[feature]) {
                continue;
            }
            if self.contains(feature, coordinate) {
                return Some(feature);
            }
        }
        None
    }

    fn contains(&self, index: usize, coordinate: Coordinate) -> bool {
        let feature = self.feature(index);
        let longitude = coordinate.longitude as f32;
        let latitude = coordinate.latitude as f32;
        if longitude < feature.minimum_longitude
            || longitude > feature.maximum_longitude
            || latitude < feature.minimum_latitude
            || latitude > feature.maximum_latitude
        {
            return false;
        }
        let point = Point {
            x: quantize(
                coordinate.longitude,
                f64::from(feature.minimum_longitude),
                f64::from(feature.maximum_longitude),
            ),
            y: quantize(
                coordinate.latitude,
                f64::from(feature.minimum_latitude),
                f64::from(feature.maximum_latitude),
            ),
        };
        let mut reader = GeometryReader::new(
            &self.bytes[feature.geometry_start..feature.geometry_end],
            SECTION,
        );
        #[expect(
            clippy::expect_used,
            reason = "Index construction validates all polygon and ring records"
        )]
        for _ in 0..reader.u16().expect("validated polygon count") {
            let ring_count = reader.u16().expect("validated ring count");
            let mut inside = reader.ring_contains(point).expect("validated ring");
            for _ in 1..ring_count {
                if reader.ring_contains(point).expect("validated ring") {
                    inside = false;
                }
            }
            if inside {
                return true;
            }
        }
        false
    }

    fn city(&self, index: usize) -> City {
        let feature = self.feature(index);
        City {
            point_index: index as u32,
            source_id: feature.source_id,
            name: self.name(feature.name).to_owned(),
            country_name: self.country(feature.country).to_owned(),
            country_code: self.country_code(feature.country),
            latitude: f64::from(feature.latitude),
            longitude: f64::from(feature.longitude),
            rank: 4,
        }
    }

    fn feature(&self, index: usize) -> Feature {
        let mut reader = ByteReader::at(&self.bytes, self.layout.records + index * RECORD_LEN);
        Feature {
            minimum_longitude: reader.f32(),
            minimum_latitude: reader.f32(),
            maximum_longitude: reader.f32(),
            maximum_latitude: reader.f32(),
            latitude: reader.f32(),
            longitude: reader.f32(),
            name: reader.u32() as usize,
            geometry_start: reader.u32() as usize,
            geometry_end: reader.u32() as usize,
            source_id: reader.u32(),
            country: usize::from(reader.byte()),
        }
    }

    fn name(&self, offset: usize) -> &str {
        #[expect(
            clippy::expect_used,
            reason = "Index construction validates name terminators"
        )]
        let end = self.bytes[offset..self.layout.geometry]
            .iter()
            .position(|&byte| byte == 0)
            .map(|length| offset + length)
            .expect("validated name terminator");
        #[expect(
            clippy::expect_used,
            reason = "Index construction validates names as UTF-8"
        )]
        std::str::from_utf8(&self.bytes[offset..end]).expect("validated name")
    }

    fn country(&self, index: usize) -> &str {
        let mut reader = ByteReader::at(&self.bytes, self.layout.country_offsets + index * 4);
        let start = reader.u32() as usize;
        let end = reader.u32() as usize;
        #[expect(
            clippy::expect_used,
            reason = "Index construction validates the country string table as UTF-8"
        )]
        std::str::from_utf8(&self.bytes[self.layout.countries + start..self.layout.countries + end])
            .expect("validated country")
    }

    fn country_code(&self, index: usize) -> CountryCode {
        let offset = self.layout.country_codes + index * 2;
        CountryCode::from_validated([self.bytes[offset], self.bytes[offset + 1]])
    }

    fn dense_cell_index(&self, cell_index: usize) -> Option<usize> {
        let block_index = cell_index / BLOCK_SIZE;
        let bit_index = cell_index % BLOCK_SIZE;
        let mut reader = ByteReader::at(&self.bytes, self.layout.blocks + block_index * BLOCK_LEN);
        let mask = reader.u64();
        let bit = 1_u64 << bit_index;
        (mask & bit != 0).then(|| {
            let first = reader.u32() as usize;
            first + (mask & bit.wrapping_sub(1)).count_ones() as usize
        })
    }

    fn cell_offset(&self, dense_index: usize) -> usize {
        ByteReader::at(&self.bytes, self.layout.cell_offsets + dense_index * 4).u32() as usize
    }
}

fn validate(bytes: &[u8]) -> crate::Result<Layout> {
    if bytes.len() < HEADER_LEN || &bytes[..4] != MAGIC {
        return Err(invalid("truncated or invalid magic"));
    }
    let version = u16_at(bytes, 4).ok_or(invalid("truncated"))?;
    if version != VERSION {
        return Err(Error::invalid(
            SECTION,
            format!("unsupported format version {version}"),
        ));
    }
    if usize::from(u16_at(bytes, 6).ok_or(invalid("truncated"))?) != HEADER_LEN
        || usize::from(u16_at(bytes, 18).ok_or(invalid("truncated"))?) != BLOCK_SIZE
    {
        return Err(invalid("unexpected header or block length"));
    }
    let layout = Layout {
        feature_count: read_usize(bytes, 8)?,
        country_count: usize::from(u16_at(bytes, 12).ok_or(invalid("truncated"))?),
        columns: usize::from(u16_at(bytes, 14).ok_or(invalid("truncated"))?),
        rows: usize::from(u16_at(bytes, 16).ok_or(invalid("truncated"))?),
        block_count: read_usize(bytes, 20)?,
        nonempty_count: read_usize(bytes, 24)?,
        records: read_usize(bytes, 28)?,
        names: read_usize(bytes, 32)?,
        geometry: read_usize(bytes, 36)?,
        country_offsets: read_usize(bytes, 40)?,
        countries: read_usize(bytes, 44)?,
        country_codes: read_usize(bytes, 48)?,
        blocks: read_usize(bytes, 52)?,
        cell_offsets: read_usize(bytes, 56)?,
        references: read_usize(bytes, 60)?,
        reference_count: read_usize(bytes, 68)?,
    };
    let declared_length = read_usize(bytes, 64)?;
    validate_layout(bytes, layout, declared_length)?;
    Ok(layout)
}

fn validate_layout(bytes: &[u8], layout: Layout, declared_length: usize) -> crate::Result<()> {
    let cell_count = layout
        .columns
        .checked_mul(layout.rows)
        .ok_or(invalid("cell count overflow"))?;
    if layout.feature_count == 0
        || layout.feature_count > usize::from(u16::MAX)
        || layout.country_count == 0
        || layout.country_count > 256
        || layout.columns == 0
        || layout.rows == 0
        || layout.block_count != cell_count.div_ceil(BLOCK_SIZE)
        || layout.nonempty_count > cell_count
    {
        return Err(invalid("invalid index counts"));
    }
    let records = range(layout.records, layout.feature_count, RECORD_LEN)
        .ok_or(invalid("record section overflow"))?;
    let country_offsets = range(layout.country_offsets, layout.country_count + 1, 4)
        .ok_or(invalid("country offset section overflow"))?;
    let country_codes = range(layout.country_codes, layout.country_count, 2)
        .ok_or(invalid("country code section overflow"))?;
    let blocks = range(layout.blocks, layout.block_count, BLOCK_LEN)
        .ok_or(invalid("block section overflow"))?;
    let cell_offsets = range(layout.cell_offsets, layout.nonempty_count + 1, 4)
        .ok_or(invalid("cell offset section overflow"))?;
    let references = range(layout.references, layout.reference_count, 2)
        .ok_or(invalid("reference section overflow"))?;
    if layout.records != HEADER_LEN
        || layout.names != records.end
        || layout.names > layout.geometry
        || layout.geometry > layout.country_offsets
        || layout.countries != country_offsets.end
        || layout.countries > layout.country_codes
        || layout.blocks != country_codes.end
        || layout.cell_offsets != blocks.end
        || layout.references != cell_offsets.end
        || references.end != bytes.len()
        || declared_length != bytes.len()
    {
        return Err(invalid("sections are not contiguous"));
    }
    validate_countries(bytes, layout)?;
    validate_features(bytes, layout)?;
    validate_grid(bytes, layout, cell_count)?;
    Ok(())
}

fn validate_countries(bytes: &[u8], layout: Layout) -> crate::Result<()> {
    let country_bytes = layout.country_codes - layout.countries;
    let mut previous = 0;
    let mut seen_codes = [false; 26 * 26];
    for index in 0..layout.country_count {
        let offset = u32_at(bytes, layout.country_offsets + index * 4)
            .ok_or(invalid("truncated country offset"))? as usize;
        let end = u32_at(bytes, layout.country_offsets + (index + 1) * 4)
            .ok_or(invalid("truncated country offset"))? as usize;
        if offset != previous || end < offset || end > country_bytes {
            return Err(invalid("invalid country offsets"));
        }
        std::str::from_utf8(&bytes[layout.countries + offset..layout.countries + end])
            .map_err(|_| invalid("country name is not UTF-8"))?;
        previous = end;

        let code_offset = layout.country_codes + index * 2;
        let code = [bytes[code_offset], bytes[code_offset + 1]];
        if !code.iter().all(u8::is_ascii_uppercase) {
            return Err(invalid("invalid country code"));
        }
        let slot = usize::from(code[0] - b'A') * 26 + usize::from(code[1] - b'A');
        if seen_codes[slot] {
            return Err(invalid("duplicate country code"));
        }
        seen_codes[slot] = true;
    }
    if previous != country_bytes {
        return Err(invalid("last country offset is not terminal"));
    }
    Ok(())
}

fn validate_features(bytes: &[u8], layout: Layout) -> crate::Result<()> {
    for index in 0..layout.feature_count {
        let offset = layout.records + index * RECORD_LEN;
        let values = [
            f32_at(bytes, offset).ok_or(invalid("truncated feature"))?,
            f32_at(bytes, offset + 4).ok_or(invalid("truncated feature"))?,
            f32_at(bytes, offset + 8).ok_or(invalid("truncated feature"))?,
            f32_at(bytes, offset + 12).ok_or(invalid("truncated feature"))?,
            f32_at(bytes, offset + 16).ok_or(invalid("truncated feature"))?,
            f32_at(bytes, offset + 20).ok_or(invalid("truncated feature"))?,
        ];
        if values.iter().any(|value| !value.is_finite())
            || !(-180.0..=180.0).contains(&values[0])
            || !(-90.0..=90.0).contains(&values[1])
            || !(-180.0..=180.0).contains(&values[2])
            || !(-90.0..=90.0).contains(&values[3])
            || values[0] >= values[2]
            || values[1] >= values[3]
            || !(-90.0..=90.0).contains(&values[4])
            || !(-180.0..=180.0).contains(&values[5])
        {
            return Err(invalid("feature has invalid coordinates"));
        }
        let name = u32_at(bytes, offset + 24).ok_or(invalid("truncated feature"))? as usize;
        if !(layout.names..layout.geometry).contains(&name) {
            return Err(invalid("feature name is outside the name section"));
        }
        let end = bytes[name..layout.geometry]
            .iter()
            .position(|&byte| byte == 0)
            .ok_or(invalid("unterminated feature name"))?;
        std::str::from_utf8(&bytes[name..name + end])
            .map_err(|_| invalid("feature name is not UTF-8"))?;
        let geometry_start =
            u32_at(bytes, offset + 28).ok_or(invalid("truncated feature"))? as usize;
        let geometry_end = u32_at(bytes, offset + 32).ok_or(invalid("truncated feature"))? as usize;
        if geometry_start < layout.geometry
            || geometry_end <= geometry_start
            || geometry_end > layout.country_offsets
        {
            return Err(invalid("feature geometry is outside the geometry section"));
        }
        validate_geometry(&bytes[geometry_start..geometry_end])?;
        let country = usize::from(bytes[offset + 40]);
        if country >= layout.country_count {
            return Err(invalid("feature references unknown country"));
        }
    }
    Ok(())
}

fn validate_geometry(bytes: &[u8]) -> crate::Result<()> {
    let mut reader = GeometryReader::new(bytes, SECTION);
    let polygon_count = reader.u16()?;
    if polygon_count == 0 {
        return Err(invalid("feature geometry has no polygons"));
    }
    for _ in 0..polygon_count {
        let ring_count = reader.u16()?;
        if ring_count == 0 {
            return Err(invalid("feature polygon has no rings"));
        }
        for _ in 0..ring_count {
            let point_count = usize::from(reader.u16()?);
            if point_count < 4 {
                return Err(invalid("feature ring is too short"));
            }
            reader.take(
                point_count
                    .checked_mul(4)
                    .ok_or(invalid("ring size overflow"))?,
            )?;
        }
    }
    if !reader.is_done() {
        return Err(invalid("feature geometry has trailing bytes"));
    }
    Ok(())
}

fn validate_grid(bytes: &[u8], layout: Layout, cell_count: usize) -> crate::Result<()> {
    let mut expected_dense = 0;
    let mut reader = ByteReader::at(bytes, layout.blocks);
    for block in 0..layout.block_count {
        let mask = reader.u64();
        let first = reader.u32() as usize;
        if first != expected_dense {
            return Err(invalid("invalid block dense offset"));
        }
        if block + 1 == layout.block_count {
            let used_bits = cell_count - block * BLOCK_SIZE;
            if used_bits < BLOCK_SIZE && mask >> used_bits != 0 {
                return Err(invalid("last block references nonexistent cells"));
            }
        }
        expected_dense += mask.count_ones() as usize;
    }
    if expected_dense != layout.nonempty_count {
        return Err(invalid("wrong nonempty cell count"));
    }
    let mut previous = 0;
    let mut reader = ByteReader::at(bytes, layout.cell_offsets);
    for _ in 0..=layout.nonempty_count {
        let offset = reader.u32() as usize;
        if offset < previous || offset > layout.reference_count {
            return Err(invalid("invalid cell offset"));
        }
        previous = offset;
    }
    if previous != layout.reference_count {
        return Err(invalid("last cell offset is not terminal"));
    }
    let mut reader = ByteReader::at(bytes, layout.references);
    for _ in 0..layout.reference_count {
        let feature = usize::from(reader.u16());
        if feature >= layout.feature_count {
            return Err(invalid("cell references unknown feature"));
        }
    }
    Ok(())
}

fn quantize(value: f64, minimum: f64, maximum: f64) -> u16 {
    (((value - minimum) * f64::from(u16::MAX) / (maximum - minimum))
        .clamp(0.0, f64::from(u16::MAX))) as u16
}

fn read_usize(bytes: &[u8], offset: usize) -> crate::Result<usize> {
    Ok(u32_at(bytes, offset).ok_or(invalid("truncated"))? as usize)
}

fn invalid(reason: &'static str) -> Error {
    Error::invalid(SECTION, reason)
}
