use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
    ptr,
};

use crate::memory_budget::MemoryBudget;

#[global_allocator]
static ALLOCATOR: BudgetedAllocator = BudgetedAllocator;

thread_local! {
    static CURRENT_BUDGET: Cell<*const MemoryBudget> = const { Cell::new(ptr::null()) };
}

pub(crate) fn with_budget<T>(budget: &MemoryBudget, work: impl FnOnce() -> T) -> T {
    let _scope = Scope::replace(budget);
    work()
}

pub(crate) fn without_budget<T>(work: impl FnOnce() -> T) -> T {
    let _scope = Scope::replace(ptr::null());
    work()
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

fn charged(allocation: *mut u8, bytes: usize) -> *mut u8 {
    if !allocation.is_null()
        && let Some(budget) = current_budget()
    {
        budget.charge(bytes);
    }
    allocation
}

fn release(bytes: usize) {
    if let Some(budget) = current_budget() {
        budget.release(bytes);
    }
}

struct BudgetedAllocator;

#[expect(
    unsafe_code,
    reason = "Every call forwards its pointer and layout to the system allocator unchanged"
)]
unsafe impl GlobalAlloc for BudgetedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        charged(unsafe { System.alloc(layout) }, layout.size())
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        charged(unsafe { System.alloc_zeroed(layout) }, layout.size())
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        release(layout.size());
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let allocation = unsafe { System.realloc(ptr, layout, new_size) };
        if !allocation.is_null() {
            release(layout.size());
        }
        charged(allocation, new_size)
    }
}
