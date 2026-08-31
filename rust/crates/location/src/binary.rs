use std::ops::Range;

pub(crate) fn array<const N: usize>(bytes: &[u8], offset: usize) -> Option<[u8; N]> {
    bytes.get(offset..offset.checked_add(N)?)?.try_into().ok()
}

pub(crate) fn u16_at(bytes: &[u8], offset: usize) -> Option<u16> {
    Some(u16::from_le_bytes(array(bytes, offset)?))
}

pub(crate) fn u24_at(bytes: &[u8], offset: usize) -> Option<u32> {
    let [a, b, c] = array(bytes, offset)?;
    Some(u32::from_le_bytes([a, b, c, 0]))
}

pub(crate) fn u32_at(bytes: &[u8], offset: usize) -> Option<u32> {
    Some(u32::from_le_bytes(array(bytes, offset)?))
}

pub(crate) fn f32_at(bytes: &[u8], offset: usize) -> Option<f32> {
    Some(f32::from_le_bytes(array(bytes, offset)?))
}

pub(crate) fn range(offset: usize, count: usize, stride: usize) -> Option<Range<usize>> {
    Some(offset..offset.checked_add(count.checked_mul(stride)?)?)
}
