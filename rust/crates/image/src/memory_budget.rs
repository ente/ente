use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
    ptr,
    sync::atomic::{AtomicBool, AtomicIsize, Ordering},
};

const MIN_REFUSABLE_BYTES: usize = 64 * 1024;

thread_local! {
    static CURRENT_BUDGET: Cell<*const MemoryBudget> = const { Cell::new(ptr::null()) };
}

pub struct BudgetedAllocator;

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
        let _scope = Scope::replace(self);
        work()
    }

    pub(crate) fn suspend<T>(work: impl FnOnce() -> T) -> T {
        let _scope = Scope::replace(ptr::null());
        work()
    }

    fn charge(&self, bytes: usize, request: usize, allocate: impl FnOnce() -> *mut u8) -> *mut u8 {
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
            return ptr::null_mut();
        }
        let allocation = allocate();
        if allocation.is_null() {
            self.used.fetch_sub(bytes, Ordering::Relaxed);
        }
        allocation
    }

    fn release(&self, bytes: usize) {
        self.used.fetch_sub(signed(bytes), Ordering::Relaxed);
    }
}

fn signed(bytes: usize) -> isize {
    isize::try_from(bytes).unwrap_or(isize::MAX)
}

struct Scope(*const MemoryBudget);

impl Scope {
    fn replace(budget: *const MemoryBudget) -> Self {
        Self(CURRENT_BUDGET.replace(budget))
    }
}

impl Drop for Scope {
    fn drop(&mut self) {
        CURRENT_BUDGET.set(self.0);
    }
}

#[expect(
    unsafe_code,
    reason = "The thread's budget pointer is only set by a Scope that borrows the budget until it is restored"
)]
fn current_budget<'a>() -> Option<&'a MemoryBudget> {
    let budget = CURRENT_BUDGET.try_with(Cell::get).unwrap_or(ptr::null());
    unsafe { budget.as_ref() }
}

#[expect(
    unsafe_code,
    reason = "Every call forwards its pointer and layout to the system allocator unchanged"
)]
unsafe impl GlobalAlloc for BudgetedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        match current_budget() {
            Some(budget) => budget.charge(layout.size(), layout.size(), || unsafe {
                System.alloc(layout)
            }),
            None => unsafe { System.alloc(layout) },
        }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        match current_budget() {
            Some(budget) => budget.charge(layout.size(), layout.size(), || unsafe {
                System.alloc_zeroed(layout)
            }),
            None => unsafe { System.alloc_zeroed(layout) },
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        if let Some(budget) = current_budget() {
            budget.release(layout.size());
        }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let Some(budget) = current_budget() else {
            return unsafe { System.realloc(ptr, layout, new_size) };
        };
        let old_size = layout.size();
        if new_size > old_size {
            return budget.charge(new_size - old_size, new_size, || unsafe {
                System.realloc(ptr, layout, new_size)
            });
        }
        let allocation = unsafe { System.realloc(ptr, layout, new_size) };
        if !allocation.is_null() {
            budget.release(old_size - new_size);
        }
        allocation
    }
}

#[cfg(test)]
mod tests {
    use std::{hint::black_box, sync::atomic::Ordering};

    use super::{BudgetedAllocator, MIN_REFUSABLE_BYTES, MemoryBudget};

    #[global_allocator]
    static ALLOCATOR: BudgetedAllocator = BudgetedAllocator;

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
