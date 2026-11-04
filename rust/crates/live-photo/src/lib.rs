use std::{
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

const EXPANSION_RATIO: u64 = 20;
const EXPANSION_OVERHEAD: u64 = 16 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Component {
    Image,
    Video,
}

impl Component {
    fn name(self) -> &'static str {
        match self {
            Self::Image => "image",
            Self::Video => "video",
        }
    }
}

#[derive(Debug)]
pub struct Part<W> {
    pub component: Component,
    pub extension: String,
    pub writer: W,
}

#[derive(Debug)]
pub struct FilePart {
    pub file_name: String,
    pub path: PathBuf,
}

#[derive(Debug)]
pub struct Files {
    pub image: FilePart,
    pub video: FilePart,
}

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

impl Error {
    pub fn is_storage_full(&self) -> bool {
        match self {
            Self::Io(error) | Self::Zip(zip::result::ZipError::Io(error)) => {
                error.kind() == std::io::ErrorKind::StorageFull
            }
            Self::Components | Self::ExpansionLimit | Self::Zip(_) => false,
        }
    }

    pub fn is_invalid_archive(&self) -> bool {
        match self {
            Self::Components | Self::ExpansionLimit => true,
            Self::Io(error) | Self::Zip(zip::result::ZipError::Io(error)) => matches!(
                error.kind(),
                std::io::ErrorKind::InvalidData | std::io::ErrorKind::UnexpectedEof
            ),
            Self::Zip(_) => true,
        }
    }
}

pub fn extract<R: Read + Seek, W: Write>(
    reader: R,
    output: impl FnMut(Component, &str) -> std::io::Result<W>,
) -> Result<[Part<W>; 2], Error> {
    extract_with(reader, |_| true, output)
}

fn extract_with<R: Read + Seek, W: Write>(
    mut reader: R,
    supported_extension: impl Fn(&str) -> bool,
    mut output: impl FnMut(Component, &str) -> std::io::Result<W>,
) -> Result<[Part<W>; 2], Error> {
    let limit = reader
        .seek(SeekFrom::End(0))?
        .saturating_mul(EXPANSION_RATIO)
        .saturating_add(EXPANSION_OVERHEAD);
    let mut archive = zip::ZipArchive::new(reader)?;
    if archive.has_duplicate_names() {
        return Err(Error::Components);
    }
    archive.validate_header_consistency()?;
    let mut image = None;
    let mut video = None;
    let mut declared_remaining = limit;
    for index in 0..archive.len() {
        let entry = archive.by_index(index)?;
        let unix_type = entry.unix_mode().map(|mode| mode & 0o170000);
        if entry.is_dir() {
            if unix_type.is_some_and(|file_type| !matches!(file_type, 0 | 0o040000)) {
                return Err(Error::Components);
            }
            continue;
        }
        if !entry.is_file() || unix_type.is_some_and(|file_type| !matches!(file_type, 0 | 0o100000))
        {
            return Err(Error::Components);
        }
        let name = entry.name()?;
        let (component, extension) = parse_name(&name).ok_or(Error::Components)?;
        if !supported_extension(extension) {
            return Err(Error::Components);
        }
        let slot = match component {
            Component::Image => &mut image,
            Component::Video => &mut video,
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
    let mut remaining = limit;
    Ok([
        write_part(
            &mut archive,
            Component::Image,
            image,
            &mut remaining,
            &mut output,
        )?,
        write_part(
            &mut archive,
            Component::Video,
            video,
            &mut remaining,
            &mut output,
        )?,
    ])
}

pub fn extract_to_directory(archive_path: &Path, output_directory: &Path) -> Result<Files, Error> {
    let [image, video] = extract_with(
        File::open(archive_path)?,
        is_simple_extension,
        |component, extension| {
            File::create(output_directory.join(format!("{}{extension}", component.name())))
        },
    )?;
    Ok(Files {
        image: file_part(output_directory, image),
        video: file_part(output_directory, video),
    })
}

fn parse_name(name: &str) -> Option<(Component, &str)> {
    let (component, extension) = if let Some(extension) = name.strip_prefix("image") {
        (Component::Image, extension)
    } else {
        (Component::Video, name.strip_prefix("video")?)
    };
    if extension.is_empty()
        || (extension.starts_with('.') && extension.len() > 1 && !extension.contains(['/', '\\']))
    {
        Some((component, extension))
    } else {
        None
    }
}

fn is_simple_extension(extension: &str) -> bool {
    extension.is_empty()
        || extension.strip_prefix('.').is_some_and(|extension| {
            (1..=16).contains(&extension.len())
                && extension.bytes().all(|byte| byte.is_ascii_alphanumeric())
        })
}

fn write_part<R: Read + Seek, W: Write>(
    archive: &mut zip::ZipArchive<R>,
    component: Component,
    (index, extension): (usize, String),
    remaining: &mut u64,
    output: &mut impl FnMut(Component, &str) -> std::io::Result<W>,
) -> Result<Part<W>, Error> {
    let mut entry = archive.by_index(index)?;
    let mut writer = output(component, &extension)?;
    *remaining -= std::io::copy(&mut entry.by_ref().take(*remaining), &mut writer)?;
    if entry.read(&mut [0])? != 0 {
        return Err(Error::ExpansionLimit);
    }
    writer.flush()?;
    Ok(Part {
        component,
        extension,
        writer,
    })
}

fn file_part(output_directory: &Path, part: Part<File>) -> FilePart {
    let file_name = format!("{}{}", part.component.name(), part.extension);
    drop(part.writer);
    FilePart {
        path: output_directory.join(&file_name),
        file_name,
    }
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

    fn sized_archive(sizes: [u64; 2], method: zip::CompressionMethod) -> Vec<u8> {
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

    fn named_archive(names: &[&str]) -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for name in names {
            zip.start_file(*name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(b"component").unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    fn unicode_path(raw_name_crc: [u8; 4], name: &str) -> Vec<u8> {
        let mut field = vec![1];
        field.extend_from_slice(&raw_name_crc);
        field.extend_from_slice(name.as_bytes());
        field
    }

    #[test]
    fn extracts_supported_names_and_compression() {
        for (method, sizes) in [
            (zip::CompressionMethod::Stored, [21 * 1024 * 1024, 1]),
            (zip::CompressionMethod::Deflated, [7 * 1024 * 1024; 2]),
        ] {
            let written = Cell::new(0);
            let parts = extract(Cursor::new(sized_archive(sizes, method)), |_, _| {
                Ok(Count(&written))
            })
            .unwrap();
            assert_eq!(written.get(), sizes.into_iter().sum::<u64>());
            assert_eq!(parts[0].component, Component::Image);
            assert_eq!(parts[1].component, Component::Video);
        }
        for names in [["video.MOV", "image.HEIC"], ["video", "image"]] {
            let parts = extract(Cursor::new(named_archive(&names)), |_, _| {
                Ok(std::io::sink())
            })
            .unwrap();
            assert_eq!(parts[0].extension, names[1].strip_prefix("image").unwrap());
            assert_eq!(parts[1].extension, names[0].strip_prefix("video").unwrap());
        }
    }

    #[test]
    fn extracts_to_fixed_paths() {
        let directory = tempfile::tempdir().unwrap();
        let output = tempfile::tempdir().unwrap();
        let archive_path = directory.path().join("live-photo.zip");
        std::fs::write(&archive_path, named_archive(&["video.mov", "image.jpg"])).unwrap();
        let files = extract_to_directory(&archive_path, output.path()).unwrap();
        assert_eq!(files.image.file_name, "image.jpg");
        assert_eq!(files.video.file_name, "video.mov");
        assert_eq!(std::fs::read(files.image.path).unwrap(), b"component");
        assert_eq!(std::fs::read(files.video.path).unwrap(), b"component");
    }

    #[test]
    fn rejects_repeated_directory_entries_before_opening_output() {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for name in ["ignored/", "altered/"] {
            zip.add_directory(name, zip::write::SimpleFileOptions::default())
                .unwrap();
        }
        for name in ["image.jpg", "video.mov"] {
            zip.start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(b"component").unwrap();
        }
        let mut bytes = zip.finish().unwrap().into_inner();
        for index in 0..=bytes.len() - b"altered/".len() {
            if &bytes[index..index + b"altered/".len()] == b"altered/" {
                bytes[index..index + b"altered/".len()].copy_from_slice(b"ignored/");
            }
        }
        let mut opened = 0;
        let result = extract(Cursor::new(bytes), |_, _| {
            opened += 1;
            Ok(std::io::sink())
        });
        assert!(matches!(result, Err(Error::Components)));
        assert_eq!(opened, 0);
    }

    #[test]
    fn rejects_invalid_components_before_opening_output() {
        for names in [
            vec!["image.jpg"],
            vec!["video.mov"],
            vec!["image.jpg", "image.png", "video.mov"],
            vec!["image.jpg", "video.mov", "other.jpg"],
            vec!["image/../../outside.jpg", "video.mov"],
            vec!["image.jpg", "video\\outside.mov"],
            vec!["image.", "video.mov"],
            vec!["imagejpg", "video.mov"],
        ] {
            let mut opened = 0;
            let result = extract(Cursor::new(named_archive(&names)), |_, _| {
                opened += 1;
                Ok(std::io::sink())
            });
            assert!(matches!(result, Err(Error::Components)), "{names:?}");
            assert_eq!(opened, 0, "{names:?}");
        }

        let mut duplicate = named_archive(&["image.jpg", "image.png", "video.mov"]);
        for index in 0..=duplicate.len() - b"image.png".len() {
            if &duplicate[index..index + b"image.png".len()] == b"image.png" {
                duplicate[index..index + b"image.png".len()].copy_from_slice(b"image.jpg");
            }
        }
        let mut opened = 0;
        let result = extract(Cursor::new(duplicate), |_, _| {
            opened += 1;
            Ok(std::io::sink())
        });
        assert!(matches!(result, Err(Error::Components)));
        assert_eq!(opened, 0);

        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (raw_name, raw_name_crc) in [
            ("raw-image-a", [0x14, 0x6a, 0x39, 0xf9]),
            ("raw-image-b", [0xae, 0x3b, 0x30, 0x60]),
        ] {
            let mut options = zip::write::FullFileOptions::default();
            options
                .add_extra_field(0x7075, unicode_path(raw_name_crc, "image.jpg"), false)
                .unwrap();
            zip.start_file(raw_name, options).unwrap();
            zip.write_all(b"component").unwrap();
        }
        zip.start_file("video.mov", zip::write::SimpleFileOptions::default())
            .unwrap();
        zip.write_all(b"component").unwrap();
        let mut opened = 0;
        let result = extract(Cursor::new(zip.finish().unwrap().into_inner()), |_, _| {
            opened += 1;
            Ok(std::io::sink())
        });
        assert!(matches!(result, Err(Error::Components)));
        assert_eq!(opened, 0);
    }

    #[test]
    fn rejects_inconsistent_headers_before_opening_output() {
        let mut bytes = named_archive(&["image.jpg", "video.mov"]);
        let headers: Vec<_> = bytes
            .windows(4)
            .enumerate()
            .filter_map(|(index, bytes)| (bytes == b"PK\x01\x02").then_some(index))
            .collect();
        assert_eq!(headers.len(), 2);
        let first_offset = bytes[headers[0] + 42..headers[0] + 46].to_vec();
        bytes[headers[1] + 42..headers[1] + 46].copy_from_slice(&first_offset);
        let mut opened = 0;
        let result = extract(Cursor::new(bytes), |_, _| {
            opened += 1;
            Ok(std::io::sink())
        });
        assert!(matches!(result, Err(Error::Zip(_))));
        assert_eq!(opened, 0);
    }

    #[test]
    fn generic_extraction_preserves_safe_extensions() {
        let parts = extract(
            Cursor::new(named_archive(&["video.m:v", "image.j?g "])),
            |_, _| Ok(std::io::sink()),
        )
        .unwrap();
        assert_eq!(parts[0].extension, ".j?g ");
        assert_eq!(parts[1].extension, ".m:v");
    }

    #[test]
    fn directory_extraction_rejects_non_simple_extensions() {
        for names in [
            ["image.jpg.png", "video.mov"],
            ["image.abcdefghijklmnopq", "video.mov"],
            ["image.jpég", "video.mov"],
            ["image.jpg\n", "video.mov"],
            ["image.j?g ", "video.mov"],
        ] {
            let directory = tempfile::tempdir().unwrap();
            let output = tempfile::tempdir().unwrap();
            let archive_path = directory.path().join("live-photo.zip");
            std::fs::write(&archive_path, named_archive(&names)).unwrap();
            assert!(matches!(
                extract_to_directory(&archive_path, output.path()),
                Err(Error::Components)
            ));
            assert_eq!(std::fs::read_dir(output.path()).unwrap().count(), 0);
        }
    }

    #[test]
    fn rejects_symlinks_before_opening_output() {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        zip.add_symlink(
            "image.jpg",
            "target",
            zip::write::SimpleFileOptions::default(),
        )
        .unwrap();
        zip.start_file("video.mov", zip::write::SimpleFileOptions::default())
            .unwrap();
        zip.write_all(b"component").unwrap();
        let mut opened = 0;
        let result = extract(Cursor::new(zip.finish().unwrap().into_inner()), |_, _| {
            opened += 1;
            Ok(std::io::sink())
        });
        assert!(matches!(result, Err(Error::Components)));
        assert_eq!(opened, 0);
    }

    #[test]
    fn accepts_entries_without_unix_file_types() {
        for (system, attributes) in [(0, 0), (3, 0o600_u32 << 16)] {
            let mut bytes = named_archive(&["image.jpg", "video.mov"]);
            let headers: Vec<_> = bytes
                .windows(4)
                .enumerate()
                .filter_map(|(index, bytes)| (bytes == b"PK\x01\x02").then_some(index))
                .collect();
            assert_eq!(headers.len(), 2);
            for header in headers {
                bytes[header + 5] = system;
                bytes[header + 38..header + 42].copy_from_slice(&attributes.to_le_bytes());
            }
            extract(Cursor::new(bytes), |_, _| Ok(std::io::sink())).unwrap();
        }
    }

    #[test]
    fn rejects_special_unix_entries_before_opening_output() {
        for mode in [0o010000, 0o020000, 0o060000, 0o140000] {
            let mut bytes = named_archive(&["image.jpg", "video.mov"]);
            let header = bytes
                .windows(4)
                .position(|bytes| bytes == b"PK\x01\x02")
                .unwrap();
            bytes[header + 5] = 3;
            bytes[header + 40..header + 42].copy_from_slice(&(mode as u16).to_le_bytes());
            let mut opened = 0;
            let result = extract(Cursor::new(bytes), |_, _| {
                opened += 1;
                Ok(std::io::sink())
            });
            assert!(matches!(result, Err(Error::Components)), "{mode:o}");
            assert_eq!(opened, 0, "{mode:o}");
        }
    }

    #[test]
    fn rejects_excessive_expansion_and_understated_sizes() {
        let mut bytes = sized_archive([9 * 1024 * 1024; 2], zip::CompressionMethod::Deflated);
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
            .filter_map(|(index, bytes)| (bytes == b"PK\x01\x02").then_some(index))
            .collect();
        assert_eq!(headers.len(), 2);
        for offset in headers {
            bytes[offset + 24..offset + 28].copy_from_slice(&1u32.to_le_bytes());
        }
        let result = extract(Cursor::new(&bytes), |_, _| {
            opened += 1;
            Ok(Count(&written))
        });
        assert!(matches!(result, Err(Error::Zip(_))));
        assert_eq!(opened, 0);
    }
}
