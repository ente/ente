struct Threshold {
    top_per_mille: u32,
    minimum_files: u32,
}

const TOP_PERCENT_THRESHOLDS: [Threshold; 4] = [
    Threshold {
        top_per_mille: 1,
        minimum_files: 39_123,
    },
    Threshold {
        top_per_mille: 10,
        minimum_files: 15_059,
    },
    Threshold {
        top_per_mille: 50,
        minimum_files: 8_063,
    },
    Threshold {
        top_per_mille: 100,
        minimum_files: 4_916,
    },
];

pub(super) fn top_per_mille(files: u32) -> Option<u32> {
    TOP_PERCENT_THRESHOLDS
        .iter()
        .find(|threshold| files >= threshold.minimum_files)
        .map(|threshold| threshold.top_per_mille)
}

#[cfg(test)]
mod tests {
    use super::{TOP_PERCENT_THRESHOLDS, top_per_mille};

    #[test]
    fn each_threshold_earns_its_own_band_and_fewer_files_earn_none() {
        for threshold in &TOP_PERCENT_THRESHOLDS {
            assert_eq!(
                top_per_mille(threshold.minimum_files),
                Some(threshold.top_per_mille)
            );
        }
        let lowest = TOP_PERCENT_THRESHOLDS
            .iter()
            .map(|threshold| threshold.minimum_files)
            .min()
            .unwrap();
        assert_eq!(top_per_mille(lowest - 1), None);
    }

    #[test]
    fn the_real_bands_match_the_measured_library_sizes() {
        assert_eq!(top_per_mille(39_123), Some(1));
        assert_eq!(top_per_mille(39_122), Some(10));
        assert_eq!(top_per_mille(5_347), Some(100));
        assert_eq!(top_per_mille(4_916), Some(100));
        assert_eq!(top_per_mille(4_915), None);
    }
}
