use std::{
    fs,
    path::{Component, Path},
};

use anyhow::{Result, ensure};
use icu_casemap::CaseMapper;
use rusqlite::params;
use unicode_normalization::UnicodeNormalization;

use super::store::Store;

pub fn folded(name: &str) -> String {
    CaseMapper::new()
        .fold_string(&name.nfc().collect::<String>())
        .nfc()
        .collect()
}

pub fn relative(path: &str) -> Result<()> {
    ensure!(
        !path.is_empty()
            && !path.contains('\\')
            && Path::new(path)
                .components()
                .all(|part| matches!(part, Component::Normal(_))),
        "invalid export path {path:?}"
    );
    Ok(())
}

pub fn check(root: &Path, path: &str) -> Result<std::path::PathBuf> {
    relative(path)?;
    let mut current = root.to_path_buf();
    let mut parts = Path::new(path).components().peekable();
    while let Some(part) = parts.next() {
        current.push(part);
        match fs::symlink_metadata(&current) {
            Ok(metadata) => {
                ensure!(
                    !metadata.is_symlink(),
                    super::Conflict(format!("symlink at {}", current.display()))
                );
                ensure!(
                    parts.peek().is_none() || metadata.is_dir(),
                    super::Conflict(format!("expected directory at {}", current.display()))
                );
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(current)
}

pub fn portable(name: &str) -> String {
    let converted: String = name
        .chars()
        .map(|c| {
            if c.is_control() || "/\\<>:\"|?*".contains(c) {
                '_'
            } else {
                c
            }
        })
        .collect();
    converted.trim_end_matches(['.', ' ']).to_owned()
}

fn shorten(stem: &str, bytes: usize) -> &str {
    let mut end = stem.len().min(bytes);
    while !stem.is_char_boundary(end) {
        end -= 1;
    }
    &stem[..end]
}

pub fn split(name: &str, album: bool) -> (&str, &str) {
    if !album
        && let Some(index) = name.rfind('.')
        && index > 0
    {
        (&name[..index], &name[index..])
    } else {
        (name, "")
    }
}

pub fn reserved(name: &str, album: bool) -> bool {
    let folded = folded(name);
    if if album {
        ["trash", "export.json"].contains(&folded.as_str())
    } else {
        ["metadata", "metadata.json"].contains(&folded.as_str())
    } {
        return true;
    }
    device(&folded)
}

fn device(name: &str) -> bool {
    let folded = folded(name);
    let device = folded.split('.').next().unwrap_or_default();
    ["con", "prn", "aux", "nul", "clock$"].contains(&device)
        || ["com", "lpt"].iter().any(|prefix| {
            device.strip_prefix(prefix).is_some_and(|n| {
                matches!(
                    n,
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
                )
            })
        })
}

fn numbered(stem: &str, suffix: &str) -> String {
    if device(stem)
        && let Some((head, tail)) = stem.split_once('.')
    {
        format!("{head}{suffix}.{tail}")
    } else {
        format!("{stem}{suffix}")
    }
}

pub fn available(
    store: &Store,
    folder: &str,
    names: &[String],
    owner: &str,
    kind: &str,
) -> Result<bool> {
    for name in names {
        let occupied: bool = if kind == "album" {
            store.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM albums WHERE parent=?1 AND folded=?2 AND key<>?3 UNION ALL SELECT 1 FROM pending WHERE folder=?1 AND folded1=?2 AND kind='album' AND owner<>?3)",
                params![folder, folded(name), owner],
                |r| r.get(0),
            )?
        } else {
            store.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM components c JOIN placements p ON p.id=c.placement WHERE c.folder=?1 AND c.folded=?2 AND c.placement<>?3 UNION ALL SELECT 1 FROM components c JOIN placements p ON p.id=c.placement WHERE c.folder=?1 AND c.stem=?4 AND c.placement<>?3 AND NOT(p.kind=?5 AND p.kind IN ('image','video')) UNION ALL SELECT 1 FROM json_records j JOIN placements p ON p.id=j.owner WHERE j.folder=?1 AND j.folded=?2 AND j.owner<>?3 UNION ALL SELECT 1 FROM json_records j JOIN placements p ON p.id=j.owner WHERE j.folder=?1 AND j.stem=?4 AND j.owner<>?3 AND NOT(p.kind=?5 AND p.kind IN ('image','video')) UNION ALL SELECT 1 FROM pending WHERE folder=?1 AND folded1=?2 AND owner<>?3 UNION ALL SELECT 1 FROM pending WHERE folder=?1 AND folded2=?2 AND owner<>?3 UNION ALL SELECT 1 FROM pending WHERE folder=?1 AND stem1=?4 AND owner<>?3 AND NOT(kind=?5 AND kind IN ('image','video')) UNION ALL SELECT 1 FROM pending WHERE folder=?1 AND stem2=?4 AND owner<>?3 AND NOT(kind=?5 AND kind IN ('image','video')))",
                params![
                    folder,
                    folded(name),
                    owner,
                    folded(split(name, false).0),
                    kind
                ],
                |r| r.get(0),
            )?
        };
        if occupied {
            return Ok(false);
        }
    }
    Ok(true)
}

pub fn allocate(
    store: &Store,
    folder: &str,
    name: &str,
    kind: &str,
    extensions: Option<(&str, &str)>,
    owner: &str,
) -> Result<Vec<String>> {
    for suffix in 0u64.. {
        let Some(candidates) = candidates(name, kind == "album", extensions, suffix)? else {
            continue;
        };
        if available(store, folder, &candidates, owner, kind)? {
            return Ok(candidates);
        }
    }
    unreachable!()
}

pub fn candidates(
    name: &str,
    album: bool,
    extensions: Option<(&str, &str)>,
    suffix: u64,
) -> Result<Option<Vec<String>>> {
    let mut base = portable(name);
    if base.is_empty() {
        base = if album { "album" } else { "file" }.into();
    }
    let (stem, extension) = split(&base, album);
    let limit = if album { 255usize } else { 250usize };
    let suffix = if suffix == 0 {
        String::new()
    } else {
        format!("-{suffix}")
    };
    let candidates = if let Some((image, video)) = extensions {
        let image = portable(image);
        let video = portable(video);
        let equal = folded(&image) == folded(&video);
        let tail = image.len().max(video.len()) + suffix.len() + if equal { 6 } else { 0 };
        ensure!(tail < limit, "Live Photo extension is too long");
        let stem = numbered(shorten(stem, limit - tail), &suffix);
        let stem = if !equal && (image.is_empty() || video.is_empty()) {
            stem.trim_end_matches(['.', ' '])
        } else {
            &stem
        };
        ensure!(
            !stem.is_empty(),
            "Live Photo name cannot fit its extensions"
        );
        if equal {
            vec![
                format!("{stem}-image{image}"),
                format!("{stem}-video{video}"),
            ]
        } else {
            vec![format!("{stem}{image}"), format!("{stem}{video}")]
        }
    } else {
        ensure!(
            extension.len() + suffix.len() < limit,
            "file extension is too long"
        );
        vec![format!(
            "{}{extension}",
            numbered(
                shorten(stem, limit - extension.len() - suffix.len()),
                &suffix
            )
        )]
    };
    let candidates: Vec<_> = candidates.into_iter().map(|name| portable(&name)).collect();
    ensure!(
        candidates.iter().all(|name| !name.is_empty()),
        "export name is empty after shortening"
    );
    if candidates.iter().any(|name| reserved(name, album)) {
        return Ok(None);
    }
    Ok(Some(candidates))
}

pub fn same_path(a: &Path, b: &Path) -> bool {
    match (fs::canonicalize(a), fs::canonicalize(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}
