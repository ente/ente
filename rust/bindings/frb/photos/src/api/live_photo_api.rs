use std::path::Path;

use ente_live_photo as live_photo;

#[derive(Clone, Debug)]
pub struct LivePhotoArchivePart {
    pub file_name: String,
    pub file_path: String,
}

#[derive(Clone, Debug)]
pub struct LivePhotoArchiveFiles {
    pub image: LivePhotoArchivePart,
    pub video: LivePhotoArchivePart,
}

#[derive(Clone, Debug)]
pub enum LivePhotoArchiveError {
    StorageFull { message: String },
    Format { message: String },
    Other { message: String },
}

impl From<live_photo::Error> for LivePhotoArchiveError {
    fn from(error: live_photo::Error) -> Self {
        let storage_full = error.is_storage_full();
        let format = error.is_invalid_archive();
        let message = error.to_string();
        if storage_full {
            Self::StorageFull { message }
        } else if format {
            Self::Format { message }
        } else {
            Self::Other { message }
        }
    }
}

pub fn extract_live_photo_archive(
    archive_path: String,
    output_directory: String,
) -> Result<LivePhotoArchiveFiles, LivePhotoArchiveError> {
    let files =
        live_photo::extract_to_directory(Path::new(&archive_path), Path::new(&output_directory))?;
    Ok(LivePhotoArchiveFiles {
        image: LivePhotoArchivePart {
            file_name: files.image.file_name,
            file_path: files.image.path.to_string_lossy().into_owned(),
        },
        video: LivePhotoArchivePart {
            file_name: files.video.file_name,
            file_path: files.video.path.to_string_lossy().into_owned(),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs::File, io::Write};

    #[test]
    fn extracts_archive_to_paths() {
        let directory = tempfile::tempdir().unwrap();
        let output = tempfile::tempdir().unwrap();
        let archive_path = directory.path().join("live-photo.zip");
        let mut zip = zip::ZipWriter::new(File::create(&archive_path).unwrap());
        for (name, bytes) in [("video.mov", b"video"), ("image.jpg", b"image")] {
            zip.start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(bytes).unwrap();
        }
        zip.finish().unwrap();

        let files = extract_live_photo_archive(
            archive_path.to_string_lossy().into_owned(),
            output.path().to_string_lossy().into_owned(),
        )
        .unwrap();
        assert_eq!(files.image.file_name, "image.jpg");
        assert_eq!(files.video.file_name, "video.mov");
        assert_eq!(std::fs::read(files.image.file_path).unwrap(), b"image");
        assert_eq!(std::fs::read(files.video.file_path).unwrap(), b"video");
    }

    #[test]
    fn preserves_storage_full_errors() {
        assert!(matches!(
            LivePhotoArchiveError::from(live_photo::Error::Io(
                std::io::ErrorKind::StorageFull.into()
            )),
            LivePhotoArchiveError::StorageFull { .. }
        ));
    }

    #[test]
    fn preserves_format_errors() {
        for error in [
            live_photo::Error::Components,
            live_photo::Error::ExpansionLimit,
            live_photo::Error::Io(std::io::ErrorKind::InvalidData.into()),
            live_photo::Error::Zip(zip::result::ZipError::Io(
                std::io::ErrorKind::UnexpectedEof.into(),
            )),
        ] {
            assert!(matches!(
                LivePhotoArchiveError::from(error),
                LivePhotoArchiveError::Format { .. }
            ));
        }
    }

    #[test]
    fn preserves_other_io_errors() {
        for error in [
            live_photo::Error::Io(std::io::ErrorKind::PermissionDenied.into()),
            live_photo::Error::Zip(zip::result::ZipError::Io(
                std::io::ErrorKind::PermissionDenied.into(),
            )),
        ] {
            assert!(matches!(
                LivePhotoArchiveError::from(error),
                LivePhotoArchiveError::Other { .. }
            ));
        }
    }
}
