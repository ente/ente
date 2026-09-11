use super::{Error, Result};

const EVECTOR_VALUES_PACKED_KEY: u32 = 0x0A;
const EVECTOR_VALUES_FIXED64_KEY: u32 = 0x09;
const MAX_GROUP_DEPTH: usize = 100;

pub fn encode_evector(values: &[f64]) -> Vec<u8> {
    if values.is_empty() {
        return Vec::new();
    }
    let mut bytes = Vec::with_capacity(values.len() * 8 + 10);
    bytes.push(EVECTOR_VALUES_PACKED_KEY as u8);
    push_varint(&mut bytes, (values.len() * 8) as u64);
    for value in values {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    bytes
}

pub fn decode_evector(bytes: &[u8]) -> Result<Vec<f64>> {
    let mut values = Vec::new();
    let mut offset = 0;
    while offset < bytes.len() {
        let key = read_key(bytes, &mut offset)?;
        match key {
            EVECTOR_VALUES_PACKED_KEY => {
                let length = read_length(bytes, &mut offset)?;
                if length % 8 != 0 {
                    return Err(malformed());
                }
                for chunk in bytes[offset..offset + length].as_chunks::<8>().0 {
                    values.push(f64::from_le_bytes(*chunk));
                }
                offset += length;
            }
            EVECTOR_VALUES_FIXED64_KEY => {
                let end = advance(bytes, &mut offset, 8)?;
                values.push(f64_from_le(&bytes[end - 8..end]));
            }
            _ if key >> 3 == 1 => return Err(malformed()),
            _ => skip_field(key, bytes, &mut offset, MAX_GROUP_DEPTH)?,
        }
    }
    Ok(values)
}

pub fn encode_f32(values: impl IntoIterator<Item = f32>) -> Vec<u8> {
    values.into_iter().flat_map(f32::to_le_bytes).collect()
}

pub fn decode_f32(bytes: &[u8]) -> Vec<f32> {
    bytes
        .as_chunks::<4>()
        .0
        .iter()
        .map(|chunk| f32::from_le_bytes(*chunk))
        .collect()
}

fn f64_from_le(chunk: &[u8]) -> f64 {
    let mut buffer = [0u8; 8];
    buffer.copy_from_slice(chunk);
    f64::from_le_bytes(buffer)
}

fn push_varint(bytes: &mut Vec<u8>, mut value: u64) {
    while value >= 0x80 {
        bytes.push((value as u8) | 0x80);
        value >>= 7;
    }
    bytes.push(value as u8);
}

fn read_key(bytes: &[u8], offset: &mut usize) -> Result<u32> {
    let key = u32::try_from(read_varint(bytes, offset)?).map_err(|_| malformed())?;
    if key >> 3 == 0 || key & 7 > 5 {
        return Err(malformed());
    }
    Ok(key)
}

fn skip_field(key: u32, bytes: &[u8], offset: &mut usize, remaining_depth: usize) -> Result<()> {
    if remaining_depth == 0 {
        return Err(malformed());
    }
    match key & 7 {
        0 => {
            read_varint(bytes, offset)?;
        }
        1 => {
            advance(bytes, offset, 8)?;
        }
        2 => {
            let length = read_length(bytes, offset)?;
            *offset += length;
        }
        3 => loop {
            let inner_key = read_key(bytes, offset)?;
            if inner_key & 7 == 4 {
                if inner_key >> 3 != key >> 3 {
                    return Err(malformed());
                }
                break;
            }
            skip_field(inner_key, bytes, offset, remaining_depth - 1)?;
        },
        5 => {
            advance(bytes, offset, 4)?;
        }
        _ => return Err(malformed()),
    }
    Ok(())
}

fn read_varint(bytes: &[u8], offset: &mut usize) -> Result<u64> {
    let mut value = 0u64;
    for shift in (0..64).step_by(7) {
        let byte = *bytes.get(*offset).ok_or_else(malformed)?;
        *offset += 1;
        if shift == 63 && byte > 1 {
            return Err(malformed());
        }
        value |= u64::from(byte & 0x7F) << shift;
        if byte & 0x80 == 0 {
            return Ok(value);
        }
    }
    Err(malformed())
}

fn read_length(bytes: &[u8], offset: &mut usize) -> Result<usize> {
    let length = usize::try_from(read_varint(bytes, offset)?).map_err(|_| malformed())?;
    if bytes.len() - *offset < length {
        return Err(malformed());
    }
    Ok(length)
}

fn advance(bytes: &[u8], offset: &mut usize, count: usize) -> Result<usize> {
    if bytes.len() - *offset < count {
        return Err(malformed());
    }
    *offset += count;
    Ok(*offset)
}

fn malformed() -> Error {
    Error::Codec("malformed EVector bytes".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evector_matches_protobuf_packed_encoding() {
        let bytes = encode_evector(&[1.0, 2.0]);
        assert_eq!(
            bytes,
            [
                0x0A, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x40
            ]
        );
        assert_eq!(decode_evector(&bytes).unwrap(), vec![1.0, 2.0]);
    }

    #[test]
    fn empty_evector_is_zero_bytes() {
        assert!(encode_evector(&[]).is_empty());
        assert!(decode_evector(&[]).unwrap().is_empty());
    }

    #[test]
    fn evector_round_trips_long_vectors() {
        let values: Vec<f64> = (0..192).map(|i| i as f64 * 0.25 - 3.0).collect();
        let bytes = encode_evector(&values);
        assert_eq!(bytes[0], 0x0A);
        assert_eq!(&bytes[1..3], &[0x80, 0x0C]);
        assert_eq!(decode_evector(&bytes).unwrap(), values);
    }

    #[test]
    fn evector_accepts_unpacked_and_unknown_fields() {
        let mut bytes = vec![0x09];
        bytes.extend_from_slice(&3.5f64.to_le_bytes());
        bytes.extend_from_slice(&[0x10, 0x05]);
        bytes.extend_from_slice(&[0x1A, 0x02, 0xAA, 0xBB]);
        bytes.extend_from_slice(&[0x25, 1, 2, 3, 4]);
        bytes.extend_from_slice(&[0x09]);
        bytes.extend_from_slice(&(-1.0f64).to_le_bytes());
        assert_eq!(decode_evector(&bytes).unwrap(), vec![3.5, -1.0]);
    }

    #[test]
    fn evector_rejects_truncated_bytes() {
        assert!(decode_evector(&[0x0A, 0x10, 0x00]).is_err());
        assert!(decode_evector(&[0x0A, 0x04, 0, 0, 0, 0]).is_err());
        assert!(decode_evector(&[0x0F]).is_err());
        for bytes in [
            &[0x09, 0, 0, 0, 0, 0, 0, 0][..],
            &[0x10],
            &[0x11, 0, 0, 0, 0, 0, 0, 0],
            &[0x12, 2, 0],
            &[0x15, 0, 0, 0],
        ] {
            assert!(decode_evector(bytes).is_err(), "{bytes:?}");
        }
    }

    #[test]
    fn evector_concatenates_packed_and_unpacked_values() {
        let mut bytes = encode_evector(&[1.0, 2.0]);
        bytes.extend([0x10, 0x05, 0x09]);
        bytes.extend(3.0f64.to_le_bytes());
        bytes.extend([0x0A, 0]);
        bytes.extend(encode_evector(&[4.0, 5.0]));
        assert_eq!(decode_evector(&bytes).unwrap(), [1.0, 2.0, 3.0, 4.0, 5.0]);
    }

    #[test]
    fn evector_preserves_float_bits() {
        let bits = [
            0,
            1,
            0x8000_0000_0000_0000,
            0x7FF0_0000_0000_0000,
            0xFFF0_0000_0000_0000,
            0x7FF8_0000_0000_0042,
        ];
        let values: Vec<f64> = bits.into_iter().map(f64::from_bits).collect();
        let decoded = decode_evector(&encode_evector(&values)).unwrap();
        assert_eq!(
            decoded.into_iter().map(f64::to_bits).collect::<Vec<_>>(),
            bits
        );
    }

    #[test]
    fn evector_rejects_invalid_keys() {
        for bytes in [
            &[0, 0][..],
            &[0x02, 0],
            &[0x16],
            &[0x17],
            &[0x80, 0x80, 0x80, 0x80, 0x10, 0],
        ] {
            assert!(decode_evector(bytes).is_err(), "{bytes:?}");
        }
        assert!(
            decode_evector(&[0xF8, 0xFF, 0xFF, 0xFF, 0x0F, 0])
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn evector_rejects_incorrect_value_wire_types() {
        for bytes in [&[0x08, 0][..], &[0x0B, 0x0C], &[0x0C], &[0x0D, 0, 0, 0, 0]] {
            assert!(decode_evector(bytes).is_err(), "{bytes:?}");
        }
    }

    #[test]
    fn evector_checks_varint_limits() {
        let mut maximum = vec![0x10];
        maximum.extend([0xFF; 9]);
        maximum.push(1);
        assert!(decode_evector(&maximum).unwrap().is_empty());

        let mut overflowing = vec![0x80; 9];
        overflowing.push(2);
        for invalid in [vec![0x80; 9], vec![0x80; 10], overflowing] {
            for prefix in [&[][..], &[0x0A][..], &[0x10][..], &[0x12][..]] {
                let mut bytes = prefix.to_vec();
                bytes.extend(&invalid);
                assert!(decode_evector(&bytes).is_err(), "{bytes:?}");
            }
        }

        for key in [0x0A, 0x12] {
            maximum[0] = key;
            assert!(decode_evector(&maximum).is_err());
        }
    }

    #[test]
    fn evector_skips_nested_unknown_groups() {
        let mut bytes = encode_evector(&[1.0]);
        bytes.extend([0x13, 0x09]);
        bytes.extend(99.0f64.to_le_bytes());
        bytes.extend([0x1B, 0x08, 1, 0x25, 1, 2, 3, 4, 0x29]);
        bytes.extend([0; 8]);
        bytes.extend([0x32, 2, 0xAA, 0xBB, 0x1C, 0x14]);
        bytes.extend(encode_evector(&[2.0]));
        assert_eq!(decode_evector(&bytes).unwrap(), [1.0, 2.0]);
    }

    #[test]
    fn evector_rejects_invalid_groups() {
        for bytes in [
            &[0x14][..],
            &[0x13],
            &[0x13, 0x1C],
            &[0x13, 0x1B, 0x14, 0x1C],
            &[0x13, 0x10, 0, 0x14, 0x14],
            &[0x13, 0, 0, 0x14],
        ] {
            assert!(decode_evector(bytes).is_err(), "{bytes:?}");
        }
    }

    #[test]
    fn evector_limits_group_nesting() {
        let nested = |depth, with_value| {
            let mut bytes = vec![0x13; depth];
            if with_value {
                bytes.extend([0x10, 0]);
            }
            bytes.extend(vec![0x14; depth]);
            bytes
        };
        assert!(decode_evector(&nested(99, true)).unwrap().is_empty());
        assert!(decode_evector(&nested(100, false)).unwrap().is_empty());
        assert!(decode_evector(&nested(100, true)).is_err());
        assert!(decode_evector(&nested(101, false)).is_err());
    }

    #[test]
    fn f32_matches_little_endian_layout() {
        assert_eq!(encode_f32([1.0f32]), [0x00, 0x00, 0x80, 0x3F]);
        assert_eq!(decode_f32(&[0x00, 0x00, 0x80, 0x3F]), vec![1.0f32]);
        assert!(encode_f32([]).is_empty());
        assert!(decode_f32(&[]).is_empty());
    }

    #[test]
    fn f32_round_trips_and_ignores_trailing_bytes() {
        let values = vec![0.5f32, -2.25, 1e-7];
        let mut bytes = encode_f32(values.iter().copied());
        assert_eq!(decode_f32(&bytes), values);
        bytes.push(0xFF);
        assert_eq!(decode_f32(&bytes), values);
    }
}
