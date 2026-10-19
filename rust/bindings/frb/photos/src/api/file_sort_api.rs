pub fn sorted_filename_indices(
    names: Vec<String>,
    file_ids: Vec<i64>,
    locale: String,
    ascending: bool,
) -> Result<Vec<u32>, String> {
    ente_photos::file_sort::sorted_filename_indices(&names, &file_ids, &locale, ascending)
        .map_err(|error| error.to_string())
}
