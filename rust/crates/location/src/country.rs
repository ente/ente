use crate::binary::{array, range, u16_at, u32_at};
use crate::{CountryCode, Error};

const MAGIC: &[u8; 4] = b"CTRY";
const VERSION: u16 = 1;
const HEADER_LEN: usize = 48;
const BLOCK_SIZE: usize = 64;
const BLOCK_LEN: usize = 12;
const SECTION: &str = "country index";

#[derive(Clone, Copy, Debug)]
struct Layout {
    columns: usize,
    rows: usize,
    country_count: usize,
    cell_count: usize,
    block_count: usize,
    nonempty_count: usize,
    countries: usize,
    blocks: usize,
    cell_offsets: usize,
    cells: usize,
}

#[derive(Debug)]
pub(crate) struct CountryGeometry {
    bytes: Box<[u8]>,
    layout: Layout,
}

impl CountryGeometry {
    pub(crate) fn from_bytes(bytes: impl Into<Box<[u8]>>) -> crate::Result<Self> {
        let bytes = bytes.into();
        let layout = validate(&bytes)?;
        Ok(Self { bytes, layout })
    }

    pub(crate) const fn country_count(&self) -> usize {
        self.layout.country_count
    }

    pub(crate) fn country_codes(&self) -> impl ExactSizeIterator<Item = CountryCode> + '_ {
        (0..self.layout.country_count).map(|index| self.country_code(index as u8))
    }

    pub(crate) const fn columns(&self) -> usize {
        self.layout.columns
    }

    pub(crate) const fn rows(&self) -> usize {
        self.layout.rows
    }

    pub(crate) fn prepare_cell(
        &self,
        latitude: f64,
        longitude: f64,
    ) -> crate::Result<PreparedCell> {
        if !latitude.is_finite()
            || !longitude.is_finite()
            || !(-90.0..=90.0).contains(&latitude)
            || !(-180.0..=180.0).contains(&longitude)
        {
            return Err(Error::InvalidCoordinate);
        }

        let longitude = normalize(longitude, -180.0, 360.0);
        let cell_x = (((longitude + 180.0) * self.layout.columns as f64 / 360.0).floor() as usize)
            .min(self.layout.columns - 1);
        let cell_y = ((self.layout.rows as f64 * (90.0 - latitude) / 180.0).ceil() as usize)
            .saturating_sub(1);
        Ok(PreparedCell {
            latitude,
            longitude,
            x: cell_x,
            y: cell_y,
            index: cell_y * self.layout.columns + cell_x,
        })
    }

    pub(crate) fn lookup_prepared(
        &self,
        location: PreparedCell,
    ) -> crate::Result<Vec<CountryCode>> {
        let Some(dense_index) = self.dense_cell_index(location.index) else {
            return Ok(Vec::new());
        };
        let point = Point {
            x: {
                let cell_longitude =
                    -180.0 + 360.0 * location.x as f64 / self.layout.columns as f64;
                ((location.longitude - cell_longitude)
                    * self.layout.columns as f64
                    * f64::from(u16::MAX)
                    / 360.0) as u16
            },
            y: {
                let cell_latitude =
                    90.0 - 180.0 * (location.y + 1) as f64 / self.layout.rows as f64;
                ((location.latitude - cell_latitude)
                    * self.layout.rows as f64
                    * f64::from(u16::MAX)
                    / 180.0) as u16
            },
        };
        let start = self.cell_offset(dense_index);
        let end = self.cell_offset(dense_index + 1);
        self.lookup_cell(
            &self.bytes[self.layout.cells + start..self.layout.cells + end],
            point,
        )
    }

    fn dense_cell_index(&self, cell_index: usize) -> Option<usize> {
        let block_index = cell_index / BLOCK_SIZE;
        let bit_index = cell_index % BLOCK_SIZE;
        let offset = self.layout.blocks + block_index * BLOCK_LEN;
        let mask = u64::from_le_bytes(array(&self.bytes, offset).expect("validated block"));
        let bit = 1_u64 << bit_index;
        if mask & bit == 0 {
            return None;
        }
        let first = u32_at(&self.bytes, offset + 8).expect("validated block") as usize;
        Some(first + (mask & bit.wrapping_sub(1)).count_ones() as usize)
    }

    fn cell_offset(&self, dense_index: usize) -> usize {
        u32_at(&self.bytes, self.layout.cell_offsets + dense_index * 4)
            .expect("validated cell offset") as usize
    }

    fn country_code(&self, index: u8) -> CountryCode {
        let offset = self.layout.countries + usize::from(index) * 2;
        CountryCode::from_validated([self.bytes[offset], self.bytes[offset + 1]])
    }

    fn lookup_cell(&self, bytes: &[u8], point: Point) -> crate::Result<Vec<CountryCode>> {
        let mut reader = Reader::new(bytes);
        let mut matches = Vec::new();
        for _ in 0..reader.byte()? {
            push_unique(&mut matches, self.country_code(reader.byte()?));
        }
        for _ in 0..reader.byte()? {
            let country = self.country_code(reader.byte()?);
            let mut winding = 0_i32;
            for _ in 0..reader.byte()? {
                if reader.ring_contains(point)? {
                    winding += 1;
                }
            }
            for _ in 0..reader.byte()? {
                if reader.ring_contains(point)? {
                    winding -= 1;
                }
            }
            if winding > 0 {
                push_unique(&mut matches, country);
            }
        }
        debug_assert_eq!(reader.position, bytes.len());
        Ok(matches)
    }
}

#[derive(Clone, Copy)]
pub(crate) struct PreparedCell {
    latitude: f64,
    longitude: f64,
    x: usize,
    y: usize,
    index: usize,
}

#[derive(Clone, Copy)]
struct Point {
    x: u16,
    y: u16,
}

struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    const fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, position: 0 }
    }

    fn byte(&mut self) -> crate::Result<u8> {
        let value = *self.bytes.get(self.position).ok_or(invalid("truncated"))?;
        self.position += 1;
        Ok(value)
    }

    fn take(&mut self, count: usize) -> crate::Result<&'a [u8]> {
        let end = self
            .position
            .checked_add(count)
            .ok_or(invalid("truncated"))?;
        let bytes = self
            .bytes
            .get(self.position..end)
            .ok_or(invalid("truncated"))?;
        self.position = end;
        Ok(bytes)
    }

    fn ring_contains(&mut self, point: Point) -> crate::Result<bool> {
        let count = usize::from(u16::from_le_bytes(
            self.take(2)?.try_into().expect("two-byte slice"),
        ));
        if count == 0 {
            return Ok(false);
        }
        let ring = self.take(count.checked_mul(4).ok_or(invalid("ring size overflow"))?)?;
        let mut winding = 0_i32;
        let mut previous = point_at(ring, count - 1);
        for index in 0..count {
            let current = point_at(ring, index);
            if previous.y <= point.y {
                if current.y > point.y && is_left(previous, current, point) > 0 {
                    winding += 1;
                }
            } else if current.y <= point.y && is_left(previous, current, point) < 0 {
                winding -= 1;
            }
            previous = current;
        }
        Ok(winding != 0)
    }
}

fn validate(bytes: &[u8]) -> crate::Result<Layout> {
    if bytes.len() < HEADER_LEN {
        return Err(invalid("truncated"));
    }
    if &bytes[..4] != MAGIC {
        return Err(invalid("invalid magic"));
    }
    let version = u16_at(bytes, 4).ok_or(invalid("truncated"))?;
    if version != VERSION {
        return Err(Error::invalid(
            SECTION,
            format!("unsupported format version {version}"),
        ));
    }
    if usize::from(u16_at(bytes, 6).ok_or(invalid("truncated"))?) != HEADER_LEN
        || usize::from(u16_at(bytes, 14).ok_or(invalid("truncated"))?) != BLOCK_SIZE
    {
        return Err(invalid("unexpected header or block length"));
    }
    let layout = Layout {
        columns: usize::from(u16_at(bytes, 8).ok_or(invalid("truncated"))?),
        rows: usize::from(u16_at(bytes, 10).ok_or(invalid("truncated"))?),
        country_count: usize::from(u16_at(bytes, 12).ok_or(invalid("truncated"))?),
        cell_count: read_usize(bytes, 16)?,
        block_count: read_usize(bytes, 20)?,
        nonempty_count: read_usize(bytes, 24)?,
        countries: read_usize(bytes, 28)?,
        blocks: read_usize(bytes, 32)?,
        cell_offsets: read_usize(bytes, 36)?,
        cells: read_usize(bytes, 40)?,
    };
    let declared_length = read_usize(bytes, 44)?;
    validate_layout(bytes, layout, declared_length)?;
    Ok(layout)
}

fn validate_layout(bytes: &[u8], layout: Layout, declared_length: usize) -> crate::Result<()> {
    if layout.columns == 0
        || layout.rows == 0
        || layout.country_count == 0
        || layout.country_count > 256
    {
        return Err(invalid("invalid grid or country count"));
    }
    if layout.cell_count
        != layout
            .columns
            .checked_mul(layout.rows)
            .ok_or(invalid("cell count overflow"))?
        || layout.block_count != layout.cell_count.div_ceil(BLOCK_SIZE)
        || layout.nonempty_count > layout.cell_count
    {
        return Err(invalid("invalid grid counts"));
    }

    let countries = range(layout.countries, layout.country_count, 2)
        .ok_or(invalid("country section overflow"))?;
    let blocks = range(layout.blocks, layout.block_count, BLOCK_LEN)
        .ok_or(invalid("block section overflow"))?;
    let offsets = range(
        layout.cell_offsets,
        layout
            .nonempty_count
            .checked_add(1)
            .ok_or(invalid("cell offset overflow"))?,
        4,
    )
    .ok_or(invalid("cell offset overflow"))?;
    if layout.countries != HEADER_LEN
        || layout.blocks != countries.end
        || layout.cell_offsets != blocks.end
        || layout.cells != offsets.end
        || layout.cells > bytes.len()
        || declared_length != bytes.len()
    {
        return Err(invalid("sections are not contiguous"));
    }

    let mut seen_codes = [false; 26 * 26];
    for index in 0..layout.country_count {
        let offset = layout.countries + index * 2;
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

    let mut expected_dense = 0;
    for block in 0..layout.block_count {
        let offset = layout.blocks + block * BLOCK_LEN;
        let mask = u64::from_le_bytes(array(bytes, offset).expect("validated block range"));
        let first = u32_at(bytes, offset + 8).expect("validated block range") as usize;
        if first != expected_dense {
            return Err(invalid("invalid block dense offset"));
        }
        if block + 1 == layout.block_count {
            let used_bits = layout.cell_count - block * BLOCK_SIZE;
            if used_bits < BLOCK_SIZE && mask >> used_bits != 0 {
                return Err(invalid("last block references nonexistent cells"));
            }
        }
        expected_dense += mask.count_ones() as usize;
    }
    if expected_dense != layout.nonempty_count {
        return Err(invalid("wrong nonempty cell count"));
    }

    let cells_length = bytes.len() - layout.cells;
    let mut previous = 0;
    for index in 0..=layout.nonempty_count {
        let offset = u32_at(bytes, layout.cell_offsets + index * 4).expect("validated offset range")
            as usize;
        if offset < previous || offset > cells_length {
            return Err(invalid("invalid cell offset"));
        }
        if index > 0 {
            validate_cell(
                &bytes[layout.cells + previous..layout.cells + offset],
                layout.country_count,
            )?;
        }
        previous = offset;
    }
    if previous != cells_length {
        return Err(invalid("last cell offset is not terminal"));
    }
    Ok(())
}

fn validate_cell(bytes: &[u8], country_count: usize) -> crate::Result<()> {
    let mut reader = Reader::new(bytes);
    for _ in 0..reader.byte()? {
        validate_country(reader.byte()?, country_count)?;
    }
    for _ in 0..reader.byte()? {
        validate_country(reader.byte()?, country_count)?;
        skip_rings(&mut reader)?;
        skip_rings(&mut reader)?;
    }
    if reader.position != bytes.len() {
        return Err(invalid("cell has trailing bytes"));
    }
    Ok(())
}

fn skip_rings(reader: &mut Reader<'_>) -> crate::Result<()> {
    for _ in 0..reader.byte()? {
        let count = usize::from(u16::from_le_bytes(
            reader.take(2)?.try_into().expect("two-byte slice"),
        ));
        reader.take(count.checked_mul(4).ok_or(invalid("ring size overflow"))?)?;
    }
    Ok(())
}

fn validate_country(index: u8, country_count: usize) -> crate::Result<()> {
    if usize::from(index) < country_count {
        Ok(())
    } else {
        Err(invalid("cell references unknown country"))
    }
}

fn point_at(ring: &[u8], index: usize) -> Point {
    let offset = index * 4;
    Point {
        x: u16::from_le_bytes([ring[offset], ring[offset + 1]]),
        y: u16::from_le_bytes([ring[offset + 2], ring[offset + 3]]),
    }
}

fn is_left(start: Point, end: Point, point: Point) -> i64 {
    (i64::from(end.x) - i64::from(start.x)) * (i64::from(point.y) - i64::from(start.y))
        - (i64::from(point.x) - i64::from(start.x)) * (i64::from(end.y) - i64::from(start.y))
}

fn normalize(value: f64, minimum: f64, width: f64) -> f64 {
    (value - minimum).rem_euclid(width) + minimum
}

fn push_unique(countries: &mut Vec<CountryCode>, country: CountryCode) {
    if !countries.contains(&country) {
        countries.push(country);
    }
}

fn read_usize(bytes: &[u8], offset: usize) -> crate::Result<usize> {
    Ok(u32_at(bytes, offset).ok_or(invalid("truncated"))? as usize)
}

fn invalid(reason: &'static str) -> Error {
    Error::invalid(SECTION, reason)
}
