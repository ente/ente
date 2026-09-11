use std::ops::Range;

// For field ranges already checked by the index validators.
pub(crate) struct ByteReader<'a> {
    bytes: &'a [u8],
}

impl<'a> ByteReader<'a> {
    pub(crate) fn at(bytes: &'a [u8], offset: usize) -> Self {
        Self {
            bytes: &bytes[offset..],
        }
    }

    fn array<const N: usize>(&mut self) -> [u8; N] {
        #[expect(
            clippy::expect_used,
            reason = "Index validators check field ranges before ByteReader is used"
        )]
        let (value, rest) = self
            .bytes
            .split_first_chunk::<N>()
            .expect("validated binary field");
        self.bytes = rest;
        *value
    }

    pub(crate) fn byte(&mut self) -> u8 {
        self.array::<1>()[0]
    }

    pub(crate) fn u16(&mut self) -> u16 {
        u16::from_le_bytes(self.array())
    }

    pub(crate) fn u24(&mut self) -> u32 {
        let [a, b, c] = self.array();
        u32::from_le_bytes([a, b, c, 0])
    }

    pub(crate) fn u32(&mut self) -> u32 {
        u32::from_le_bytes(self.array())
    }

    pub(crate) fn u64(&mut self) -> u64 {
        u64::from_le_bytes(self.array())
    }

    pub(crate) fn f32(&mut self) -> f32 {
        f32::from_le_bytes(self.array())
    }
}

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
