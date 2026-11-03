use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};

use crate::allocator;

pub(crate) struct MemoryBudget {
    limit: isize,
    used: AtomicIsize,
    exceeded: AtomicBool,
}

impl MemoryBudget {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            limit: signed(limit),
            used: AtomicIsize::new(0),
            exceeded: AtomicBool::new(false),
        }
    }

    pub(crate) fn enter<T>(&self, work: impl FnOnce() -> T) -> T {
        allocator::with_budget(self, work)
    }

    pub(crate) fn suspend<T>(work: impl FnOnce() -> T) -> T {
        allocator::without_budget(work)
    }

    pub(crate) fn charge(&self, bytes: usize) {
        let bytes = signed(bytes);
        let used = self
            .used
            .fetch_add(bytes, Ordering::Relaxed)
            .saturating_add(bytes);
        if used > self.limit {
            self.exceeded.store(true, Ordering::Relaxed);
        }
    }

    pub(crate) fn release(&self, bytes: usize) {
        self.used.fetch_sub(signed(bytes), Ordering::Relaxed);
    }

    pub(crate) fn is_exceeded(&self) -> bool {
        self.exceeded.load(Ordering::Relaxed)
    }
}

fn signed(bytes: usize) -> isize {
    isize::try_from(bytes).unwrap_or(isize::MAX)
}

#[cfg(test)]
mod tests {
    use std::{hint::black_box, sync::atomic::Ordering};

    use super::MemoryBudget;

    fn used_bytes(budget: &MemoryBudget) -> isize {
        budget.used.load(Ordering::Relaxed)
    }

    #[test]
    fn allocations_past_the_limit_succeed_and_exceed_the_budget() {
        let budget = MemoryBudget::new(1 << 20);
        let exceeded = budget.enter(|| {
            let _within = black_box(vec![0u8; 1 << 20]);
            let at_limit = budget.is_exceeded();
            let _beyond = black_box(vec![0u8; 1]);
            (at_limit, budget.is_exceeded())
        });

        assert_eq!(exceeded, (false, true));
    }

    #[test]
    fn stays_exceeded_after_usage_drops_back_under_the_limit() {
        let budget = MemoryBudget::new(0);
        budget.enter(|| drop(black_box(vec![0u8; 1])));

        assert_eq!(used_bytes(&budget), 0);
        assert!(budget.is_exceeded());
    }

    #[test]
    fn frees_return_their_bytes_to_the_budget() {
        let budget = MemoryBudget::new(usize::MAX);
        let used = budget.enter(|| {
            let block = black_box(vec![0u8; 1 << 20]);
            let held = used_bytes(&budget);
            drop(block);
            (held, used_bytes(&budget))
        });

        assert_eq!(used, (1 << 20, 0));
    }

    #[test]
    fn reallocations_charge_growth_and_release_shrinkage() {
        let budget = MemoryBudget::new(usize::MAX);
        let used = budget.enter(|| {
            let mut block = black_box(Vec::<u8>::with_capacity(1024));
            block.reserve_exact(4096);
            let grown = used_bytes(&budget);
            block.shrink_to(512);
            let shrunk = used_bytes(&budget);
            drop(block);
            (grown, shrunk, used_bytes(&budget))
        });

        assert_eq!(used, (4096, 512, 0));
    }

    #[test]
    fn charges_only_allocations_inside_the_scope() {
        let budget = MemoryBudget::new(usize::MAX);
        let _unscoped = black_box(vec![0u8; 1 << 20]);
        let _suspended = budget.enter(|| MemoryBudget::suspend(|| black_box(vec![0u8; 1 << 20])));

        assert_eq!(used_bytes(&budget), 0);
    }
}
