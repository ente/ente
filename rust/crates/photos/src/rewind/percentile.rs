struct Threshold {
    top_percent: u32,
    minimum_files: u32,
}

const PLACEHOLDER_TOP_PERCENT_THRESHOLDS: [Threshold; 3] = [
    Threshold {
        top_percent: 1,
        minimum_files: 12_000,
    },
    Threshold {
        top_percent: 10,
        minimum_files: 4_000,
    },
    Threshold {
        top_percent: 25,
        minimum_files: 1_500,
    },
];

pub(super) fn top_percent(files: u32) -> Option<u32> {
    PLACEHOLDER_TOP_PERCENT_THRESHOLDS
        .iter()
        .find(|threshold| files >= threshold.minimum_files)
        .map(|threshold| threshold.top_percent)
}

#[cfg(test)]
mod tests {
    use super::{PLACEHOLDER_TOP_PERCENT_THRESHOLDS, top_percent};

    #[test]
    fn each_threshold_earns_its_own_band_and_fewer_files_earn_none() {
        for threshold in &PLACEHOLDER_TOP_PERCENT_THRESHOLDS {
            assert_eq!(
                top_percent(threshold.minimum_files),
                Some(threshold.top_percent)
            );
        }
        let lowest = PLACEHOLDER_TOP_PERCENT_THRESHOLDS
            .iter()
            .map(|threshold| threshold.minimum_files)
            .min()
            .unwrap();
        assert_eq!(top_percent(lowest - 1), None);
    }
}
