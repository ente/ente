pub(super) struct Rng {
    state: u64,
}

impl Rng {
    pub(super) fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub(super) fn shuffle<T>(&mut self, items: &mut [T]) {
        for index in (1..items.len()).rev() {
            items.swap(index, self.below(index + 1));
        }
    }

    pub(super) fn below(&mut self, bound: usize) -> usize {
        ((u128::from(self.next_u64()) * bound as u128) >> 64) as usize
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut value = self.state;
        value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        value ^ (value >> 31)
    }
}

#[cfg(test)]
mod tests {
    use super::Rng;

    fn shuffled(seed: u64) -> Vec<u32> {
        let mut items: Vec<u32> = (0..50).collect();
        Rng::new(seed).shuffle(&mut items);
        items
    }

    #[test]
    fn shuffles_are_permutations_determined_by_the_seed() {
        let first = shuffled(7);
        let mut sorted = first.clone();
        sorted.sort_unstable();
        assert_eq!(sorted, (0..50).collect::<Vec<_>>());
        assert_eq!(first, shuffled(7));
        assert_ne!(first, shuffled(8));
    }
}
