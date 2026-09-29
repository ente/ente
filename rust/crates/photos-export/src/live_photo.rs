use std::io::{Read, Seek, Write};

use crate::metadata::Role;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Zip(#[from] zip::result::ZipError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("Live Photo must contain one image and one video")]
    Components,
}

pub fn extract<R: Read + Seek, W: Write>(
    reader: R,
    mut output: impl FnMut(Role, &str) -> std::io::Result<W>,
) -> Result<Vec<(Role, String, W)>, Error> {
    let mut archive = zip::ZipArchive::new(reader)?;
    let mut image = None;
    let mut video = None;
    for index in 0..archive.len() {
        let entry = archive.by_index(index)?;
        if entry.is_dir() {
            continue;
        }
        let name = entry.name();
        let (role, extension) = if let Some(extension) = name.strip_prefix("image") {
            (Role::Image, extension)
        } else if let Some(extension) = name.strip_prefix("video") {
            (Role::Video, extension)
        } else {
            return Err(Error::Components);
        };
        if (!extension.is_empty() && (!extension.starts_with('.') || extension.len() == 1))
            || extension.contains(['/', '\\'])
        {
            return Err(Error::Components);
        }
        let slot = if role == Role::Image {
            &mut image
        } else {
            &mut video
        };
        if slot.replace((index, extension.to_owned())).is_some() {
            return Err(Error::Components);
        }
    }
    let (Some(image), Some(video)) = (image, video) else {
        return Err(Error::Components);
    };
    let mut results = Vec::with_capacity(2);
    for (role, (index, extension)) in [(Role::Image, image), (Role::Video, video)] {
        let mut writer = output(role.clone(), &extension)?;
        std::io::copy(&mut archive.by_index(index)?, &mut writer)?;
        writer.flush()?;
        results.push((role, extension, writer));
    }
    Ok(results)
}
