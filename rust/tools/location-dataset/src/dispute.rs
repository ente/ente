use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use ente_location::TerritoryId;
use shapefile::Reader;
use shapefile::dbase::Record;

use crate::catalog::{DISPUTED_AREAS, UKRAINIAN_REGIONS, WORLDVIEWS};
use crate::country::{
    Area, character_field, encode as encode_geometry, natural_earth_country_code, polygon_geometry,
};
use crate::{Result, invalid};

const HEADER_LEN: usize = 64;
const TERRITORY_LEN: usize = 12;
const MISSING_COUNTRY: u8 = u8::MAX;

#[derive(Clone)]
struct SourceDispute {
    territory: TerritoryId,
    geometry_code: [u8; 2],
    name: String,
    source_default: Option<[u8; 2]>,
    possible_countries: Vec<[u8; 2]>,
    worldview_assignments: Vec<Option<[u8; 2]>>,
}

struct EncodedRecord {
    territory: TerritoryId,
    geometry_code: [u8; 2],
    default_country: u8,
    candidate_start: u16,
    candidate_count: u8,
    name_start: u16,
    name_length: u8,
}

pub(crate) fn build(
    countries_path: &Path,
    disputes_path: &Path,
    admin1_path: &Path,
) -> Result<Vec<u8>> {
    let country_codes = read_country_codes(countries_path)?;
    let (mut metadata, mut areas) = read_disputed_areas(disputes_path, &country_codes)?;
    let (ukraine_metadata, ukraine_areas) = read_ukrainian_regions(admin1_path)?;
    metadata.extend(ukraine_metadata);
    areas.extend(ukraine_areas);
    if metadata.len() != DISPUTED_AREAS.len() + UKRAINIAN_REGIONS.len() {
        return Err(invalid("Priority-1 dispute catalog is incomplete"));
    }
    let geometry = encode_geometry(&areas)?;
    encode(&geometry, &metadata)
}

fn read_country_codes(path: &Path) -> Result<BTreeMap<String, [u8; 2]>> {
    let mut reader = Reader::from_path(path)?;
    let mut codes = BTreeMap::new();
    for shape_record in reader.iter_shapes_and_records() {
        let (_, record) = shape_record?;
        let Some(code) = natural_earth_country_code(&record) else {
            continue;
        };
        for field in [
            "ADM0_A3",
            "SOV_A3",
            "ISO_A3_EH",
            "ISO_A3",
            "GU_A3",
            "SU_A3",
            "ADM0_TLC",
        ] {
            let Some(value) = character_field(&record, field) else {
                continue;
            };
            if value.len() == 3 && value.bytes().all(|byte| byte.is_ascii_uppercase()) {
                codes.entry(value.to_owned()).or_insert(code);
            }
        }
    }
    Ok(codes)
}

fn read_disputed_areas(
    path: &Path,
    country_codes: &BTreeMap<String, [u8; 2]>,
) -> Result<(Vec<SourceDispute>, Vec<Area>)> {
    let selections: BTreeMap<&str, _> = DISPUTED_AREAS
        .iter()
        .map(|source| (source.source_id, source))
        .collect();
    let mut seen = BTreeSet::new();
    let mut metadata = Vec::new();
    let mut areas = Vec::new();
    let mut reader = Reader::from_path(path)?;
    for shape_record in reader.iter_shapes_and_records() {
        let (shape, record) = shape_record?;
        let Some(source_id) = character_field(&record, "BRK_A3") else {
            continue;
        };
        let Some(selection) = selections.get(source_id) else {
            continue;
        };
        if !seen.insert(source_id.to_owned()) {
            return Err(invalid(format!(
                "duplicate disputed-area source {source_id}"
            )));
        }
        let name = required_field(&record, "NAME_EN", source_id)?.to_owned();
        let geometry = polygon_geometry(shape, source_id)?;
        metadata.push(SourceDispute {
            territory: selection.territory,
            geometry_code: selection.geometry_code,
            name,
            source_default: assigned_country(&record, "ADM0_A3", country_codes),
            possible_countries: selection.additional_countries.to_vec(),
            worldview_assignments: WORLDVIEWS
                .iter()
                .map(|&(_, field)| assigned_country(&record, field, country_codes))
                .collect(),
        });
        areas.push(Area {
            code: selection.geometry_code,
            geometry,
        });
    }
    let missing: Vec<&str> = selections
        .keys()
        .copied()
        .filter(|source| !seen.contains(*source))
        .collect();
    if !missing.is_empty() {
        return Err(invalid(format!(
            "disputed-area source is missing {missing:?}"
        )));
    }
    Ok((metadata, areas))
}

fn read_ukrainian_regions(path: &Path) -> Result<(Vec<SourceDispute>, Vec<Area>)> {
    let selections: BTreeMap<&str, _> = UKRAINIAN_REGIONS
        .iter()
        .map(|source| (source.iso_3166_2, source))
        .collect();
    let mut seen = BTreeSet::new();
    let mut metadata = Vec::new();
    let mut areas = Vec::new();
    let mut reader = Reader::from_path(path)?;
    for shape_record in reader.iter_shapes_and_records() {
        let (shape, record) = shape_record?;
        let Some(iso_code) = character_field(&record, "iso_3166_2") else {
            continue;
        };
        let Some(selection) = selections.get(iso_code) else {
            continue;
        };
        if !seen.insert(iso_code.to_owned()) {
            return Err(invalid(format!("duplicate Admin-1 source {iso_code}")));
        }
        let name = required_field(&record, "name_en", iso_code)?;
        let geometry = polygon_geometry(shape, iso_code)?;
        metadata.push(SourceDispute {
            territory: selection.territory,
            geometry_code: selection.geometry_code,
            name: format!("{name} Region"),
            source_default: Some(*b"UA"),
            possible_countries: vec![*b"RU", *b"UA"],
            worldview_assignments: WORLDVIEWS
                .iter()
                .map(|&(viewpoint, _)| Some(if viewpoint == *b"RU" { *b"RU" } else { *b"UA" }))
                .collect(),
        });
        areas.push(Area {
            code: selection.geometry_code,
            geometry,
        });
    }
    let missing: Vec<&str> = selections
        .keys()
        .copied()
        .filter(|source| !seen.contains(*source))
        .collect();
    if !missing.is_empty() {
        return Err(invalid(format!("Admin-1 source is missing {missing:?}")));
    }
    Ok((metadata, areas))
}

fn encode(geometry: &[u8], source: &[SourceDispute]) -> Result<Vec<u8>> {
    let mut disputes = source.to_vec();
    disputes.sort_unstable_by_key(|dispute| dispute.territory);
    validate_source(&disputes)?;
    let countries = collect_countries(&disputes)?;
    let country_indices: BTreeMap<[u8; 2], u8> = countries
        .iter()
        .copied()
        .enumerate()
        .map(|(index, code)| (code, index as u8))
        .collect();

    let mut candidates = Vec::new();
    let mut assignments = Vec::with_capacity(disputes.len() * WORLDVIEWS.len());
    let mut strings = Vec::new();
    let mut records = Vec::with_capacity(disputes.len());
    for dispute in &disputes {
        let candidate_start = u16_length(candidates.len(), "too many dispute candidates")?;
        let possible = complete_candidates(dispute);
        let candidate_count = u8::try_from(possible.len())
            .map_err(|_| invalid("too many candidates for one territory"))?;
        candidates.extend(possible.into_iter().map(|code| country_indices[&code]));

        let name_start = u16_length(strings.len(), "dispute strings exceed 64 KiB")?;
        let name_length = u8::try_from(dispute.name.len())
            .map_err(|_| invalid("territory name exceeds 255 bytes"))?;
        strings.extend_from_slice(dispute.name.as_bytes());

        records.push(EncodedRecord {
            territory: dispute.territory,
            geometry_code: dispute.geometry_code,
            default_country: encode_optional(dispute.source_default, &country_indices),
            candidate_start,
            candidate_count,
            name_start,
            name_length,
        });
        assignments.extend(
            dispute
                .worldview_assignments
                .iter()
                .copied()
                .map(|country| encode_optional(country, &country_indices)),
        );
    }
    u16_length(strings.len(), "dispute strings exceed 64 KiB")?;

    let countries_offset = HEADER_LEN;
    let worldviews_offset = countries_offset + countries.len() * 2;
    let territories_offset = worldviews_offset + WORLDVIEWS.len();
    let candidates_offset = territories_offset + records.len() * TERRITORY_LEN;
    let assignments_offset = candidates_offset + candidates.len();
    let strings_offset = assignments_offset + assignments.len();
    let geometry_offset = strings_offset + strings.len();
    let file_length = geometry_offset
        .checked_add(geometry.len())
        .ok_or_else(|| invalid("dispute index size overflow"))?;
    let mut output = Vec::with_capacity(file_length);

    output.extend_from_slice(b"DSPT");
    push_u16(&mut output, 1);
    push_u16(&mut output, HEADER_LEN as u16);
    push_u16(
        &mut output,
        u16_length(WORLDVIEWS.len(), "too many worldviews")?,
    );
    push_u16(
        &mut output,
        u16_length(records.len(), "too many territories")?,
    );
    push_u16(
        &mut output,
        u16_length(countries.len(), "too many countries")?,
    );
    push_u16(&mut output, TERRITORY_LEN as u16);
    for value in [
        countries_offset,
        worldviews_offset,
        territories_offset,
        candidates_offset,
        assignments_offset,
        strings_offset,
        geometry_offset,
        file_length,
    ] {
        push_length(&mut output, value)?;
    }
    output.resize(HEADER_LEN, 0);
    for country in &countries {
        output.extend_from_slice(country);
    }
    for &(worldview, _) in WORLDVIEWS {
        output.push(country_indices[&worldview]);
    }
    for record in records {
        push_u16(&mut output, record.territory.get());
        output.extend_from_slice(&record.geometry_code);
        output.push(record.default_country);
        output.push(record.candidate_count);
        push_u16(&mut output, record.candidate_start);
        push_u16(&mut output, record.name_start);
        output.push(record.name_length);
        output.push(0);
    }
    output.extend_from_slice(&candidates);
    output.extend_from_slice(&assignments);
    output.extend_from_slice(&strings);
    output.extend_from_slice(geometry);
    debug_assert_eq!(output.len(), file_length);
    Ok(output)
}

fn validate_source(disputes: &[SourceDispute]) -> Result<()> {
    let mut ids = BTreeSet::new();
    let mut geometry_codes = BTreeSet::new();
    for dispute in disputes {
        if !ids.insert(dispute.territory)
            || !geometry_codes.insert(dispute.geometry_code)
            || dispute.name.is_empty()
            || dispute.worldview_assignments.len() != WORLDVIEWS.len()
        {
            return Err(invalid("invalid or duplicate dispute metadata"));
        }
    }
    Ok(())
}

fn collect_countries(disputes: &[SourceDispute]) -> Result<Vec<[u8; 2]>> {
    let mut countries: BTreeSet<[u8; 2]> = WORLDVIEWS.iter().map(|&(code, _)| code).collect();
    for dispute in disputes {
        countries.extend(complete_candidates(dispute));
    }
    if countries.len() >= usize::from(MISSING_COUNTRY) {
        return Err(invalid("dispute country table exceeds one-byte indices"));
    }
    if countries
        .iter()
        .flatten()
        .any(|byte| !byte.is_ascii_uppercase())
    {
        return Err(invalid("dispute catalog contains an invalid country code"));
    }
    Ok(countries.into_iter().collect())
}

fn complete_candidates(dispute: &SourceDispute) -> BTreeSet<[u8; 2]> {
    let mut countries: BTreeSet<[u8; 2]> = dispute.possible_countries.iter().copied().collect();
    countries.extend(dispute.source_default);
    countries.extend(dispute.worldview_assignments.iter().flatten().copied());
    countries
}

fn assigned_country(
    record: &Record,
    field: &str,
    country_codes: &BTreeMap<String, [u8; 2]>,
) -> Option<[u8; 2]> {
    character_field(record, field).and_then(|code| country_codes.get(code).copied())
}

fn required_field<'a>(record: &'a Record, field: &str, source: &str) -> Result<&'a str> {
    character_field(record, field)
        .ok_or_else(|| invalid(format!("source {source} is missing {field}")))
}

fn encode_optional(country: Option<[u8; 2]>, country_indices: &BTreeMap<[u8; 2], u8>) -> u8 {
    country.map_or(MISSING_COUNTRY, |code| country_indices[&code])
}

fn u16_length(value: usize, message: &'static str) -> Result<u16> {
    u16::try_from(value).map_err(|_| invalid(message))
}

fn push_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn push_length(output: &mut Vec<u8>, value: usize) -> Result<()> {
    output.extend_from_slice(
        &u32::try_from(value)
            .map_err(|_| invalid("dispute index exceeds 4 GiB"))?
            .to_le_bytes(),
    );
    Ok(())
}

#[cfg(test)]
pub(crate) fn test_bytes() -> Vec<u8> {
    use geo::{LineString, MultiPolygon, Polygon};

    let geometry = encode_geometry(&[Area {
        code: *b"AC",
        geometry: MultiPolygon(vec![Polygon::new(
            LineString::from(vec![
                (79.0, 35.0),
                (80.0, 35.0),
                (80.0, 36.0),
                (79.0, 36.0),
                (79.0, 35.0),
            ]),
            vec![],
        )]),
    }])
    .unwrap();
    encode(
        &geometry,
        &[SourceDispute {
            territory: TerritoryId::AKSAI_CHIN,
            geometry_code: *b"AC",
            name: "Aksai Chin".to_owned(),
            source_default: Some(*b"CN"),
            possible_countries: vec![*b"CN", *b"IN"],
            worldview_assignments: WORLDVIEWS
                .iter()
                .map(|&(region, _)| Some(if region == *b"IN" { *b"IN" } else { *b"CN" }))
                .collect(),
        }],
    )
    .unwrap()
}

#[cfg(test)]
mod tests {
    use ente_location::{Coordinate, CountryCode, CountryIndex, CountryView, TerritoryId};
    use geo::{LineString, MultiPolygon, Polygon};

    use crate::country::{Area, encode as encode_geometry};

    use super::test_bytes;

    #[test]
    fn builds_and_resolves_a_dispute_overlay() {
        let countries = encode_geometry(&[Area {
            code: *b"AA",
            geometry: MultiPolygon(vec![Polygon::new(
                LineString::from(vec![
                    (79.0, 35.0),
                    (80.0, 35.0),
                    (80.0, 36.0),
                    (79.0, 36.0),
                    (79.0, 35.0),
                ]),
                vec![],
            )]),
        }])
        .unwrap();
        let index = CountryIndex::from_bytes(countries, test_bytes()).unwrap();
        let disputed = index.lookup(Coordinate::new(35.5, 79.5)).unwrap().disputes[0];
        let india = CountryCode::from_bytes(*b"IN").unwrap();

        assert_eq!(disputed.territory_id(), TerritoryId::AKSAI_CHIN);
        assert_eq!(disputed.name(), "Aksai Chin");
        assert_eq!(disputed.resolve(CountryView::Neutral), None);
        assert_eq!(
            disputed.resolve(CountryView::SourceDefault),
            Some(CountryCode::from_bytes(*b"CN").unwrap())
        );
        assert_eq!(disputed.resolve(CountryView::Region(india)), Some(india));
    }
}
