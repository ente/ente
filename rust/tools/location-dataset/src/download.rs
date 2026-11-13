use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

use reqwest::blocking::Client;
use zip::ZipArchive;

use crate::Result;

pub(crate) fn download(client: &Client, url: &str, path: &Path) -> Result<()> {
    if path.is_file() {
        return Ok(());
    }
    let temporary = path.with_extension("download");
    let mut response = client.get(url).send()?.error_for_status()?;
    let mut writer = BufWriter::new(File::create(&temporary)?);
    std::io::copy(&mut response, &mut writer)?;
    writer.flush()?;
    std::fs::rename(temporary, path)?;
    Ok(())
}

pub(crate) fn extract(archive_path: &Path, output: &Path, name: &str) -> Result<()> {
    if output.is_file() {
        return Ok(());
    }
    let mut archive = ZipArchive::new(File::open(archive_path)?)?;
    let mut source = archive.by_name(name)?;
    let temporary = output.with_extension("extract");
    let mut writer = BufWriter::new(File::create(&temporary)?);
    std::io::copy(&mut source, &mut writer)?;
    writer.flush()?;
    std::fs::rename(temporary, output)?;
    Ok(())
}
