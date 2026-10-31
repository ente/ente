use std::collections::{HashMap, HashSet};

use ente_core::{
    Session, b64,
    crypto::{Key, secretbox},
    http,
};
use serde::Serialize;

use super::{Duplicate, RemovalPlan, plan_removal};

const REQUEST_BATCH_SIZE: usize = 1000;

pub struct RemovalCollection {
    pub id: i64,
    pub key: Key,
}

pub struct RemovalFile {
    pub id: i64,
    pub collection_id: i64,
    pub key: Key,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RemovalProgress {
    pub completed: usize,
    pub total: usize,
}

#[derive(Debug, thiserror::Error)]
pub enum RemovalError {
    #[error(transparent)]
    Http(#[from] http::Error),
    #[error("Missing collection {0}")]
    MissingCollection(i64),
    #[error("Missing file {0}")]
    MissingFile(i64),
    #[error("Invalid duplicate removal plan: {0}")]
    InvalidPlan(&'static str),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WrappedFile {
    id: i64,
    encrypted_key: String,
    key_decryption_nonce: String,
}

#[derive(Serialize)]
struct AddFiles<'a> {
    #[serde(rename = "collectionID")]
    collection_id: i64,
    files: &'a [WrappedFile],
}

#[derive(Serialize)]
struct TrashItem {
    #[serde(rename = "fileID")]
    file_id: i64,
    #[serde(rename = "collectionID")]
    collection_id: i64,
}

#[derive(Serialize)]
struct TrashFiles<'a> {
    items: &'a [TrashItem],
}

pub async fn remove_duplicates(
    session: &Session,
    groups: &[Vec<Duplicate>],
    collections: &[RemovalCollection],
    files: &[RemovalFile],
    on_progress: impl FnMut(RemovalProgress),
) -> Result<Vec<i64>, RemovalError> {
    let plan = plan_removal(groups);
    execute_removal(session, &plan, collections, files, on_progress).await?;
    Ok(plan.trash_ids)
}

pub async fn execute_removal(
    session: &Session,
    plan: &RemovalPlan,
    collections: &[RemovalCollection],
    files: &[RemovalFile],
    mut on_progress: impl FnMut(RemovalProgress),
) -> Result<(), RemovalError> {
    let collections: HashMap<_, _> = collections.iter().map(|c| (c.id, c)).collect();
    let files: HashMap<_, _> = files.iter().map(|f| (f.id, f)).collect();
    let trash_ids: HashSet<_> = plan.trash_ids.iter().copied().collect();
    if trash_ids.len() != plan.trash_ids.len() {
        return Err(RemovalError::InvalidPlan("repeated trash ID"));
    }
    let mut additions = Vec::with_capacity(plan.additions.len());
    for addition in &plan.additions {
        let collection = collections
            .get(&addition.collection_id)
            .ok_or(RemovalError::MissingCollection(addition.collection_id))?;
        let mut wrapped = Vec::with_capacity(addition.file_ids.len());
        for id in &addition.file_ids {
            if trash_ids.contains(id) {
                return Err(RemovalError::InvalidPlan(
                    "retained file is also scheduled for trash",
                ));
            }
            let file = files.get(id).ok_or(RemovalError::MissingFile(*id))?;
            let encrypted = secretbox::encrypt(file.key.as_bytes(), &collection.key);
            wrapped.push(WrappedFile {
                id: *id,
                encrypted_key: b64::encode(&encrypted.encrypted_data),
                key_decryption_nonce: b64::encode(encrypted.nonce.as_bytes()),
            });
        }
        additions.push((addition.collection_id, wrapped));
    }
    let items = plan
        .trash_ids
        .iter()
        .map(|id| {
            let file = files.get(id).ok_or(RemovalError::MissingFile(*id))?;
            Ok(TrashItem {
                file_id: *id,
                collection_id: file.collection_id,
            })
        })
        .collect::<Result<Vec<_>, RemovalError>>()?;

    let total = additions.len() + usize::from(!items.is_empty());
    let mut completed = 0;
    for (collection_id, files) in &additions {
        for batch in files.chunks(REQUEST_BATCH_SIZE) {
            session
                .api
                .post("/collections/add-files")
                .json(&AddFiles {
                    collection_id: *collection_id,
                    files: batch,
                })
                .send()
                .await?
                .error_for_code()
                .await?;
        }
        completed += 1;
        on_progress(RemovalProgress { completed, total });
    }
    for batch in items.chunks(REQUEST_BATCH_SIZE) {
        session
            .api
            .post("/files/trash")
            .json(&TrashFiles { items: batch })
            .send()
            .await?
            .error_for_code()
            .await?;
    }
    if !items.is_empty() {
        completed += 1;
        on_progress(RemovalProgress { completed, total });
    }
    Ok(())
}
