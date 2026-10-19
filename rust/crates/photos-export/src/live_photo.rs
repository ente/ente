use std::io::{Read, Seek, SeekFrom, Write};

use crate::metadata::Role;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Zip(#[from] zip::result::ZipError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("Live Photo must contain one image and one video")]
    Components,
    #[error("Live Photo archive expands beyond limit")]
    ExpansionLimit,
}

pub fn extract<R: Read + Seek, W: Write>(
    mut reader: R,
    mut output: impl FnMut(Role, &str) -> std::io::Result<W>,
) -> Result<Vec<(Role, String, W)>, Error> {
    let limit = reader
        .seek(SeekFrom::End(0))?
        .saturating_mul(20)
        .saturating_add(16 * 1024 * 1024);
    let mut archive = zip::ZipArchive::new(reader)?;
    let mut image = None;
    let mut video = None;
    let mut declared_remaining = limit;
    for index in 0..archive.len() {
        let entry = archive.by_index(index)?;
        if entry.is_dir() {
            continue;
        }
        let name = entry.name()?;
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
        declared_remaining = declared_remaining
            .checked_sub(entry.size())
            .ok_or(Error::ExpansionLimit)?;
    }
    let (Some(image), Some(video)) = (image, video) else {
        return Err(Error::Components);
    };
    let mut results = Vec::with_capacity(2);
    let mut remaining = limit;
    for (role, (index, extension)) in [(Role::Image, image), (Role::Video, video)] {
        let mut writer = output(role.clone(), &extension)?;
        let mut entry = archive.by_index(index)?;
        remaining -= std::io::copy(&mut entry.by_ref().take(remaining), &mut writer)?;
        if entry.read(&mut [0])? != 0 {
            return Err(Error::ExpansionLimit);
        }
        writer.flush()?;
        results.push((role, extension, writer));
    }
    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::Cell, io::Cursor};

    struct Count<'a>(&'a Cell<u64>);

    impl Write for Count<'_> {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0.set(self.0.get() + bytes.len() as u64);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn archive(sizes: [u64; 2], method: zip::CompressionMethod) -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (name, size) in ["image.heic", "video.mov"].into_iter().zip(sizes) {
            zip.start_file(
                name,
                zip::write::SimpleFileOptions::default().compression_method(method),
            )
            .unwrap();
            std::io::copy(&mut std::io::repeat(0).take(size), &mut zip).unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    #[test]
    fn accepts_stored_large_components_and_deflated_pairs() {
        for (method, sizes) in [
            (zip::CompressionMethod::Stored, [21 * 1024 * 1024, 1]),
            (zip::CompressionMethod::Deflated, [7 * 1024 * 1024; 2]),
        ] {
            let written = Cell::new(0);
            let parts = extract(Cursor::new(archive(sizes, method)), |_, _| {
                Ok(Count(&written))
            })
            .unwrap();
            assert_eq!(written.get(), sizes.into_iter().sum::<u64>());
            assert_eq!(parts.len(), 2);
        }
    }

    #[test]
    fn rejects_excessive_expansion_and_understated_sizes() {
        let mut bytes = archive([9 * 1024 * 1024; 2], zip::CompressionMethod::Deflated);
        let written = Cell::new(0);
        let mut opened = 0;
        let result = extract(Cursor::new(&bytes), |_, _| {
            opened += 1;
            Ok(Count(&written))
        });
        assert!(matches!(result, Err(Error::ExpansionLimit)));
        assert_eq!(opened, 0);
        let headers: Vec<_> = bytes
            .windows(4)
            .enumerate()
            .filter_map(|(i, bytes)| (bytes == b"PK\x01\x02").then_some(i))
            .collect();
        assert_eq!(headers.len(), 2);
        for offset in headers {
            bytes[offset + 24..offset + 28].copy_from_slice(&1u32.to_le_bytes());
        }
        let result = extract(Cursor::new(&bytes), |_, _| {
            opened += 1;
            Ok(Count(&written))
        });
        assert!(
            matches!(result, Err(Error::Io(error)) if error.kind() == std::io::ErrorKind::InvalidData)
        );
    }
}
