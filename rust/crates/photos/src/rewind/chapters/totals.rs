use crate::rewind::library::Library;
use crate::rewind::percentile::top_per_mille;
use crate::rewind::report::Totals;

pub(in crate::rewind) fn totals(library: &Library<'_>) -> Option<Totals> {
    let files = u32::try_from(library.files().len()).unwrap_or(u32::MAX);
    (files > 0).then(|| Totals {
        files,
        top_per_mille: top_per_mille(files),
    })
}
