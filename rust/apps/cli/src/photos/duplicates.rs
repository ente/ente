use std::{collections::HashSet, io::Write};

use anyhow::{Context, Result, ensure};
use dialoguer::{Confirm, MultiSelect, console::Term};
use ente_core::{Session, crypto::Key};
use ente_photos::{
    collections::{Collection, Visibility},
    dedup::{self, Duplicate, RemovalCollection, RemovalFile},
    files::File,
};
use serde::Serialize;
use serde_json::json;

use crate::{
    args::{DuplicateCommand, Options},
    output::{self, escape_controls},
};

use super::replica::Replica;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct GroupView {
    id: String,
    size_bytes: u64,
    reclaimable_bytes: u64,
    retained_id: String,
    files: Vec<FileView>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct FileView {
    id: String,
    name: String,
    albums: Vec<AlbumView>,
}

#[derive(Serialize)]
struct AlbumView {
    id: String,
    name: String,
}

struct Group {
    view: GroupView,
    items: Vec<Duplicate>,
    file_indices: Vec<usize>,
}

struct Snapshot {
    albums: Vec<Collection>,
    files: Vec<File>,
    groups: Vec<Group>,
}

pub fn validate(command: &DuplicateCommand, options: &Options) -> Result<()> {
    if let DuplicateCommand::Remove {
        groups,
        all,
        dry_run,
        yes,
    } = command
    {
        ensure!(
            !options.offline,
            "duplicate removal requires network access"
        );
        ensure!(
            *all || !groups.is_empty() || options.can_prompt(),
            "supply group IDs or --all when running without interactive prompts"
        );
        ensure!(
            *dry_run || *yes || options.can_prompt(),
            "duplicate removal requires confirmation; supply --yes when running without interactive prompts"
        );
    }
    Ok(())
}

pub async fn run(
    command: DuplicateCommand,
    session: &Session,
    replica: &mut Replica<'_>,
    options: &Options,
) -> Result<()> {
    let snapshot = load(session, replica, options.offline).await?;
    let DuplicateCommand::Remove {
        groups,
        all,
        dry_run,
        yes,
    } = command
    else {
        let DuplicateCommand::List(args) = command else {
            unreachable!()
        };
        let limit = args.limit().map_or(usize::MAX, |n| n as usize);
        let views: Vec<_> = snapshot
            .groups
            .iter()
            .take(limit)
            .map(|g| &g.view)
            .collect();
        if options.json {
            output::json(&views)?;
        } else if views.is_empty() {
            writeln!(std::io::stdout(), "No duplicates found.")?;
        } else {
            show(&mut std::io::stdout().lock(), &views)?;
        }
        if snapshot.groups.len() > limit {
            eprintln!("Showing first {limit} results; use --limit N or --all to see more.");
        }
        return Ok(());
    };

    let mut selected = HashSet::new();
    for id in groups {
        let id = id.to_string();
        let index = snapshot
            .groups
            .iter()
            .position(|g| g.view.id == id)
            .with_context(|| {
                format!("no duplicate group matches {id}; run photos duplicates list again")
            })?;
        selected.insert(index);
    }
    if all {
        selected.extend(0..snapshot.groups.len());
    } else if selected.is_empty() && !snapshot.groups.is_empty() {
        let labels: Vec<_> = snapshot
            .groups
            .iter()
            .map(|g| {
                format!(
                    "{}: {} copies, {} bytes reclaimable — {}",
                    g.view.id,
                    g.items.len(),
                    g.view.reclaimable_bytes,
                    g.view
                        .files
                        .iter()
                        .map(|f| escape_controls(&f.name))
                        .collect::<Vec<_>>()
                        .join(", ")
                )
            })
            .collect();
        selected.extend(
            MultiSelect::new()
                .with_prompt("Select duplicate groups (space to toggle, enter to continue)")
                .items(&labels)
                .interact_on(&Term::stderr())?,
        );
    }
    let groups: Vec<_> = snapshot
        .groups
        .into_iter()
        .enumerate()
        .filter_map(|(i, g)| selected.contains(&i).then_some(g))
        .collect();
    let views: Vec<_> = groups.iter().map(|g| &g.view).collect();
    show(&mut std::io::stderr().lock(), &views)?;
    let reclaimable_bytes = groups
        .iter()
        .try_fold(0_u64, |total, g| {
            total.checked_add(g.view.reclaimable_bytes)
        })
        .context("duplicate size exceeds the supported range")?;
    let group_ids: Vec<_> = groups.iter().map(|g| g.view.id.clone()).collect();
    let retained_ids: Vec<_> = groups.iter().map(|g| g.view.retained_id.clone()).collect();
    let files: Vec<_> = groups
        .iter()
        .flat_map(|g| g.file_indices.iter().zip(&g.items))
        .map(|(&index, item)| RemovalFile {
            id: item.file_id,
            collection_id: item.collection_ids[0],
            key: Key::from_bytes(*snapshot.files[index].key.as_bytes()),
        })
        .collect();
    let items: Vec<_> = groups.into_iter().map(|g| g.items).collect();
    let plan = dedup::plan_removal(&items);
    if !dry_run && !plan.trash_ids.is_empty() {
        if !yes {
            ensure!(
                Confirm::new()
                    .with_prompt(format!(
                        "Move {} extra copies to trash?",
                        plan.trash_ids.len()
                    ))
                    .default(false)
                    .interact_on(&Term::stderr())?,
                "cancelled"
            );
        }
        let albums: Vec<_> = snapshot
            .albums
            .into_iter()
            .map(|a| RemovalCollection {
                id: a.id,
                key: a.key,
            })
            .collect();
        dedup::execute_removal(session, &plan, &albums, &files, |p| {
            eprintln!("Completed {}/{} duplicate removal steps.", p.completed, p.total);
        })
        .await
        .context("duplicate removal did not finish; some changes may have completed; list duplicates again before retrying")?;
        replica.sync_collections(session).await.context("duplicates were moved to trash, but refreshing albums failed; run photos duplicates list online")?;
        load(session, replica, false).await.context("duplicates were moved to trash, but refreshing files failed; run photos duplicates list online")?;
    }
    output::action(
        options.json,
        &json!({
            "dryRun": dry_run,
            "groupIds": group_ids,
            "retainedIds": retained_ids,
            "trashIds": plan.trash_ids.iter().map(i64::to_string).collect::<Vec<_>>(),
            "reclaimableBytes": reclaimable_bytes,
        }),
        &format!(
            "{} {} extra copies from {} duplicate groups to trash.",
            if dry_run { "Would move" } else { "Moved" },
            plan.trash_ids.len(),
            items.len(),
        ),
    )
}

async fn load(session: &Session, replica: &mut Replica<'_>, offline: bool) -> Result<Snapshot> {
    let mut albums = replica.collections(None, None, |rows| {
        let mut albums = Vec::new();
        for entry in rows {
            let entry = entry?;
            let album = entry.value.with_context(|| {
                format!("cannot scan duplicates: album {} is unavailable", entry.id)
            })?;
            if album.owner_id == session.user_id && !matches!(album.visibility, Visibility::Hidden)
            {
                albums.push(album);
            }
        }
        Ok(albums)
    })?;
    albums.sort_by(|a, b| a.name.cmp(&b.name).then(a.id.cmp(&b.id)));
    if !offline {
        replica.sync_files(session, &albums).await?;
    }
    let mut files = Vec::new();
    let mut candidates = Vec::new();
    for album in &albums {
        ensure!(
            replica.files_synced_to(album.id)?.is_some(),
            "files for album {:?} have not finished syncing; run photos duplicates list online first",
            album.name
        );
        replica.files(Some(album.id), None, None, |rows| {
            for entry in rows {
                let entry = entry?;
                let file = entry.file.with_context(|| {
                    format!("cannot scan duplicates: file {} is unavailable", entry.id)
                })?;
                candidates.push(dedup::File {
                    id: file.id,
                    collection_id: album.id,
                    owner_id: file.owner_id,
                    hash: file.hash.clone(),
                    size: file.size,
                });
                files.push(file);
            }
            Ok(())
        })?;
    }
    let collections: Vec<_> = albums
        .iter()
        .map(|a| dedup::Collection {
            id: a.id,
            owner_id: a.owner_id,
        })
        .collect();
    let mut groups = Vec::new();
    for group in dedup::find_duplicates(session.user_id, &collections, &candidates) {
        let items: Vec<_> = group
            .items
            .iter()
            .map(|item| {
                let file = &files[item.file_index];
                Duplicate {
                    file_id: file.id,
                    collection_ids: item.collection_ids.clone(),
                    caption: file.caption.clone(),
                    edited_name: file.edited_name.clone(),
                    edited_time: file.edited_time,
                }
            })
            .collect();
        let plan = dedup::plan_removal(std::slice::from_ref(&items));
        let retained = items
            .iter()
            .find(|f| !plan.trash_ids.contains(&f.file_id))
            .context("duplicate group has no retained file")?;
        let id = items
            .iter()
            .map(|f| f.file_id)
            .min()
            .context("empty duplicate group")?;
        let view = GroupView {
            id: id.to_string(),
            size_bytes: group.item_size,
            reclaimable_bytes: group
                .item_size
                .checked_mul(plan.trash_ids.len() as u64)
                .context("duplicate size exceeds the supported range")?,
            retained_id: retained.file_id.to_string(),
            files: group
                .items
                .iter()
                .map(|item| {
                    let file = &files[item.file_index];
                    FileView {
                        id: file.id.to_string(),
                        name: file.name.clone(),
                        albums: albums
                            .iter()
                            .filter(|a| item.collection_ids.contains(&a.id))
                            .map(|a| AlbumView {
                                id: a.id.to_string(),
                                name: a.name.clone(),
                            })
                            .collect(),
                    }
                })
                .collect(),
        };
        groups.push(Group {
            view,
            items,
            file_indices: group.items.iter().map(|f| f.file_index).collect(),
        });
    }
    groups.sort_by(|a, b| {
        b.view
            .reclaimable_bytes
            .cmp(&a.view.reclaimable_bytes)
            .then(a.view.id.cmp(&b.view.id))
    });
    Ok(Snapshot {
        albums,
        files,
        groups,
    })
}

fn show(out: &mut impl Write, groups: &[&GroupView]) -> Result<()> {
    if groups.is_empty() {
        writeln!(out, "No duplicate groups selected.")?;
    }
    for group in groups {
        writeln!(
            out,
            "Group {}: {} copies, {} bytes reclaimable",
            group.id,
            group.files.len(),
            group.reclaimable_bytes
        )?;
        for file in &group.files {
            let albums = file
                .albums
                .iter()
                .map(|a| format!("{} ({})", escape_controls(&a.name), a.id))
                .collect::<Vec<_>>()
                .join(", ");
            writeln!(
                out,
                "  {} {}  {}  [{}]",
                if file.id == group.retained_id {
                    "keep "
                } else {
                    "trash"
                },
                file.id,
                escape_controls(&file.name),
                albums
            )?;
        }
    }
    Ok(())
}
