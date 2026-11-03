use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};

use crate::allocator;

const MIN_REFUSABLE_BYTES: usize = 64 * 1024;

pub(crate) struct MemoryBudget {
    limit: isize,
    used: AtomicIsize,
    refused: AtomicBool,
}

impl MemoryBudget {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            limit: isize::try_from(limit).unwrap_or(isize::MAX),
            used: AtomicIsize::new(0),
            refused: AtomicBool::new(false),
        }
    }

    pub(crate) fn enter<T>(&self, work: impl FnOnce() -> T) -> T {
        allocator::with_budget(self, work)
    }

    pub(crate) fn suspend<T>(work: impl FnOnce() -> T) -> T {
        allocator::without_budget(work)
    }

    pub(crate) fn reserve(&self, bytes: usize, request: usize) -> bool {
        let bytes = signed(bytes);
        let used = self
            .used
            .fetch_add(bytes, Ordering::Relaxed)
            .saturating_add(bytes);
        if request >= MIN_REFUSABLE_BYTES
            && used > self.limit
            && !self.refused.swap(true, Ordering::Relaxed)
        {
            self.used.fetch_sub(bytes, Ordering::Relaxed);
            return false;
        }
        true
    }

    pub(crate) fn release(&self, bytes: usize) {
        self.used.fetch_sub(signed(bytes), Ordering::Relaxed);
    }
}

fn signed(bytes: usize) -> isize {
    isize::try_from(bytes).unwrap_or(isize::MAX)
}

#[cfg(test)]
mod tests {
    use std::{hint::black_box, sync::atomic::Ordering};

    use super::{MIN_REFUSABLE_BYTES, MemoryBudget};

    fn try_allocate(bytes: usize) -> Option<Vec<u8>> {
        let mut block = Vec::new();
        block.try_reserve_exact(bytes).ok()?;
        Some(black_box(block))
    }

    fn used_bytes(budget: &MemoryBudget) -> isize {
        budget.used.load(Ordering::Relaxed)
    }

    #[test]
    fn refuses_a_large_allocation_that_exceeds_the_limit() {
        let budget = MemoryBudget::new(1 << 20);
        let allocated = budget.enter(|| {
            let within = try_allocate(1 << 20);
            let beyond = try_allocate(MIN_REFUSABLE_BYTES);
            (within.is_some(), beyond.is_some())
        });

        assert_eq!(allocated, (true, false));
    }

    #[test]
    fn never_refuses_small_allocations() {
        let budget = MemoryBudget::new(0);

        assert!(budget.enter(|| try_allocate(MIN_REFUSABLE_BYTES - 1).is_some()));
    }

    #[test]
    fn refuses_only_the_first_large_allocation_past_the_limit() {
        let budget = MemoryBudget::new(0);
        let allocated = budget.enter(|| {
            [
                try_allocate(MIN_REFUSABLE_BYTES).is_some(),
                try_allocate(MIN_REFUSABLE_BYTES).is_some(),
            ]
        });

        assert_eq!(allocated, [false, true]);
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
    fn refused_growth_keeps_the_original_block() {
        let budget = MemoryBudget::new(0);
        let (grew, block) = budget.enter(|| {
            let mut block = vec![7u8; 16];
            (block.try_reserve_exact(MIN_REFUSABLE_BYTES).is_ok(), block)
        });

        assert!(!grew);
        assert_eq!(block, [7u8; 16]);
    }

    #[test]
    fn charges_only_allocations_inside_the_scope() {
        let budget = MemoryBudget::new(usize::MAX);
        let unscoped = try_allocate(1 << 20);
        let suspended = budget.enter(|| MemoryBudget::suspend(|| try_allocate(1 << 20)));

        assert!(unscoped.is_some() && suspended.is_some());
        assert_eq!(used_bytes(&budget), 0);
    }
}
