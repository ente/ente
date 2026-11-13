#[cfg(windows)]
use std::fs::File;
#[cfg(windows)]
use std::io;
use std::path::Path;

#[cfg(windows)]
pub(super) fn open(root: &Path, document_id: &str) -> io::Result<File> {
    if !root.is_absolute() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "Collection root must be absolute",
        ));
    }
    let mut path = root.to_path_buf();
    for component in document_id.split('/') {
        path.push(component);
    }
    let file = File::open(path)?;
    if !path_is_beneath(&crate::platform::final_handle_path(&file)?, root) {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "Source note escaped its collection",
        ));
    }
    Ok(file)
}

fn path_is_beneath(path: &Path, root: &Path) -> bool {
    let Some((path, root)) = comparison_path(path).zip(comparison_path(root)) else {
        return false;
    };
    let root = root.trim_end_matches('\\');
    path == root
        || path
            .strip_prefix(root)
            .is_some_and(|suffix| suffix.starts_with('\\'))
}

fn comparison_path(path: &Path) -> Option<String> {
    let path = path
        .to_string_lossy()
        .replace('/', "\\")
        .to_ascii_lowercase();
    if path.starts_with(r"\\.\") {
        return None;
    }
    let Some(verbatim) = path.strip_prefix(r"\\?\") else {
        return Some(path);
    };
    if let Some(unc) = verbatim.strip_prefix(r"unc\") {
        return Some(format!(r"\\{unc}"));
    }
    let drive = verbatim.as_bytes().get(..3).is_some_and(|prefix| {
        prefix[0].is_ascii_alphabetic() && prefix[1] == b':' && prefix[2] == b'\\'
    });
    let volume = verbatim
        .split('\\')
        .next()?
        .strip_prefix("volume{")
        .and_then(|volume| volume.strip_suffix('}'))
        .is_some_and(|volume| uuid::Uuid::parse_str(volume).is_ok());
    (drive || volume).then(|| verbatim.to_owned())
}

#[cfg(test)]
mod tests {
    #[cfg(windows)]
    use std::fs;
    #[cfg(windows)]
    use std::io::Read;
    use std::path::Path;
    #[cfg(windows)]
    use std::path::PathBuf;

    #[cfg(windows)]
    use super::open;
    use super::path_is_beneath;

    #[cfg(windows)]
    struct Directory(PathBuf);

    #[cfg(windows)]
    impl Directory {
        fn new() -> Self {
            let directory =
                std::env::temp_dir().join(format!("ensu-scoped-{}", uuid::Uuid::new_v4()));
            fs::create_dir_all(directory.join("root/nested")).unwrap();
            fs::create_dir(directory.join("outside")).unwrap();
            fs::write(directory.join("root/nested/note.md"), "inside").unwrap();
            fs::write(directory.join("outside/note.md"), "outside").unwrap();
            Self(fs::canonicalize(directory).unwrap())
        }
    }

    #[cfg(windows)]
    impl Drop for Directory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[cfg(windows)]
    #[test]
    fn opens_nested_files_and_rejects_parent_and_absolute_paths() {
        let directory = Directory::new();
        let root = directory.0.join("root");
        let mut contents = String::new();
        open(&root, "nested/note.md")
            .unwrap()
            .read_to_string(&mut contents)
            .unwrap();
        assert_eq!(contents, "inside");
        assert!(open(&root, "../outside/note.md").is_err());
        assert!(open(&root, directory.0.join("outside/note.md").to_str().unwrap()).is_err());
    }

    #[cfg(windows)]
    #[test]
    fn rejects_directory_junction_escapes_and_device_names() {
        let directory = Directory::new();
        let root = directory.0.join("root");
        fs::remove_file(root.join("nested/note.md")).unwrap();
        fs::remove_dir(root.join("nested")).unwrap();
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(root.join("nested"))
            .arg(directory.0.join("outside"))
            .status()
            .unwrap();
        assert!(status.success());
        assert_eq!(
            fs::read_to_string(root.join("nested/note.md")).unwrap(),
            "outside"
        );
        let error = open(&root, "nested/note.md").unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
        assert_eq!(error.raw_os_error(), None);
        for name in ["NUL", "CON", "COM1", "COM¹", "LPT¹"] {
            assert!(open(&root, name).is_err());
        }
        fs::rename(&root, directory.0.join("original-root")).unwrap();
        let status = std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(&root)
            .arg(directory.0.join("outside"))
            .status()
            .unwrap();
        assert!(status.success());
        assert_eq!(fs::read_to_string(root.join("note.md")).unwrap(), "outside");
        let error = open(&root, "note.md").unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
        assert_eq!(error.raw_os_error(), None);
    }

    #[cfg(windows)]
    #[test]
    fn supports_unicode_names_and_reads_from_the_opened_handle() {
        let directory = Directory::new();
        let root = directory.0.join("root");
        fs::write(root.join("café.md"), "original").unwrap();
        let mut file = open(&root, "café.md").unwrap();
        fs::rename(root.join("café.md"), root.join("moved.md")).unwrap();
        fs::write(root.join("café.md"), "replacement").unwrap();
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        assert_eq!(contents, "original");
    }

    #[cfg(windows)]
    #[test]
    fn supports_paths_longer_than_legacy_windows_limits() {
        let directory = Directory::new();
        let root = directory.0.join("root");
        let relative = format!("{}/note.md", ["long-directory-name"; 16].join("/"));
        let path = root.join(&relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, "long path").unwrap();
        let mut contents = String::new();
        open(&root, &relative)
            .unwrap()
            .read_to_string(&mut contents)
            .unwrap();
        assert_eq!(contents, "long path");
    }

    #[test]
    fn compares_windows_namespaces_and_path_boundaries() {
        for (path, root) in [
            (r"C:\Notes\note.md", r"\\?\C:\Notes"),
            (r"\\?\C:\Notes\note.md", r"c:\notes\"),
            (r"C:\Notes\café.md", r"\\?\C:\Notes"),
            (
                r"\\server\share\notes\note.md",
                r"\\?\UNC\server\share\notes",
            ),
            (
                r"\\?\UNC\server\share\notes\note.md",
                r"\\server\share\notes",
            ),
            (
                r"Volume{00000000-0000-0000-0000-000000000001}\notes\note.md",
                r"\\?\Volume{00000000-0000-0000-0000-000000000001}\notes",
            ),
        ] {
            assert!(path_is_beneath(Path::new(path), Path::new(root)));
        }
        for (path, root) in [
            (r"C:\Notes-other\note.md", r"\\?\C:\Notes"),
            (r"D:\Notes\note.md", r"\\?\C:\Notes"),
            (r"\\server\share-other\note.md", r"\\?\UNC\server\share"),
            (r"GLOBALROOT\Device\note.md", r"\\?\GLOBALROOT\Device"),
            (r"\\.\C:\Notes\note.md", r"C:\Notes"),
        ] {
            assert!(!path_is_beneath(Path::new(path), Path::new(root)));
        }
    }

    #[cfg(windows)]
    #[test]
    fn reads_literal_reserved_windows_filenames() {
        let directory = Directory::new();
        let root = directory.0.join("root");
        for name in ["con.md", "aux.notes.md", "com¹.md"] {
            fs::write(root.join(name), name).unwrap();
            let mut contents = String::new();
            open(&root, name)
                .unwrap()
                .read_to_string(&mut contents)
                .unwrap();
            assert_eq!(contents, name);
        }
    }
}
