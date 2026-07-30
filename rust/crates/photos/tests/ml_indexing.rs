#![cfg(feature = "ml-assets")]

mod support;

use anyhow::Result;
use support::ml_indexing::{
    ComparisonStats, MlIndexingTestContext, fail_if_any, run_with_large_stack,
};

#[tokio::test]
async fn rust_ml_matches_python_goldens() -> Result<()> {
    let context = MlIndexingTestContext::load().await?;
    run_with_large_stack("rust_ml_matches_python_goldens", move || {
        run_ml_indexing_test(context)
    })
}

fn run_ml_indexing_test(context: MlIndexingTestContext) -> Result<()> {
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
