use std::path::Path;

use super::{Index, Result};
use crate::ml_db::MlDb;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FillState {
    Filled,
    Filling,
    Stale,
}

const FILLED: &str = "filled";
const FILLING: &str = "filling";

struct Keys {
    fill: &'static str,
    cursor: &'static str,
}

fn keys(index: Index) -> Keys {
    match index {
        Index::Clip => Keys {
            fill: "clip.fill",
            cursor: "clip.cursor",
        },
        Index::ClusterCentroid => Keys {
            fill: "cluster_centroid.fill",
            cursor: "cluster_centroid.cursor",
        },
    }
}

pub(super) fn read(db: &MlDb, index: Index) -> Result<FillState> {
    Ok(match db.get_meta(keys(index).fill)?.as_deref() {
        Some(FILLED) => FillState::Filled,
        Some(FILLING) => FillState::Filling,
        _ => FillState::Stale,
    })
}

pub(super) fn cursor(db: &MlDb, index: Index) -> Result<Option<String>> {
    Ok(db.get_meta(keys(index).cursor)?)
}

pub(super) fn set_cursor(db: &MlDb, index: Index, key: &str) -> Result<()> {
    db.set_meta(keys(index).cursor, key)?;
    Ok(())
}

pub(super) fn mark_filling(db: &MlDb, index: Index) -> Result<()> {
    let keys = keys(index);
    db.delete_meta(keys.cursor)?;
    db.set_meta(keys.fill, FILLING)?;
    Ok(())
}

pub(super) fn mark_filled(db: &MlDb, index: Index) -> Result<()> {
    let keys = keys(index);
    db.set_meta(keys.fill, FILLED)?;
    db.delete_meta(keys.cursor)?;
    Ok(())
}

pub(super) fn mark_stale(db: &MlDb, index: Index) -> Result<()> {
    let keys = keys(index);
    db.delete_meta(keys.fill)?;
    db.delete_meta(keys.cursor)?;
    Ok(())
}

pub(super) fn invalidate_lost_index(db: &MlDb, index: Index, path: &Path) -> Result<()> {
    if read(db, index)? == FillState::Stale {
        return Ok(());
    }
    log::warn!("{}: index files missing, refill required", path.display());
    mark_stale(db, index)
}
