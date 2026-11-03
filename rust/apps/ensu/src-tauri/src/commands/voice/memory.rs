use super::platform::{self, Memory};

const GIB: u64 = 1024 * 1024 * 1024;

fn should_release(memory: Memory, preparing: bool) -> bool {
    memory.pressure
        || memory
            .available
            .is_some_and(|bytes| bytes < if preparing { 2 * GIB } else { GIB / 2 })
}

pub(super) fn release_chat_model(preparing: bool) -> bool {
    should_release(platform::memory(), preparing)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_warm_models_until_headroom_is_low_or_pressure_is_reported() {
        for preparing in [false, true] {
            assert!(!should_release(
                Memory {
                    available: Some(4 * GIB),
                    pressure: false
                },
                preparing
            ));
            assert!(!should_release(Memory::default(), preparing));
            assert!(should_release(
                Memory {
                    available: Some(8 * GIB),
                    pressure: true
                },
                preparing
            ));
            assert!(should_release(
                Memory {
                    available: Some(GIB / 4),
                    pressure: false
                },
                preparing
            ));
        }
        assert!(should_release(
            Memory {
                available: Some(GIB),
                pressure: false
            },
            true
        ));
        assert!(!should_release(
            Memory {
                available: Some(GIB),
                pressure: false
            },
            false
        ));
    }
}
