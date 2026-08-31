use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use unicode_normalization::UnicodeNormalization;
use unicode_normalization::char::is_combining_mark;

use crate::binary::{f32_at, range, u16_at, u24_at, u32_at};
use crate::{Coordinate, CountryCode, Error};

const MAGIC: &[u8; 4] = b"CITY";
const VERSION: u16 = 1;
const HEADER_LEN: usize = 72;
const NODE_LEN: usize = 3;
const POINT_LEN: usize = 15;
const NAME_OFFSET_LEN: usize = 3;
const MAX_U24: usize = 0x00ff_ffff;
const MAX_CATCHMENT_KM: f64 = 30.0;
const SECTION: &str = "city index";

#[derive(Clone, Debug, PartialEq)]
pub struct City {
    pub point_index: u32,
    pub source_id: u32,
    pub name: String,
    pub country_name: String,
    pub country_code: CountryCode,
    pub latitude: f64,
    pub longitude: f64,
    pub rank: u8,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CityMatch {
    pub city: City,
    pub coordinate_indices: Vec<u32>,
}

#[derive(Clone, Copy, Debug)]
struct Layout {
    point_count: usize,
    name_count: usize,
    country_count: usize,
    nodes: usize,
    points: usize,
    name_offsets: usize,
    names: usize,
    country_offsets: usize,
    countries: usize,
    country_codes: usize,
    rank_ends: [usize; 4],
}

#[derive(Clone, Copy)]
struct Point {
    latitude: f32,
    longitude: f32,
    name: usize,
    country: usize,
    source_id: u32,
}

#[derive(Clone, Copy)]
struct SearchBounds {
    minimum_latitude: f64,
    maximum_latitude: f64,
    minimum_longitude: f64,
    maximum_longitude: f64,
}

impl SearchBounds {
    const fn new(
        minimum_latitude: f64,
        maximum_latitude: f64,
        minimum_longitude: f64,
        maximum_longitude: f64,
    ) -> Self {
        Self {
            minimum_latitude,
            maximum_latitude,
            minimum_longitude,
            maximum_longitude,
        }
    }
}

struct SearchPattern {
    characters: Vec<char>,
    fallback: Vec<usize>,
}

impl SearchPattern {
    fn new(query: &str) -> Option<Self> {
        let characters: Vec<char> = search_characters(query).collect();
        if characters.is_empty() {
            return None;
        }
        let mut fallback = vec![0; characters.len()];
        let mut matched = 0;
        for index in 1..characters.len() {
            while matched > 0 && characters[index] != characters[matched] {
                matched = fallback[matched - 1];
            }
            if characters[index] == characters[matched] {
                matched += 1;
                fallback[index] = matched;
            }
        }
        Some(Self {
            characters,
            fallback,
        })
    }

    fn matches(&self, value: &str) -> bool {
        let mut matched = 0;
        for character in search_characters(value) {
            while matched > 0 && character != self.characters[matched] {
                matched = self.fallback[matched - 1];
            }
            if character == self.characters[matched] {
                matched += 1;
                if matched == self.characters.len() {
                    return true;
                }
            }
        }
        false
    }
}

fn search_characters(value: &str) -> impl Iterator<Item = char> + '_ {
    value
        .nfd()
        .filter(|&character| !is_combining_mark(character))
        .flat_map(char::to_lowercase)
}

pub struct CityIndex {
    bytes: Box<[u8]>,
    layout: Layout,
}

impl CityIndex {
    pub fn from_path(path: impl AsRef<Path>) -> crate::Result<Self> {
        Self::from_bytes(fs::read(path)?)
    }

    pub fn from_bytes(bytes: impl Into<Box<[u8]>>) -> crate::Result<Self> {
        let bytes = bytes.into();
        let layout = validate(&bytes)?;
        Ok(Self { bytes, layout })
    }

    pub const fn len(&self) -> usize {
        self.layout.point_count
    }

    pub const fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<City> {
        if limit == 0 {
            return Vec::new();
        }
        let matching_names = self.matching_names(query);
        if no_names_match(&matching_names) {
            return Vec::new();
        }
        let mut cities = Vec::new();
        for point_index in 0..self.layout.point_count {
            let point = self.point(point_index);
            if matching_names
                .as_ref()
                .is_none_or(|matches| matches[point.name])
            {
                cities.push(self.city(point_index));
                if cities.len() == limit {
                    break;
                }
            }
        }
        cities
    }

    pub fn match_coordinates(&self, coordinates: &[Coordinate], query: &str) -> Vec<CityMatch> {
        if coordinates.is_empty() {
            return Vec::new();
        }
        let matching_names = self.matching_names(query);
        if no_names_match(&matching_names) {
            return Vec::new();
        }
        let mut matches = BTreeMap::<usize, Vec<u32>>::new();
        let mut candidates = Vec::new();
        let mut eligible = Vec::new();
        let mut stack = Vec::new();

        for (coordinate_index, &coordinate) in coordinates.iter().enumerate() {
            if !coordinate.is_valid() {
                continue;
            }
            self.range_around(coordinate, MAX_CATCHMENT_KM, &mut candidates, &mut stack);
            eligible.clear();
            for &point_index in &candidates {
                let point = self.point(point_index);
                if matching_names
                    .as_ref()
                    .is_some_and(|matches| !matches[point.name])
                {
                    continue;
                }
                let distance_km = distance_km(
                    coordinate.latitude,
                    coordinate.longitude,
                    f64::from(point.latitude),
                    f64::from(point.longitude),
                );
                let rank = self.rank(point_index);
                if distance_km <= catchment_km(rank) {
                    eligible.push(Candidate {
                        point: point_index,
                        distance_km,
                        rank,
                        source_id: point.source_id,
                    });
                }
            }

            let Some(nearest) = eligible
                .iter()
                .map(|candidate| candidate.distance_km)
                .reduce(f64::min)
            else {
                continue;
            };
            let prominence_window = (0.5 + nearest * 0.25).min(2.0);
            let best = eligible
                .iter()
                .filter(|candidate| candidate.distance_km <= nearest + prominence_window)
                .min_by(compare_candidates)
                .expect("eligible candidates are nonempty");
            matches
                .entry(best.point)
                .or_default()
                .push(coordinate_index as u32);
        }

        matches
            .into_iter()
            .map(|(point, coordinate_indices)| CityMatch {
                city: self.city(point),
                coordinate_indices,
            })
            .collect()
    }

    fn matching_names(&self, query: &str) -> Option<Vec<bool>> {
        let pattern = SearchPattern::new(query)?;
        Some(
            (0..self.layout.name_count)
                .map(|index| {
                    let (name, alias) = self.name_parts(index);
                    pattern.matches(name) || alias.is_some_and(|alias| pattern.matches(alias))
                })
                .collect(),
        )
    }

    fn range_around(
        &self,
        coordinate: Coordinate,
        maximum_distance_km: f64,
        result: &mut Vec<usize>,
        stack: &mut Vec<(usize, usize, u8)>,
    ) {
        result.clear();
        let latitude_delta = maximum_distance_km / 110.574;
        let longitude_scale = coordinate.latitude.to_radians().cos().abs().max(0.01);
        let longitude_delta = (maximum_distance_km / (111.320 * longitude_scale)).min(180.0);
        let minimum_latitude = (coordinate.latitude - latitude_delta).max(-90.0);
        let maximum_latitude = (coordinate.latitude + latitude_delta).min(90.0);
        if longitude_delta >= 180.0 {
            self.range_into(
                SearchBounds::new(minimum_latitude, maximum_latitude, -180.0, 180.0),
                result,
                stack,
            );
            return;
        }

        let minimum_longitude = coordinate.longitude - longitude_delta;
        let maximum_longitude = coordinate.longitude + longitude_delta;
        if minimum_longitude < -180.0 {
            self.range_into(
                SearchBounds::new(
                    minimum_latitude,
                    maximum_latitude,
                    minimum_longitude + 360.0,
                    180.0,
                ),
                result,
                stack,
            );
            self.range_into(
                SearchBounds::new(
                    minimum_latitude,
                    maximum_latitude,
                    -180.0,
                    maximum_longitude,
                ),
                result,
                stack,
            );
        } else if maximum_longitude > 180.0 {
            self.range_into(
                SearchBounds::new(minimum_latitude, maximum_latitude, minimum_longitude, 180.0),
                result,
                stack,
            );
            self.range_into(
                SearchBounds::new(
                    minimum_latitude,
                    maximum_latitude,
                    -180.0,
                    maximum_longitude - 360.0,
                ),
                result,
                stack,
            );
        } else {
            self.range_into(
                SearchBounds::new(
                    minimum_latitude,
                    maximum_latitude,
                    minimum_longitude,
                    maximum_longitude,
                ),
                result,
                stack,
            );
        }
    }

    fn range_into(
        &self,
        bounds: SearchBounds,
        result: &mut Vec<usize>,
        stack: &mut Vec<(usize, usize, u8)>,
    ) {
        if self.layout.point_count == 0 {
            return;
        }
        stack.clear();
        stack.push((0, self.layout.point_count, 0));
        while let Some((node_index, subtree_size, axis)) = stack.pop() {
            let point_index = self.node(node_index);
            let point = self.point(point_index);
            let latitude = f64::from(point.latitude);
            let longitude = f64::from(point.longitude);
            if (bounds.minimum_latitude..=bounds.maximum_latitude).contains(&latitude)
                && (bounds.minimum_longitude..=bounds.maximum_longitude).contains(&longitude)
            {
                result.push(point_index);
            }

            let left_size = subtree_size / 2;
            let right_size = subtree_size - left_size - 1;
            let next_axis = axis ^ 1;
            if axis == 0 {
                if bounds.minimum_latitude <= latitude && left_size > 0 {
                    stack.push((node_index + 1, left_size, next_axis));
                }
                if bounds.maximum_latitude >= latitude && right_size > 0 {
                    stack.push((node_index + left_size + 1, right_size, next_axis));
                }
            } else {
                if bounds.minimum_longitude <= longitude && left_size > 0 {
                    stack.push((node_index + 1, left_size, next_axis));
                }
                if bounds.maximum_longitude >= longitude && right_size > 0 {
                    stack.push((node_index + left_size + 1, right_size, next_axis));
                }
            }
        }
    }

    fn city(&self, point_index: usize) -> City {
        let point = self.point(point_index);
        City {
            point_index: point_index as u32,
            source_id: point.source_id,
            name: self.name(point.name).to_owned(),
            country_name: self.country(point.country).to_owned(),
            country_code: self.country_code(point.country),
            latitude: f64::from(point.latitude),
            longitude: f64::from(point.longitude),
            rank: self.rank(point_index),
        }
    }

    fn node(&self, index: usize) -> usize {
        u24_at(&self.bytes, self.layout.nodes + index * NODE_LEN).expect("validated node") as usize
    }

    fn point(&self, index: usize) -> Point {
        let offset = self.layout.points + index * POINT_LEN;
        Point {
            latitude: f32_at(&self.bytes, offset).expect("validated point"),
            longitude: f32_at(&self.bytes, offset + 4).expect("validated point"),
            name: u24_at(&self.bytes, offset + 8).expect("validated point") as usize,
            country: usize::from(self.bytes[offset + 11]),
            source_id: u24_at(&self.bytes, offset + 12).expect("validated point"),
        }
    }

    fn rank(&self, point_index: usize) -> u8 {
        self.layout
            .rank_ends
            .iter()
            .position(|&end| point_index < end)
            .map_or(0, |index| 4 - index as u8)
    }

    fn name(&self, index: usize) -> &str {
        self.name_parts(index).0
    }

    fn name_parts(&self, index: usize) -> (&str, Option<&str>) {
        let value = table_entry_u24(
            &self.bytes,
            self.layout.name_offsets,
            self.layout.names,
            index,
        );
        value
            .split_once('\0')
            .map_or((value, None), |(name, alias)| (name, Some(alias)))
    }

    fn country(&self, index: usize) -> &str {
        table_entry_u32(
            &self.bytes,
            self.layout.country_offsets,
            self.layout.countries,
            index,
        )
    }

    fn country_code(&self, index: usize) -> CountryCode {
        let offset = self.layout.country_codes + index * 2;
        CountryCode::from_validated([self.bytes[offset], self.bytes[offset + 1]])
    }
}

#[derive(Clone, Copy)]
struct Candidate {
    point: usize,
    distance_km: f64,
    rank: u8,
    source_id: u32,
}

fn no_names_match(matching_names: &Option<Vec<bool>>) -> bool {
    matching_names
        .as_ref()
        .is_some_and(|matches| !matches.iter().any(|&matched| matched))
}

fn validate(bytes: &[u8]) -> crate::Result<Layout> {
    if bytes.len() < HEADER_LEN {
        return Err(invalid("truncated"));
    }
    if &bytes[..4] != MAGIC {
        return Err(invalid("invalid magic"));
    }
    let version = read_u16(bytes, 4)?;
    if version != VERSION {
        return Err(Error::invalid(
            SECTION,
            format!("unsupported format version {version}"),
        ));
    }
    if usize::from(read_u16(bytes, 6)?) != HEADER_LEN {
        return Err(invalid("unexpected header length"));
    }
    if usize::from(read_u16(bytes, 18)?) != POINT_LEN
        || usize::from(read_u16(bytes, 20)?) != NODE_LEN
        || usize::from(read_u16(bytes, 22)?) != NAME_OFFSET_LEN
    {
        return Err(invalid("unexpected record length"));
    }

    let layout = Layout {
        point_count: read_usize(bytes, 8)?,
        name_count: read_usize(bytes, 12)?,
        country_count: usize::from(read_u16(bytes, 16)?),
        nodes: read_usize(bytes, 24)?,
        points: read_usize(bytes, 28)?,
        name_offsets: read_usize(bytes, 32)?,
        names: read_usize(bytes, 36)?,
        country_offsets: read_usize(bytes, 40)?,
        countries: read_usize(bytes, 44)?,
        country_codes: read_usize(bytes, 48)?,
        rank_ends: [
            read_usize(bytes, 56)?,
            read_usize(bytes, 60)?,
            read_usize(bytes, 64)?,
            read_usize(bytes, 68)?,
        ],
    };
    let declared_length = read_usize(bytes, 52)?;
    validate_sections(bytes, layout, declared_length)?;
    validate_strings(bytes, layout)?;
    validate_points(bytes, layout)?;
    validate_tree(bytes, layout)?;
    Ok(layout)
}

fn validate_sections(bytes: &[u8], layout: Layout, declared_length: usize) -> crate::Result<()> {
    if layout.point_count > MAX_U24
        || layout.name_count > MAX_U24
        || layout.country_count > 256
        || (layout.point_count > 0 && (layout.name_count == 0 || layout.country_count == 0))
        || layout.rank_ends[3] > layout.point_count
        || layout.rank_ends.windows(2).any(|ends| ends[0] > ends[1])
    {
        return Err(invalid("invalid section count"));
    }
    let nodes = range(layout.nodes, layout.point_count, NODE_LEN)
        .ok_or(invalid("node section overflow"))?;
    let points = range(layout.points, layout.point_count, POINT_LEN)
        .ok_or(invalid("point section overflow"))?;
    let name_offsets = offset_table_range(layout.name_offsets, layout.name_count, NAME_OFFSET_LEN)?;
    let name_bytes = terminal_offset(
        bytes,
        layout.name_offsets,
        layout.name_count,
        NAME_OFFSET_LEN,
    )?;
    let country_offsets = offset_table_range(layout.country_offsets, layout.country_count, 4)?;
    let country_bytes = terminal_offset(bytes, layout.country_offsets, layout.country_count, 4)?;
    let country_codes = range(layout.country_codes, layout.country_count, 2)
        .ok_or(invalid("country-code section overflow"))?;
    let names_end = layout
        .names
        .checked_add(name_bytes)
        .ok_or(invalid("name section overflow"))?;
    let countries_end = layout
        .countries
        .checked_add(country_bytes)
        .ok_or(invalid("country section overflow"))?;

    if layout.nodes != HEADER_LEN
        || layout.points != nodes.end
        || layout.name_offsets != points.end
        || layout.names != name_offsets.end
        || layout.country_offsets != names_end
        || layout.countries != country_offsets.end
        || layout.country_codes != countries_end
        || country_codes.end != bytes.len()
        || declared_length != bytes.len()
    {
        return Err(invalid("sections are not contiguous"));
    }
    Ok(())
}

fn validate_strings(bytes: &[u8], layout: Layout) -> crate::Result<()> {
    validate_table(
        bytes,
        layout.name_offsets,
        layout.names,
        layout.name_count,
        NAME_OFFSET_LEN,
        "name table",
    )?;
    validate_table(
        bytes,
        layout.country_offsets,
        layout.countries,
        layout.country_count,
        4,
        "country-name table",
    )?;
    for index in 0..layout.name_count {
        let value = table_entry_u24(bytes, layout.name_offsets, layout.names, index);
        if let Some((name, alias)) = value.split_once('\0')
            && (name.is_empty() || alias.is_empty() || alias.contains('\0'))
        {
            return Err(invalid("invalid city name"));
        }
    }

    let mut seen_codes = [false; 26 * 26];
    for index in 0..layout.country_count {
        let offset = layout.country_codes + index * 2;
        let code = [bytes[offset], bytes[offset + 1]];
        if !code.iter().all(u8::is_ascii_uppercase) {
            return Err(invalid("invalid country code"));
        }
        let slot = usize::from(code[0] - b'A') * 26 + usize::from(code[1] - b'A');
        if seen_codes[slot] {
            return Err(invalid("duplicate country code"));
        }
        seen_codes[slot] = true;
    }
    Ok(())
}

fn validate_points(bytes: &[u8], layout: Layout) -> crate::Result<()> {
    for index in 0..layout.point_count {
        let offset = layout.points + index * POINT_LEN;
        let latitude = f32_at(bytes, offset).ok_or(invalid("truncated"))?;
        let longitude = f32_at(bytes, offset + 4).ok_or(invalid("truncated"))?;
        let name = u24_at(bytes, offset + 8).ok_or(invalid("truncated"))? as usize;
        let country = usize::from(bytes[offset + 11]);
        if !latitude.is_finite()
            || !(-90.0..=90.0).contains(&latitude)
            || !longitude.is_finite()
            || !(-180.0..=180.0).contains(&longitude)
            || name >= layout.name_count
            || country >= layout.country_count
        {
            return Err(invalid("invalid city point"));
        }
    }
    Ok(())
}

fn validate_tree(bytes: &[u8], layout: Layout) -> crate::Result<()> {
    if layout.point_count == 0 {
        return Ok(());
    }

    let mut visited_points = vec![false; layout.point_count];
    let mut stack = vec![(0usize, layout.point_count, 0u8, -90.0, 90.0, -180.0, 180.0)];
    while let Some((node_index, size, axis, min_lat, max_lat, min_lng, max_lng)) = stack.pop() {
        if size == 0
            || node_index
                .checked_add(size)
                .is_none_or(|end| end > layout.point_count)
        {
            return Err(invalid("invalid tree layout"));
        }
        let point = u24_at(bytes, layout.nodes + node_index * NODE_LEN)
            .ok_or(invalid("truncated"))? as usize;
        if point >= layout.point_count || visited_points[point] {
            return Err(invalid("invalid tree node"));
        }
        visited_points[point] = true;
        let point_offset = layout.points + point * POINT_LEN;
        let latitude = f64::from(f32_at(bytes, point_offset).expect("validated point"));
        let longitude = f64::from(f32_at(bytes, point_offset + 4).expect("validated point"));
        if !(min_lat..=max_lat).contains(&latitude) || !(min_lng..=max_lng).contains(&longitude) {
            return Err(invalid("invalid KD ordering"));
        }

        let left_size = size / 2;
        let right_size = size - left_size - 1;
        let next_axis = axis ^ 1;
        if axis == 0 {
            if left_size > 0 {
                stack.push((
                    node_index + 1,
                    left_size,
                    next_axis,
                    min_lat,
                    latitude,
                    min_lng,
                    max_lng,
                ));
            }
            if right_size > 0 {
                stack.push((
                    node_index + left_size + 1,
                    right_size,
                    next_axis,
                    latitude,
                    max_lat,
                    min_lng,
                    max_lng,
                ));
            }
        } else {
            if left_size > 0 {
                stack.push((
                    node_index + 1,
                    left_size,
                    next_axis,
                    min_lat,
                    max_lat,
                    min_lng,
                    longitude,
                ));
            }
            if right_size > 0 {
                stack.push((
                    node_index + left_size + 1,
                    right_size,
                    next_axis,
                    min_lat,
                    max_lat,
                    longitude,
                    max_lng,
                ));
            }
        }
    }
    if visited_points.iter().any(|&visited| !visited) {
        return Err(invalid("tree does not cover every point"));
    }
    Ok(())
}

fn validate_table(
    bytes: &[u8],
    offsets: usize,
    blob: usize,
    count: usize,
    offset_len: usize,
    name: &'static str,
) -> crate::Result<()> {
    let blob_length = terminal_offset(bytes, offsets, count, offset_len)?;
    let mut previous = 0;
    for index in 0..count {
        let start = string_offset(bytes, offsets + index * offset_len, offset_len)?;
        let end = string_offset(bytes, offsets + (index + 1) * offset_len, offset_len)?;
        if start != previous || end <= start || end > blob_length {
            return Err(invalid("invalid string offsets"));
        }
        std::str::from_utf8(&bytes[blob + start..blob + end])
            .map_err(|_| Error::invalid(SECTION, format!("invalid UTF-8 in {name}")))?;
        previous = end;
    }
    Ok(())
}

fn offset_table_range(
    offset: usize,
    count: usize,
    stride: usize,
) -> crate::Result<std::ops::Range<usize>> {
    range(
        offset,
        count
            .checked_add(1)
            .ok_or(invalid("offset count overflow"))?,
        stride,
    )
    .ok_or(invalid("offset table overflow"))
}

fn terminal_offset(
    bytes: &[u8],
    offset: usize,
    count: usize,
    stride: usize,
) -> crate::Result<usize> {
    let terminal = offset
        .checked_add(
            count
                .checked_mul(stride)
                .ok_or(invalid("offset table overflow"))?,
        )
        .ok_or(invalid("offset table overflow"))?;
    string_offset(bytes, terminal, stride)
}

fn string_offset(bytes: &[u8], offset: usize, length: usize) -> crate::Result<usize> {
    match length {
        NAME_OFFSET_LEN => Ok(u24_at(bytes, offset).ok_or(invalid("truncated"))? as usize),
        4 => Ok(u32_at(bytes, offset).ok_or(invalid("truncated"))? as usize),
        _ => unreachable!("validated offset length"),
    }
}

fn table_entry_u24(bytes: &[u8], offsets: usize, blob: usize, index: usize) -> &str {
    let start =
        u24_at(bytes, offsets + index * NAME_OFFSET_LEN).expect("validated string table") as usize;
    let end = u24_at(bytes, offsets + (index + 1) * NAME_OFFSET_LEN)
        .expect("validated string table") as usize;
    std::str::from_utf8(&bytes[blob + start..blob + end]).expect("validated UTF-8")
}

fn table_entry_u32(bytes: &[u8], offsets: usize, blob: usize, index: usize) -> &str {
    let start = u32_at(bytes, offsets + index * 4).expect("validated string table") as usize;
    let end = u32_at(bytes, offsets + (index + 1) * 4).expect("validated string table") as usize;
    std::str::from_utf8(&bytes[blob + start..blob + end]).expect("validated UTF-8")
}

fn read_u16(bytes: &[u8], offset: usize) -> crate::Result<u16> {
    u16_at(bytes, offset).ok_or(invalid("truncated"))
}

fn read_usize(bytes: &[u8], offset: usize) -> crate::Result<usize> {
    Ok(u32_at(bytes, offset).ok_or(invalid("truncated"))? as usize)
}

fn invalid(reason: &'static str) -> Error {
    Error::invalid(SECTION, reason)
}

fn compare_candidates(left: &&Candidate, right: &&Candidate) -> Ordering {
    right
        .rank
        .cmp(&left.rank)
        .then_with(|| left.distance_km.total_cmp(&right.distance_km))
        .then_with(|| left.source_id.cmp(&right.source_id))
}

fn catchment_km(rank: u8) -> f64 {
    [8.0, 10.0, 14.0, 20.0, 30.0][usize::from(rank)]
}

fn distance_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let lat1 = lat1.to_radians();
    let lat2 = lat2.to_radians();
    let delta_latitude = lat2 - lat1;
    let delta_longitude = (lng2 - lng1).to_radians();
    let a = (delta_latitude / 2.0).sin().powi(2)
        + lat1.cos() * lat2.cos() * (delta_longitude / 2.0).sin().powi(2);
    6371.0 * 2.0 * a.sqrt().atan2((1.0 - a).sqrt())
}
