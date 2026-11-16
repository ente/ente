struct Measured {
    top_percent: f64,
    minimum_files: u32,
}

const MEASURED: [Measured; 4] = [
    Measured {
        top_percent: 1.0,
        minimum_files: 15_059,
    },
    Measured {
        top_percent: 5.0,
        minimum_files: 8_063,
    },
    Measured {
        top_percent: 10.0,
        minimum_files: 4_916,
    },
    Measured {
        top_percent: 25.0,
        minimum_files: 2_765,
    },
];

const WIDEST_SHOWN_PERCENT: u32 = 19;
const ROUNDING_SLACK: f64 = 1e-9;

pub(super) fn top_percent(files: u32) -> Option<u32> {
    if files >= MEASURED[0].minimum_files {
        return Some(1);
    }
    let percent = MEASURED.windows(2).find_map(|pair| match pair {
        [above, below] if files >= below.minimum_files => {
            Some(interpolated_percent(above, below, files))
        }
        _ => None,
    })?;
    let rounded_up = (percent - ROUNDING_SLACK).ceil().max(1.0) as u32;
    (rounded_up <= WIDEST_SHOWN_PERCENT).then_some(rounded_up)
}

fn interpolated_percent(above: &Measured, below: &Measured, files: u32) -> f64 {
    let ln_files = |files: u32| f64::from(files).ln();
    let share = (ln_files(above.minimum_files) - ln_files(files))
        / (ln_files(above.minimum_files) - ln_files(below.minimum_files));
    let ln_percent =
        above.top_percent.ln() + share * (below.top_percent.ln() - above.top_percent.ln());
    ln_percent.exp()
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::{MEASURED, WIDEST_SHOWN_PERCENT, top_percent};

    #[test]
    fn each_measured_library_size_earns_its_own_percent() {
        for measured in &MEASURED[..3] {
            assert_eq!(
                top_percent(measured.minimum_files),
                Some(measured.top_percent as u32)
            );
        }
    }

    #[test]
    fn libraries_between_measurements_round_up_to_a_whole_percent() {
        assert_eq!(top_percent(1_000_000), Some(1));
        assert_eq!(top_percent(15_058), Some(2));
        assert_eq!(top_percent(8_062), Some(6));
        assert_eq!(top_percent(6_000), Some(8));
        assert_eq!(top_percent(4_915), Some(11));
    }

    #[test]
    fn more_files_earn_every_whole_percent_from_nineteen_down_to_one() {
        let shown: Vec<u32> = (0..=20_000).filter_map(top_percent).collect();
        assert!(shown.windows(2).all(|pair| pair[0] >= pair[1]));
        let distinct: BTreeSet<u32> = shown.into_iter().collect();
        assert_eq!(distinct, (1..=WIDEST_SHOWN_PERCENT).collect());
    }

    #[test]
    fn only_the_top_nineteen_percent_are_shown() {
        let smallest_shown = (0..=20_000)
            .find(|&files| top_percent(files).is_some())
            .unwrap();
        assert_eq!(top_percent(smallest_shown), Some(WIDEST_SHOWN_PERCENT));
        assert_eq!(top_percent(smallest_shown - 1), None);
        assert_eq!(top_percent(2_765), None);
        assert_eq!(top_percent(0), None);
    }
}
