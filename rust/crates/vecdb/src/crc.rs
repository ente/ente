const POLYNOMIAL: u32 = 0xEDB8_8320;
const INITIAL_STATE: u32 = 0xFFFF_FFFF;

const TABLES: [[u32; 256]; 8] = build_tables();

const fn build_tables() -> [[u32; 256]; 8] {
    let mut tables = [[0u32; 256]; 8];
    let mut byte = 0usize;
    while byte < 256 {
        let mut crc = byte as u32;
        let mut bit = 0;
        while bit < 8 {
            crc = (crc >> 1) ^ (POLYNOMIAL * (crc & 1));
            bit += 1;
        }
        tables[0][byte] = crc;
        byte += 1;
    }
    let mut byte = 0usize;
    while byte < 256 {
        let mut crc = tables[0][byte];
        let mut stride = 1;
        while stride < 8 {
            crc = tables[0][(crc & 0xFF) as usize] ^ (crc >> 8);
            tables[stride][byte] = crc;
            stride += 1;
        }
        byte += 1;
    }
    tables
}

pub(crate) fn crc32(bytes: &[u8]) -> u32 {
    update_state(INITIAL_STATE, bytes) ^ INITIAL_STATE
}

pub(crate) struct Crc32 {
    state: u32,
}

impl Crc32 {
    pub(crate) fn new() -> Self {
        Self {
            state: INITIAL_STATE,
        }
    }

    pub(crate) fn update(&mut self, bytes: &[u8]) {
        self.state = update_state(self.state, bytes);
    }

    pub(crate) fn finalize(self) -> u32 {
        self.state ^ INITIAL_STATE
    }
}

fn update_state(state: u32, bytes: &[u8]) -> u32 {
    let (chunks, tail) = bytes.as_chunks::<8>();
    let mut state = state;
    for chunk in chunks {
        let low = state ^ u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        state = TABLES[7][(low & 0xFF) as usize]
            ^ TABLES[6][((low >> 8) & 0xFF) as usize]
            ^ TABLES[5][((low >> 16) & 0xFF) as usize]
            ^ TABLES[4][(low >> 24) as usize]
            ^ TABLES[3][chunk[4] as usize]
            ^ TABLES[2][chunk[5] as usize]
            ^ TABLES[1][chunk[6] as usize]
            ^ TABLES[0][chunk[7] as usize];
    }
    for &byte in tail {
        state = TABLES[0][((state ^ byte as u32) & 0xFF) as usize] ^ (state >> 8);
    }
    state
}

#[cfg(test)]
mod tests {
    use super::super::kernel::splitmix64;
    use super::*;

    fn bitwise_crc32(bytes: &[u8]) -> u32 {
        let mut crc = INITIAL_STATE;
        for &byte in bytes {
            crc ^= byte as u32;
            for _ in 0..8 {
                crc = (crc >> 1) ^ (POLYNOMIAL * (crc & 1));
            }
        }
        crc ^ INITIAL_STATE
    }

    fn seeded_bytes(seed: u64, len: usize) -> Vec<u8> {
        let mut state = seed;
        (0..len).map(|_| splitmix64(&mut state) as u8).collect()
    }

    #[test]
    fn matches_the_standard_check_value() {
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }

    #[test]
    fn empty_input_hashes_to_zero() {
        assert_eq!(crc32(&[]), 0);
        assert_eq!(Crc32::new().finalize(), 0);
    }

    #[test]
    fn agrees_with_bitwise_reference_across_lengths_and_offsets() {
        let buffer = seeded_bytes(0x00C1_0000, 608);
        for len in 0..600usize {
            for offset in 0..8usize {
                let slice = &buffer[offset..offset + len];
                assert_eq!(
                    crc32(slice),
                    bitwise_crc32(slice),
                    "len {len} offset {offset}"
                );
            }
        }
    }

    #[test]
    fn split_updates_match_one_shot_at_every_boundary() {
        let bytes = seeded_bytes(0x00C3_0000, 100);
        let whole = crc32(&bytes);
        for split in 0..=bytes.len() {
            let mut hasher = Crc32::new();
            hasher.update(&bytes[..split]);
            hasher.update(&bytes[split..]);
            assert_eq!(hasher.finalize(), whole, "split at {split}");
        }
    }
}
