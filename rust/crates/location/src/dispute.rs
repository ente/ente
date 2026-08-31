use std::str;

use crate::binary::{range, u16_at, u32_at};
use crate::country::{CountryGeometry, PreparedCell};
use crate::{CountryCode, Error};

const MAGIC: &[u8; 4] = b"DSPT";
const VERSION: u16 = 1;
const HEADER_LEN: usize = 64;
const TERRITORY_LEN: usize = 12;
const MISSING_COUNTRY: u8 = u8::MAX;
const SECTION: &str = "dispute index";

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct TerritoryId(u16);

impl TerritoryId {
    pub const ARUNACHAL_PRADESH: Self = Self(1);
    pub const TIRPANI_VALLEYS: Self = Self(2);
    pub const BARA_HOTII_VALLEYS: Self = Self(3);
    pub const DEMCHOK: Self = Self(4);
    pub const SAMDU_VALLEYS: Self = Self(5);
    pub const KASHMIR: Self = Self(6);
    pub const TRANS_KARAKORAM_TRACT: Self = Self(7);
    pub const AKSAI_CHIN: Self = Self(8);
    pub const GILGIT_BALTISTAN: Self = Self(9);
    pub const AZAD_KASHMIR: Self = Self(10);
    pub const SIACHEN_GLACIER: Self = Self(11);
    pub const GAZA_STRIP: Self = Self(12);
    pub const WEST_BANK: Self = Self(13);
    pub const GOLAN_HEIGHTS: Self = Self(14);
    pub const SHEBAA_FARMS: Self = Self(15);
    pub const EAST_JERUSALEM: Self = Self(16);
    pub const LATRUN_FORT: Self = Self(17);
    pub const JERUSALEM_NO_MANS_LAND: Self = Self(18);
    pub const MOUNT_SCOPUS: Self = Self(19);
    pub const TAIWAN: Self = Self(20);
    pub const CRIMEA: Self = Self(21);
    pub const DONETSK_REGION: Self = Self(22);
    pub const LUHANSK_REGION: Self = Self(23);
    pub const KHERSON_REGION: Self = Self(24);
    pub const ZAPORIZHZHIA_REGION: Self = Self(25);
    pub const KOSOVO: Self = Self(26);
    pub const WESTERN_SAHARA_MOROCCAN_AREA: Self = Self(27);
    pub const WESTERN_SAHARA_SELF_ADMINISTERED_AREA: Self = Self(28);
    pub const NORTHERN_CYPRUS: Self = Self(29);
    pub const CYPRUS_BUFFER_ZONE: Self = Self(30);
    pub const FALKLAND_ISLANDS: Self = Self(31);

    pub const fn get(self) -> u16 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CountryView {
    Neutral,
    SourceDefault,
    Region(CountryCode),
}

#[derive(Clone, Copy, Debug)]
struct Layout {
    worldview_count: usize,
    territory_count: usize,
    country_count: usize,
    countries: usize,
    worldviews: usize,
    territories: usize,
    candidates: usize,
    assignments: usize,
    strings: usize,
    geometry: usize,
}

#[derive(Debug)]
pub(crate) struct DisputeIndex {
    bytes: Box<[u8]>,
    layout: Layout,
    geometry: CountryGeometry,
}

impl DisputeIndex {
    pub(crate) fn from_bytes(bytes: impl Into<Box<[u8]>>) -> crate::Result<Self> {
        let bytes = bytes.into();
        let layout = validate(&bytes)?;
        let geometry = CountryGeometry::from_bytes(bytes[layout.geometry..].to_vec())?;
        validate_geometry(&geometry, &bytes, layout)?;
        Ok(Self {
            bytes,
            layout,
            geometry,
        })
    }

    pub(crate) fn lookup_prepared(
        &self,
        location: PreparedCell,
    ) -> crate::Result<Vec<DisputeMatch<'_>>> {
        Ok(self
            .geometry
            .lookup_prepared(location)?
            .into_iter()
            .map(|code| DisputeMatch {
                index: self,
                territory: territory_index_for_code(&self.bytes, self.layout, code)
                    .expect("geometry was validated against the catalog"),
            })
            .collect())
    }

    fn country_code(&self, index: u8) -> CountryCode {
        country_code(&self.bytes, self.layout, index)
    }

    fn worldview_index(&self, code: CountryCode) -> Option<usize> {
        worldview_index(&self.bytes, self.layout, code)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct DisputeMatch<'a> {
    index: &'a DisputeIndex,
    territory: usize,
}

impl<'a> DisputeMatch<'a> {
    pub fn territory_id(self) -> TerritoryId {
        TerritoryId(self.record().id)
    }

    pub fn name(self) -> &'a str {
        let record = self.record();
        self.string(record.name_start, usize::from(record.name_length))
    }

    fn source_default(self) -> Option<CountryCode> {
        decode_optional_country(
            &self.index.bytes,
            self.index.layout,
            self.record().default_country,
        )
    }

    pub fn possible_countries(self) -> impl ExactSizeIterator<Item = CountryCode> + 'a {
        let record = self.record();
        let start = self.index.layout.candidates + usize::from(record.candidate_start);
        self.index.bytes[start..start + usize::from(record.candidate_count)]
            .iter()
            .map(|&country| self.index.country_code(country))
    }

    pub fn resolve(self, view: CountryView) -> Option<CountryCode> {
        match view {
            CountryView::Neutral => None,
            CountryView::SourceDefault => self.source_default(),
            CountryView::Region(region) => {
                if let Some(worldview) = self.index.worldview_index(region) {
                    let assignment = self.index.layout.assignments
                        + self.territory * self.index.layout.worldview_count
                        + worldview;
                    decode_optional_country(
                        &self.index.bytes,
                        self.index.layout,
                        self.index.bytes[assignment],
                    )
                } else if self.possible_countries().any(|country| country == region) {
                    Some(region)
                } else {
                    self.source_default()
                }
            }
        }
    }

    fn record(self) -> TerritoryRecord {
        let offset = self.record_offset();
        TerritoryRecord {
            id: u16_at(&self.index.bytes, offset).expect("validated territory"),
            default_country: self.index.bytes[offset + 4],
            candidate_count: self.index.bytes[offset + 5],
            candidate_start: u16_at(&self.index.bytes, offset + 6).expect("validated territory"),
            name_start: u16_at(&self.index.bytes, offset + 8).expect("validated territory"),
            name_length: self.index.bytes[offset + 10],
        }
    }

    fn record_offset(self) -> usize {
        self.index.layout.territories + self.territory * TERRITORY_LEN
    }

    fn string(self, start: u16, length: usize) -> &'a str {
        let start = self.index.layout.strings + usize::from(start);
        str::from_utf8(&self.index.bytes[start..start + length]).expect("validated UTF-8")
    }
}

#[derive(Clone, Copy)]
struct TerritoryRecord {
    id: u16,
    default_country: u8,
    candidate_count: u8,
    candidate_start: u16,
    name_start: u16,
    name_length: u8,
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
    if usize::from(read_u16(bytes, 6)?) != HEADER_LEN
        || usize::from(read_u16(bytes, 14)?) != TERRITORY_LEN
    {
        return Err(invalid("unexpected header or territory length"));
    }
    if bytes[48..HEADER_LEN].iter().any(|&byte| byte != 0) {
        return Err(invalid("nonzero reserved header bytes"));
    }
    let layout = Layout {
        worldview_count: usize::from(read_u16(bytes, 8)?),
        territory_count: usize::from(read_u16(bytes, 10)?),
        country_count: usize::from(read_u16(bytes, 12)?),
        countries: read_usize(bytes, 16)?,
        worldviews: read_usize(bytes, 20)?,
        territories: read_usize(bytes, 24)?,
        candidates: read_usize(bytes, 28)?,
        assignments: read_usize(bytes, 32)?,
        strings: read_usize(bytes, 36)?,
        geometry: read_usize(bytes, 40)?,
    };
    validate_layout(bytes, layout, read_usize(bytes, 44)?)?;
    Ok(layout)
}

fn validate_layout(bytes: &[u8], layout: Layout, declared_length: usize) -> crate::Result<()> {
    if layout.worldview_count == 0
        || layout.territory_count == 0
        || layout.country_count == 0
        || layout.country_count >= usize::from(MISSING_COUNTRY)
    {
        return Err(invalid("invalid catalog counts"));
    }
    let countries = range(layout.countries, layout.country_count, 2)
        .ok_or(invalid("country table overflow"))?;
    let worldviews = range(layout.worldviews, layout.worldview_count, 1)
        .ok_or(invalid("worldview table overflow"))?;
    let territories = range(layout.territories, layout.territory_count, TERRITORY_LEN)
        .ok_or(invalid("territory table overflow"))?;
    let assignment_count = layout
        .territory_count
        .checked_mul(layout.worldview_count)
        .ok_or(invalid("assignment table overflow"))?;
    let assignments = range(layout.assignments, assignment_count, 1)
        .ok_or(invalid("assignment table overflow"))?;
    if layout.countries != HEADER_LEN
        || layout.worldviews != countries.end
        || layout.territories != worldviews.end
        || layout.candidates != territories.end
        || layout.assignments < layout.candidates
        || layout.strings != assignments.end
        || layout.geometry < layout.strings
        || layout.geometry >= bytes.len()
        || declared_length != bytes.len()
    {
        return Err(invalid("sections are not contiguous"));
    }

    let mut seen_codes = [false; 26 * 26];
    for index in 0..layout.country_count {
        let code = code_at(bytes, layout.countries + index * 2)?;
        let slot = usize::from(code[0] - b'A') * 26 + usize::from(code[1] - b'A');
        if seen_codes[slot] {
            return Err(invalid("duplicate catalog country code"));
        }
        seen_codes[slot] = true;
    }

    let mut seen_worldviews = [false; 255];
    for &country in &bytes[layout.worldviews..worldviews.end] {
        validate_country(country, layout.country_count)?;
        if seen_worldviews[usize::from(country)] {
            return Err(invalid("duplicate worldview"));
        }
        seen_worldviews[usize::from(country)] = true;
    }

    let candidate_length = layout.assignments - layout.candidates;
    let string_length = layout.geometry - layout.strings;
    let mut ids = Vec::with_capacity(layout.territory_count);
    let mut geometry_codes = Vec::with_capacity(layout.territory_count);
    for territory in 0..layout.territory_count {
        let offset = layout.territories + territory * TERRITORY_LEN;
        let id = read_u16_infallible(bytes, offset);
        if id == 0 || ids.contains(&id) {
            return Err(invalid("invalid or duplicate territory ID"));
        }
        ids.push(id);
        let geometry_code = code_at(bytes, offset + 2)?;
        if geometry_codes.contains(&geometry_code) {
            return Err(invalid("duplicate territory geometry code"));
        }
        geometry_codes.push(geometry_code);
        validate_optional_country(bytes[offset + 4], layout.country_count)?;

        let candidate_start = usize::from(read_u16_infallible(bytes, offset + 6));
        let candidate_end = candidate_start
            .checked_add(usize::from(bytes[offset + 5]))
            .ok_or(invalid("candidate range overflow"))?;
        if candidate_end > candidate_length {
            return Err(invalid("candidate range exceeds table"));
        }
        for &country in
            &bytes[layout.candidates + candidate_start..layout.candidates + candidate_end]
        {
            validate_country(country, layout.country_count)?;
        }
        for &country in &bytes[layout.assignments + territory * layout.worldview_count
            ..layout.assignments + (territory + 1) * layout.worldview_count]
        {
            validate_optional_country(country, layout.country_count)?;
        }

        let name_start = usize::from(read_u16_infallible(bytes, offset + 8));
        let name_length = usize::from(bytes[offset + 10]);
        if name_length == 0 {
            return Err(invalid("empty territory name"));
        }
        validate_string(
            bytes,
            layout.strings,
            string_length,
            name_start,
            name_length,
        )?;
        if bytes[offset + 11] != 0 {
            return Err(invalid("nonzero reserved territory byte"));
        }
    }
    Ok(())
}

fn validate_geometry(
    geometry: &CountryGeometry,
    bytes: &[u8],
    layout: Layout,
) -> crate::Result<()> {
    if geometry.columns() != 360
        || geometry.rows() != 180
        || geometry.country_count() != layout.territory_count
        || geometry
            .country_codes()
            .any(|code| territory_index_for_code(bytes, layout, code).is_none())
    {
        return Err(invalid("geometry does not match the territory catalog"));
    }
    Ok(())
}

fn validate_string(
    bytes: &[u8],
    strings: usize,
    string_length: usize,
    start: usize,
    length: usize,
) -> crate::Result<()> {
    let end = start
        .checked_add(length)
        .ok_or(invalid("string range overflow"))?;
    if end > string_length {
        return Err(invalid("string exceeds string table"));
    }
    str::from_utf8(&bytes[strings + start..strings + end]).map_err(|_| invalid("invalid UTF-8"))?;
    Ok(())
}

fn territory_index_for_code(bytes: &[u8], layout: Layout, code: CountryCode) -> Option<usize> {
    (0..layout.territory_count).find(|&index| {
        let offset = layout.territories + index * TERRITORY_LEN + 2;
        bytes[offset..offset + 2] == code.as_bytes()
    })
}

fn worldview_index(bytes: &[u8], layout: Layout, code: CountryCode) -> Option<usize> {
    (0..layout.worldview_count).find(|&index| {
        let country = bytes[layout.worldviews + index];
        country_code(bytes, layout, country) == code
    })
}

fn country_code(bytes: &[u8], layout: Layout, index: u8) -> CountryCode {
    let offset = layout.countries + usize::from(index) * 2;
    CountryCode::from_validated([bytes[offset], bytes[offset + 1]])
}

fn decode_optional_country(bytes: &[u8], layout: Layout, index: u8) -> Option<CountryCode> {
    (index != MISSING_COUNTRY).then(|| country_code(bytes, layout, index))
}

fn validate_country(index: u8, count: usize) -> crate::Result<()> {
    if usize::from(index) < count {
        Ok(())
    } else {
        Err(invalid("catalog references unknown country"))
    }
}

fn validate_optional_country(index: u8, count: usize) -> crate::Result<()> {
    if index == MISSING_COUNTRY {
        Ok(())
    } else {
        validate_country(index, count)
    }
}

fn code_at(bytes: &[u8], offset: usize) -> crate::Result<[u8; 2]> {
    let code = [bytes[offset], bytes[offset + 1]];
    if code.iter().all(u8::is_ascii_uppercase) {
        Ok(code)
    } else {
        Err(invalid("invalid country code"))
    }
}

fn read_u16(bytes: &[u8], offset: usize) -> crate::Result<u16> {
    u16_at(bytes, offset).ok_or(invalid("truncated"))
}

fn read_usize(bytes: &[u8], offset: usize) -> crate::Result<usize> {
    Ok(u32_at(bytes, offset).ok_or(invalid("truncated"))? as usize)
}

fn read_u16_infallible(bytes: &[u8], offset: usize) -> u16 {
    u16_at(bytes, offset).expect("validated territory field")
}

fn invalid(reason: &'static str) -> Error {
    Error::invalid(SECTION, reason)
}
