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

fn charge(bytes: usize, request: usize, allocate: impl FnOnce() -> *mut u8) -> *mut u8 {
    let Some(budget) = current_budget() else {
        return allocate();
    };
    if !budget.reserve(bytes, request) {
        return ptr::null_mut();
    }
    let allocation = allocate();
    if allocation.is_null() {
        budget.release(bytes);
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
        charge(layout.size(), layout.size(), || unsafe {
            System.alloc(layout)
        })
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        charge(layout.size(), layout.size(), || unsafe {
            System.alloc_zeroed(layout)
        })
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        release(layout.size());
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let old_size = layout.size();
        if new_size > old_size {
            return charge(new_size - old_size, new_size, || unsafe {
                System.realloc(ptr, layout, new_size)
            });
        }
        let allocation = unsafe { System.realloc(ptr, layout, new_size) };
        if !allocation.is_null() {
            release(old_size - new_size);
        }
        allocation
    }
}
