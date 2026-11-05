import "package:photos/src/rust/api/rewind_api.dart" as rust;

const rewindSampleReports = {
  "Busy year": rust.RewindReport(totals: rust.Totals(files: 12873)),
  "One file": rust.RewindReport(totals: rust.Totals(files: 1)),
  "No chapters": rust.RewindReport(),
};
