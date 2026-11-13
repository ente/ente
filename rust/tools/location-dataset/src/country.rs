use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use geo::{BooleanOps, BoundingRect, Contains, Coord, LineString, MultiPolygon, Rect};
use shapefile::dbase::{FieldValue, Record};
use shapefile::{Reader, Shape};

use crate::{Result, invalid};

const COLUMNS: u16 = 360;
const ROWS: u16 = 180;
const HEADER_LEN: usize = 48;
const BLOCK_SIZE: usize = 64;
const BLOCK_LEN: usize = 12;

pub(crate) struct Area {
    pub code: [u8; 2],
    pub geometry: MultiPolygon<f64>,
}

#[derive(Default)]
struct Cell {
    containing: BTreeSet<[u8; 2]>,
    intersecting: BTreeMap<[u8; 2], CellAreas>,
}

#[derive(Default)]
struct CellAreas {
    outer: Vec<Vec<[u16; 2]>>,
    inner: Vec<Vec<[u16; 2]>>,
}

pub(crate) fn build_countries(path: &Path) -> Result<Vec<u8>> {
    let mut reader = Reader::from_path(path)?;
    let mut areas = Vec::new();
    for shape_record in reader.iter_shapes_and_records() {
        let (shape, record) = shape_record?;
        let Some(code) = natural_earth_country_code(&record) else {
            continue;
        };
        if &code == b"AQ" {
            continue;
        }
        areas.push(Area {
            code,
            geometry: polygon_geometry(shape, "country")?,
        });
    }
    encode(&areas)
}

pub(crate) fn encode(areas: &[Area]) -> Result<Vec<u8>> {
    if areas.is_empty() {
        return Err(invalid("country geometry is empty"));
    }
    let mut cells: Vec<Cell> = (0..usize::from(COLUMNS) * usize::from(ROWS))
        .map(|_| Cell::default())
        .collect();
    for area in areas {
        validate_code(area.code)?;
        add_area(&mut cells, area)?;
    }
    encode_cells(&cells)
}

fn add_area(cells: &mut [Cell], area: &Area) -> Result<()> {
    for polygon in &area.geometry {
        add_polygon(cells, area.code, polygon)?;
    }
    Ok(())
}

fn add_polygon(cells: &mut [Cell], code: [u8; 2], polygon: &geo::Polygon<f64>) -> Result<()> {
    let bounds = polygon
        .bounding_rect()
        .ok_or_else(|| invalid("country polygon has no bounds"))?;
    let minimum_column = longitude_column(bounds.min().x);
    let maximum_column = longitude_column(bounds.max().x);
    let northern_row = latitude_row(bounds.max().y);
    let southern_row = latitude_row(bounds.min().y);

    for row in northern_row..=southern_row {
        for column in minimum_column..=maximum_column {
            let bounds = cell_rect(column, row);
            let cell = &mut cells[row * usize::from(COLUMNS) + column];
            if polygon.contains(&bounds) {
                cell.containing.insert(code);
                cell.intersecting.remove(&code);
                continue;
            }
            if cell.containing.contains(&code) {
                continue;
            }
            let intersection = polygon.intersection(&bounds.to_polygon());
            if intersection.0.is_empty() {
                continue;
            }
            let areas = cell.intersecting.entry(code).or_default();
            for polygon in intersection {
                if let Some(ring) = encode_ring(polygon.exterior(), bounds) {
                    areas.outer.push(ring);
                }
                for ring in polygon.interiors() {
                    if let Some(ring) = encode_ring(ring, bounds) {
                        areas.inner.push(ring);
                    }
                }
            }
            if areas.outer.is_empty() {
                cell.intersecting.remove(&code);
            }
        }
    }
    Ok(())
}

fn encode_cells(cells: &[Cell]) -> Result<Vec<u8>> {
    let countries: Vec<[u8; 2]> = cells
        .iter()
        .flat_map(|cell| {
            cell.containing
                .iter()
                .copied()
                .chain(cell.intersecting.keys().copied())
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    if countries.is_empty() || countries.len() > 256 {
        return Err(invalid("country table does not fit one-byte indices"));
    }
    let country_indices: BTreeMap<[u8; 2], u8> = countries
        .iter()
        .copied()
        .enumerate()
        .map(|(index, code)| (code, index as u8))
        .collect();

    let encoded_cells: Vec<Option<Vec<u8>>> = cells
        .iter()
        .map(|cell| encode_cell(cell, &country_indices))
        .collect::<Result<_>>()?;
    let cell_count = cells.len();
    let block_count = cell_count.div_ceil(BLOCK_SIZE);
    let nonempty_count = encoded_cells.iter().filter(|cell| cell.is_some()).count();
    let countries_offset = HEADER_LEN;
    let blocks_offset = countries_offset + countries.len() * 2;
    let cell_offsets_offset = blocks_offset + block_count * BLOCK_LEN;
    let cells_offset = cell_offsets_offset + (nonempty_count + 1) * 4;
    let data_length: usize = encoded_cells.iter().flatten().map(Vec::len).sum();
    let file_length = cells_offset
        .checked_add(data_length)
        .ok_or_else(|| invalid("country index size overflow"))?;
    let mut output = Vec::with_capacity(file_length);

    output.extend_from_slice(b"CTRY");
    push_u16(&mut output, 1);
    push_u16(&mut output, HEADER_LEN as u16);
    push_u16(&mut output, COLUMNS);
    push_u16(&mut output, ROWS);
    push_u16(
        &mut output,
        u16::try_from(countries.len()).map_err(|_| invalid("too many countries"))?,
    );
    push_u16(&mut output, BLOCK_SIZE as u16);
    for value in [
        cell_count,
        block_count,
        nonempty_count,
        countries_offset,
        blocks_offset,
        cell_offsets_offset,
        cells_offset,
        file_length,
    ] {
        push_len(&mut output, value)?;
    }
    for code in &countries {
        output.extend_from_slice(code);
    }

    let mut dense_start = 0;
    for block in 0..block_count {
        let mut mask = 0_u64;
        for bit in 0..BLOCK_SIZE {
            let index = block * BLOCK_SIZE + bit;
            if index < cell_count && encoded_cells[index].is_some() {
                mask |= 1_u64 << bit;
            }
        }
        output.extend_from_slice(&mask.to_le_bytes());
        push_len(&mut output, dense_start)?;
        dense_start += mask.count_ones() as usize;
    }

    let mut cell_offset = 0;
    push_len(&mut output, cell_offset)?;
    for cell in encoded_cells.iter().flatten() {
        cell_offset += cell.len();
        push_len(&mut output, cell_offset)?;
    }
    for cell in encoded_cells.into_iter().flatten() {
        output.extend_from_slice(&cell);
    }
    debug_assert_eq!(output.len(), file_length);
    Ok(output)
}

fn encode_cell(cell: &Cell, countries: &BTreeMap<[u8; 2], u8>) -> Result<Option<Vec<u8>>> {
    if cell.containing.is_empty() && cell.intersecting.is_empty() {
        return Ok(None);
    }
    let mut output = Vec::new();
    output.push(
        u8::try_from(cell.containing.len())
            .map_err(|_| invalid("too many containing countries in one cell"))?,
    );
    output.extend(cell.containing.iter().map(|code| countries[code]));
    output.push(
        u8::try_from(cell.intersecting.len())
            .map_err(|_| invalid("too many intersecting countries in one cell"))?,
    );
    for (code, areas) in &cell.intersecting {
        output.push(countries[code]);
        encode_rings(&mut output, &areas.outer)?;
        encode_rings(&mut output, &areas.inner)?;
    }
    Ok(Some(output))
}

fn encode_rings(output: &mut Vec<u8>, rings: &[Vec<[u16; 2]>]) -> Result<()> {
    output.push(
        u8::try_from(rings.len()).map_err(|_| invalid("too many clipped rings in one cell"))?,
    );
    for ring in rings {
        push_u16(
            output,
            u16::try_from(ring.len()).map_err(|_| invalid("clipped ring is too long"))?,
        );
        for &[x, y] in ring {
            push_u16(output, x);
            push_u16(output, y);
        }
    }
    Ok(())
}

fn encode_ring(ring: &LineString<f64>, bounds: Rect<f64>) -> Option<Vec<[u16; 2]>> {
    let width = bounds.width();
    let height = bounds.height();
    let mut points: Vec<[u16; 2]> = ring
        .0
        .iter()
        .map(|coordinate| {
            [
                quantize(coordinate.x, bounds.min().x, width),
                quantize(coordinate.y, bounds.min().y, height),
            ]
        })
        .collect();
    points.dedup();
    while points.len() > 3 && points.first() == points.last() {
        points.pop();
    }
    loop {
        if points.len() <= 3 {
            break;
        }
        let removable: Vec<bool> = (0..points.len())
            .map(|index| {
                lies_on_segment(
                    points[(index + points.len() - 1) % points.len()],
                    points[index],
                    points[(index + 1) % points.len()],
                )
            })
            .collect();
        let retained = removable.iter().filter(|&&remove| !remove).count();
        if retained < 3 || retained == points.len() {
            break;
        }
        points = points
            .into_iter()
            .zip(removable)
            .filter_map(|(point, remove)| (!remove).then_some(point))
            .collect();
    }
    (points.len() >= 3).then_some(points)
}

fn cell_rect(column: usize, row: usize) -> Rect<f64> {
    let minimum_longitude = -180.0 + column as f64 * 360.0 / f64::from(COLUMNS);
    let maximum_latitude = 90.0 - row as f64 * 180.0 / f64::from(ROWS);
    Rect::new(
        Coord {
            x: minimum_longitude,
            y: maximum_latitude - 180.0 / f64::from(ROWS),
        },
        Coord {
            x: minimum_longitude + 360.0 / f64::from(COLUMNS),
            y: maximum_latitude,
        },
    )
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

fn quantize(value: f64, minimum: f64, width: f64) -> u16 {
    (((value - minimum) * f64::from(u16::MAX) / width).clamp(0.0, f64::from(u16::MAX))) as u16
}

fn lies_on_segment(start: [u16; 2], point: [u16; 2], end: [u16; 2]) -> bool {
    let cross = (i64::from(point[0]) - i64::from(start[0]))
        * (i64::from(end[1]) - i64::from(start[1]))
        - (i64::from(point[1]) - i64::from(start[1])) * (i64::from(end[0]) - i64::from(start[0]));
    cross == 0
        && point[0] >= start[0].min(end[0])
        && point[0] <= start[0].max(end[0])
        && point[1] >= start[1].min(end[1])
        && point[1] <= start[1].max(end[1])
}

pub(crate) fn natural_earth_country_code(record: &Record) -> Option<[u8; 2]> {
    ["ISO_A2_EH", "ISO_A2"]
        .into_iter()
        .filter_map(|field| character_field(record, field))
        .find_map(|value| {
            let code: [u8; 2] = value.as_bytes().try_into().ok()?;
            code.iter().all(u8::is_ascii_uppercase).then_some(code)
        })
}

pub(crate) fn character_field<'a>(record: &'a Record, field: &str) -> Option<&'a str> {
    match record.get(field) {
        Some(FieldValue::Character(Some(value))) => Some(value.trim()),
        _ => None,
    }
}

pub(crate) fn polygon_geometry(shape: Shape, source: &str) -> Result<MultiPolygon<f64>> {
    let Shape::Polygon(polygon) = shape else {
        return Err(invalid(format!("{source} contains a non-polygon shape")));
    };
    let geometry: MultiPolygon<f64> = polygon
        .try_into()
        .map_err(|error| invalid(format!("cannot convert {source} polygon: {error}")))?;
    if geometry.0.is_empty() {
        Err(invalid(format!("{source} has empty geometry")))
    } else {
        Ok(geometry)
    }
}

fn validate_code(code: [u8; 2]) -> Result<()> {
    if code.iter().all(u8::is_ascii_uppercase) {
        Ok(())
    } else {
        Err(invalid("geometry has an invalid country code"))
    }
}

fn push_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn push_len(output: &mut Vec<u8>, value: usize) -> Result<()> {
    output.extend_from_slice(
        &u32::try_from(value)
            .map_err(|_| invalid("country index exceeds 4 GiB"))?
            .to_le_bytes(),
    );
    Ok(())
}
