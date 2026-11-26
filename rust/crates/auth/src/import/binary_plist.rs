use std::collections::BTreeMap;

use serde::Serialize;

use super::{Error, Result};

const HEADER: &[u8; 8] = b"bplist00";
const TRAILER_LENGTH: usize = 32;
const MAX_NESTING: usize = 128;
pub(super) const EXPANSION_ERROR: &str = "OTP Auth archive expansion limit exceeded";

pub(super) type Dictionary = BTreeMap<String, Value>;

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(untagged)]
pub(super) enum Value {
    Null,
    Boolean(bool),
    Integer(u64),
    Real(f64),
    Date(f64),
    Data(Vec<u8>),
    String(String),
    Uid(u64),
    Array(Vec<Value>),
    Dictionary(Dictionary),
}

pub(super) fn parse(input: &[u8], capacity: usize) -> Result<(Value, usize)> {
    Reader::new(input, capacity)?.parse()
}

struct Reader<'a> {
    input: &'a [u8],
    object_table_end: usize,
    reference_width: usize,
    offsets: Vec<usize>,
    active: Vec<bool>,
    depth: usize,
    root: usize,
    budget: Budget,
}

impl<'a> Reader<'a> {
    fn new(input: &'a [u8], capacity: usize) -> Result<Self> {
        if input.len() < HEADER.len() + TRAILER_LENGTH || !input.starts_with(HEADER) {
            return Err(Error::invalid("Invalid binary plist header"));
        }
        let trailer = input.len() - TRAILER_LENGTH;
        let offset_width = usize::from(input[trailer + 6]);
        let reference_width = usize::from(input[trailer + 7]);
        if !(1..=8).contains(&offset_width) || !(1..=8).contains(&reference_width) {
            return Err(Error::invalid("Invalid binary plist integer width"));
        }
        let object_count = read_usize(input, trailer + 8, 8, input.len())?;
        let root = read_usize(input, trailer + 16, 8, input.len())?;
        let offset_table = read_usize(input, trailer + 24, 8, input.len())?;
        let offset_table_length = object_count
            .checked_mul(offset_width)
            .ok_or_else(|| Error::invalid("Invalid binary plist offset table"))?;
        let offset_table_end = offset_table
            .checked_add(offset_table_length)
            .filter(|end| *end <= trailer)
            .ok_or_else(|| Error::invalid("Invalid binary plist offset table"))?;
        if object_count == 0
            || root >= object_count
            || offset_table < HEADER.len()
            || offset_table_end > trailer
        {
            return Err(Error::invalid("Invalid binary plist trailer"));
        }

        let mut budget = Budget::new(capacity);
        let bookkeeping = object_count
            .checked_mul(std::mem::size_of::<usize>() + std::mem::size_of::<bool>())
            .ok_or_else(|| Error::invalid(EXPANSION_ERROR))?;
        budget.consume(bookkeeping)?;

        let mut offsets = Vec::new();
        offsets
            .try_reserve_exact(object_count)
            .map_err(|_| Error::invalid(EXPANSION_ERROR))?;
        for index in 0..object_count {
            let position = offset_table
                .checked_add(
                    index
                        .checked_mul(offset_width)
                        .ok_or_else(|| Error::invalid("Invalid binary plist offset table"))?,
                )
                .ok_or_else(|| Error::invalid("Invalid binary plist offset table"))?;
            let offset = read_usize(input, position, offset_width, trailer)?;
            if !(HEADER.len()..offset_table).contains(&offset) {
                return Err(Error::invalid("Invalid binary plist object offset"));
            }
            offsets.push(offset);
        }
        let mut active = Vec::new();
        active
            .try_reserve_exact(object_count)
            .map_err(|_| Error::invalid(EXPANSION_ERROR))?;
        active.resize(object_count, false);

        Ok(Self {
            input,
            object_table_end: offset_table,
            reference_width,
            active,
            depth: 0,
            offsets,
            root,
            budget,
        })
    }

    fn parse(mut self) -> Result<(Value, usize)> {
        let value = self.read_object(self.root)?;
        Ok((value, self.budget.remaining))
    }

    fn read_object(&mut self, index: usize) -> Result<Value> {
        if index >= self.offsets.len() {
            return Err(Error::invalid("Invalid binary plist reference"));
        }
        if self.active[index] {
            return Err(Error::invalid("Recursive binary plist reference"));
        }
        if self.depth >= MAX_NESTING {
            return Err(Error::invalid("Binary plist nesting limit exceeded"));
        }

        self.budget.consume(1)?;
        self.active[index] = true;
        self.depth += 1;
        let result = self.decode_object(index);
        self.depth -= 1;
        self.active[index] = false;
        result
    }

    fn decode_object(&mut self, index: usize) -> Result<Value> {
        let offset = self.offsets[index];
        let marker = self.byte(offset)?;
        let kind = marker >> 4;
        let info = marker & 0x0f;
        match kind {
            0x0 => match info {
                0x0 => Ok(Value::Null),
                0x8 => Ok(Value::Boolean(false)),
                0x9 => Ok(Value::Boolean(true)),
                _ => Err(Error::invalid("Unsupported binary plist simple value")),
            },
            0x1 => {
                let width = integer_width(info)?;
                Ok(Value::Integer(self.unsigned(offset + 1, width)?))
            }
            0x2 => self.real(offset + 1, integer_width(info)?).map(Value::Real),
            0x3 if info == 0x3 => self.real(offset + 1, 8).map(Value::Date),
            0x4 => self.data(offset, info).map(Value::Data),
            0x5 => self.ascii(offset, info).map(Value::String),
            0x6 => self.utf16(offset, info).map(Value::String),
            0x7 => self.utf8(offset, info).map(Value::String),
            0x8 => {
                let width = usize::from(info) + 1;
                if width > 8 {
                    return Err(Error::invalid("Unsupported binary plist UID width"));
                }
                Ok(Value::Uid(self.unsigned(offset + 1, width)?))
            }
            0xa..=0xc => self.array(offset, info).map(Value::Array),
            0xd => self.dictionary(offset, info).map(Value::Dictionary),
            _ => Err(Error::invalid("Unsupported binary plist object type")),
        }
    }

    fn real(&self, offset: usize, width: usize) -> Result<f64> {
        match width {
            4 => {
                let bytes: [u8; 4] = self
                    .bytes(offset, width)?
                    .try_into()
                    .map_err(|_| Error::invalid("Invalid binary plist floating-point value"))?;
                Ok(f64::from(f32::from_be_bytes(bytes)))
            }
            8 => {
                let bytes: [u8; 8] = self
                    .bytes(offset, width)?
                    .try_into()
                    .map_err(|_| Error::invalid("Invalid binary plist floating-point value"))?;
                Ok(f64::from_be_bytes(bytes))
            }
            _ => Err(Error::invalid(
                "Unsupported binary plist floating-point width",
            )),
        }
    }

    fn data(&mut self, offset: usize, info: u8) -> Result<Vec<u8>> {
        let (length, start) = self.length(offset, info)?;
        self.budget.consume(length)?;
        Ok(self.bytes(start, length)?.to_vec())
    }

    fn ascii(&mut self, offset: usize, info: u8) -> Result<String> {
        let (length, start) = self.length(offset, info)?;
        let bytes = self.bytes(start, length)?;
        if !bytes.is_ascii() {
            return Err(Error::invalid("Invalid binary plist ASCII string"));
        }
        self.budget.consume(length)?;
        String::from_utf8(bytes.to_vec())
            .map_err(|_| Error::invalid("Invalid binary plist ASCII string"))
    }

    fn utf8(&mut self, offset: usize, info: u8) -> Result<String> {
        let (length, start) = self.length(offset, info)?;
        let bytes = self.bytes(start, length)?;
        self.budget.consume(length)?;
        std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| Error::invalid("Invalid binary plist UTF-8 string"))
    }

    fn utf16(&mut self, offset: usize, info: u8) -> Result<String> {
        let (length, start) = self.length(offset, info)?;
        let byte_length = length
            .checked_mul(2)
            .ok_or_else(|| Error::invalid("Invalid binary plist UTF-16 string"))?;
        let bytes = self.bytes(start, byte_length)?;
        self.budget.consume(byte_length)?;
        let units = bytes
            .as_chunks::<2>()
            .0
            .iter()
            .copied()
            .map(u16::from_be_bytes);
        char::decode_utf16(units)
            .collect::<std::result::Result<String, _>>()
            .map_err(|_| Error::invalid("Invalid binary plist UTF-16 string"))
    }

    fn array(&mut self, offset: usize, info: u8) -> Result<Vec<Value>> {
        let (length, start) = self.length(offset, info)?;
        let byte_length = length
            .checked_mul(self.reference_width)
            .ok_or_else(|| Error::invalid("Invalid binary plist array"))?;
        self.bytes(start, byte_length)?;
        self.budget.consume(length)?;
        let mut values = Vec::new();
        values
            .try_reserve_exact(length)
            .map_err(|_| Error::invalid(EXPANSION_ERROR))?;
        for index in 0..length {
            let position = indexed_position(start, index, self.reference_width)?;
            let reference = self.reference(position)?;
            values.push(self.read_object(reference)?);
        }
        Ok(values)
    }

    fn dictionary(&mut self, offset: usize, info: u8) -> Result<Dictionary> {
        let (length, keys_start) = self.length(offset, info)?;
        let section_length = length
            .checked_mul(self.reference_width)
            .ok_or_else(|| Error::invalid("Invalid binary plist dictionary"))?;
        let values_start = keys_start
            .checked_add(section_length)
            .ok_or_else(|| Error::invalid("Invalid binary plist dictionary"))?;
        let total_length = section_length
            .checked_mul(2)
            .ok_or_else(|| Error::invalid("Invalid binary plist dictionary"))?;
        self.bytes(keys_start, total_length)?;
        self.budget.consume(
            length
                .checked_mul(2)
                .ok_or_else(|| Error::invalid(EXPANSION_ERROR))?,
        )?;

        let mut values = Dictionary::new();
        for index in 0..length {
            let key_position = indexed_position(keys_start, index, self.reference_width)?;
            let value_position = indexed_position(values_start, index, self.reference_width)?;
            let key_reference = self.reference(key_position)?;
            let value_reference = self.reference(value_position)?;
            let Value::String(key) = self.read_object(key_reference)? else {
                return Err(Error::invalid("Invalid binary plist dictionary key"));
            };
            let value = self.read_object(value_reference)?;
            if values.insert(key, value).is_some() {
                return Err(Error::invalid("Duplicate binary plist dictionary key"));
            }
        }
        Ok(values)
    }

    fn length(&self, object_offset: usize, info: u8) -> Result<(usize, usize)> {
        if info < 0x0f {
            return Ok((usize::from(info), object_offset + 1));
        }
        let marker_offset = object_offset
            .checked_add(1)
            .ok_or_else(|| Error::invalid("Invalid binary plist length"))?;
        let marker = self.byte(marker_offset)?;
        if marker >> 4 != 0x1 {
            return Err(Error::invalid("Invalid binary plist length"));
        }
        let width = integer_width(marker & 0x0f)?;
        let length = usize::try_from(self.unsigned(marker_offset + 1, width)?)
            .map_err(|_| Error::invalid("Binary plist length is too large"))?;
        let start = marker_offset
            .checked_add(1 + width)
            .ok_or_else(|| Error::invalid("Invalid binary plist length"))?;
        Ok((length, start))
    }

    fn reference(&self, offset: usize) -> Result<usize> {
        let reference = usize::try_from(self.unsigned(offset, self.reference_width)?)
            .map_err(|_| Error::invalid("Invalid binary plist reference"))?;
        if reference >= self.offsets.len() {
            return Err(Error::invalid("Invalid binary plist reference"));
        }
        Ok(reference)
    }

    fn unsigned(&self, offset: usize, width: usize) -> Result<u64> {
        read_unsigned(self.input, offset, width, self.object_table_end)
    }

    fn byte(&self, offset: usize) -> Result<u8> {
        self.bytes(offset, 1)
            .map(|bytes| bytes[0])
            .map_err(|_| Error::invalid("Truncated binary plist object"))
    }

    fn bytes(&self, offset: usize, length: usize) -> Result<&'a [u8]> {
        let end = offset
            .checked_add(length)
            .filter(|end| *end <= self.object_table_end)
            .ok_or_else(|| Error::invalid("Truncated binary plist object"))?;
        Ok(&self.input[offset..end])
    }
}

struct Budget {
    remaining: usize,
}

impl Budget {
    fn new(remaining: usize) -> Self {
        Self { remaining }
    }

    fn consume(&mut self, amount: usize) -> Result<()> {
        self.remaining = self
            .remaining
            .checked_sub(amount)
            .ok_or_else(|| Error::invalid(EXPANSION_ERROR))?;
        Ok(())
    }
}

fn integer_width(info: u8) -> Result<usize> {
    if info > 3 {
        return Err(Error::invalid("Unsupported binary plist integer width"));
    }
    Ok(1usize << info)
}

fn indexed_position(start: usize, index: usize, width: usize) -> Result<usize> {
    start
        .checked_add(
            index
                .checked_mul(width)
                .ok_or_else(|| Error::invalid("Invalid binary plist reference table"))?,
        )
        .ok_or_else(|| Error::invalid("Invalid binary plist reference table"))
}

fn read_usize(input: &[u8], offset: usize, width: usize, end: usize) -> Result<usize> {
    usize::try_from(read_unsigned(input, offset, width, end)?)
        .map_err(|_| Error::invalid("Binary plist integer is too large"))
}

fn read_unsigned(input: &[u8], offset: usize, width: usize, limit: usize) -> Result<u64> {
    if width == 0 || width > 8 {
        return Err(Error::invalid("Unsupported binary plist integer width"));
    }
    let end = offset
        .checked_add(width)
        .filter(|end| *end <= limit && *end <= input.len())
        .ok_or_else(|| Error::invalid("Truncated binary plist integer"))?;
    Ok(input[offset..end]
        .iter()
        .fold(0u64, |value, byte| (value << 8) | u64::from(*byte)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_supported_binary_plist_values() {
        let objects = vec![
            ascii("root"),
            vec![0x80, 42],
            vec![0x43, 1, 2, 3],
            vec![0x10, 7],
            real(2.5),
            vec![0x09],
            vec![0x00],
            date(1.25),
            vec![0xa7, 1, 2, 3, 4, 5, 6, 7],
            vec![0xd1, 0, 8],
        ];
        let (Value::Dictionary(root), remaining) = parse(&archive(&objects, 9), 1024).unwrap()
        else {
            panic!("expected dictionary");
        };
        assert!(remaining < 1024);
        assert_eq!(
            root["root"],
            Value::Array(vec![
                Value::Uid(42),
                Value::Data(vec![1, 2, 3]),
                Value::Integer(7),
                Value::Real(2.5),
                Value::Boolean(true),
                Value::Null,
                Value::Date(1.25),
            ])
        );
    }

    #[test]
    fn parses_extended_lengths_and_utf16() {
        let mut data = vec![0x4f, 0x10, 16];
        data.extend(0..16);
        let utf16 = vec![0x62, 0x00, b'O', 0x03, 0xa9];
        let objects = vec![data, utf16, vec![0xa2, 0, 1]];
        assert_eq!(
            parse(&archive(&objects, 2), 1024).unwrap().0,
            Value::Array(vec![
                Value::Data((0..16).collect()),
                Value::String("OΩ".to_owned()),
            ])
        );
    }

    #[test]
    fn rejects_invalid_binary_plist_structure() {
        assert!(parse(&archive(&[vec![0xa1, 0]], 0), 1024).is_err());
        assert!(parse(&archive(&[vec![0xa1, 1]], 0), 1024).is_err());
        assert!(parse(&archive(&[vec![0x4f, 0x00]], 0), 1024).is_err());
        assert!(parse(&archive(&[vec![0x4f, 0x10, 16, 1]], 0), 1024).is_err());

        let invalid_key = vec![vec![0x10, 1], vec![0x00], vec![0xd1, 0, 1]];
        assert!(parse(&archive(&invalid_key, 2), 1024).is_err());

        let duplicate_key = vec![
            ascii("key"),
            vec![0x10, 1],
            vec![0x10, 2],
            vec![0xd2, 0, 0, 1, 2],
        ];
        assert!(parse(&archive(&duplicate_key, 3), 1024).is_err());

        let mut invalid_offset = archive(&[vec![0x00]], 0);
        let trailer = invalid_offset.len() - TRAILER_LENGTH;
        let offset_table =
            read_usize(&invalid_offset, trailer + 24, 8, invalid_offset.len()).unwrap();
        invalid_offset[offset_table] = 0;
        assert!(parse(&invalid_offset, 1024).is_err());
    }

    #[test]
    fn bounds_nesting_and_expansion() {
        let mut data = vec![0x4f, 0x10, 64];
        data.extend(std::iter::repeat_n(1, 64));
        let mut repeated = vec![0xaf, 0x10, 64];
        repeated.extend(std::iter::repeat_n(0, 64));
        let error = parse(&archive(&[data, repeated], 1), 128).err().unwrap();
        assert_eq!(error.message(), EXPANSION_ERROR);

        let mut nested = Vec::new();
        for index in 0..=MAX_NESTING {
            nested.push(vec![0xa1, (index + 1) as u8]);
        }
        nested.push(vec![0x00]);
        assert!(parse(&archive(&nested, 0), 16 * 1024).is_err());
    }

    fn ascii(value: &str) -> Vec<u8> {
        assert!(value.len() < 15 && value.is_ascii());
        let mut bytes = vec![0x50 | value.len() as u8];
        bytes.extend_from_slice(value.as_bytes());
        bytes
    }

    fn real(value: f64) -> Vec<u8> {
        let mut bytes = vec![0x23];
        bytes.extend_from_slice(&value.to_be_bytes());
        bytes
    }

    fn date(value: f64) -> Vec<u8> {
        let mut bytes = vec![0x33];
        bytes.extend_from_slice(&value.to_be_bytes());
        bytes
    }

    fn archive(objects: &[Vec<u8>], root: u8) -> Vec<u8> {
        assert!(!objects.is_empty() && objects.len() <= usize::from(u8::MAX));
        let mut bytes = HEADER.to_vec();
        let mut offsets = Vec::with_capacity(objects.len());
        for object in objects {
            offsets.push(bytes.len());
            bytes.extend_from_slice(object);
        }
        let offset_table = bytes.len();
        let offset_width = if offset_table < 256 { 1 } else { 2 };
        for offset in offsets {
            append_unsigned(&mut bytes, offset as u64, offset_width);
        }
        bytes.extend_from_slice(&[0; 6]);
        bytes.push(offset_width as u8);
        bytes.push(1);
        append_unsigned(&mut bytes, objects.len() as u64, 8);
        append_unsigned(&mut bytes, u64::from(root), 8);
        append_unsigned(&mut bytes, offset_table as u64, 8);
        bytes
    }

    fn append_unsigned(bytes: &mut Vec<u8>, value: u64, width: usize) {
        for shift in (0..width).rev() {
            bytes.push((value >> (shift * 8)) as u8);
        }
    }
}
