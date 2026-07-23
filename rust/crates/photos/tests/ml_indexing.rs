#![cfg(feature = "ml-assets")]

mod support;

use anyhow::Result;
use support::ml_indexing::{
    ComparisonStats, MlIndexingTestContext, fail_if_any, run_with_large_stack,
};

#[test]
fn rust_ml_matches_python_goldens() {
    run_with_large_stack("rust_ml_matches_python_goldens", run_ml_indexing_test);
}

fn run_ml_indexing_test() -> Result<()> {
    let context = MlIndexingTestContext::load()?;
    let runtime = context.prepare_runtime();

    let mut failures = context.validate_manifest_expectations()?;
    let mut stats = ComparisonStats::default();
    let rust_results = context.run_rust_indexing(&runtime, &mut failures)?;
    context.compare_with_python_goldens(&rust_results, &mut failures, &mut stats)?;
    if failures.is_empty() {
        stats.print_if_requested();
    }

    fail_if_any(failures, &stats)
}
