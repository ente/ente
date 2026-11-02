use ente_photos::dedup;
use serde::{Deserialize, Serialize};
use serde_wasm_bindgen as swb;
use tsify::Tsify;
use wasm_bindgen::prelude::*;

use crate::session::Session;
use ente_core::{
    b64,
    crypto::{self, Key},
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Serde(#[from] swb::Error),
    #[error(transparent)]
    Removal(#[from] dedup::RemovalError),
    #[error(transparent)]
    Decode(#[from] b64::DecodeError),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
}

impl From<Error> for JsValue {
    fn from(error: Error) -> Self {
        crate::js_error(&error, None)
    }
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct DedupCollection {
    id: i64,
    owner_id: i64,
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct DedupFile {
    id: i64,
    collection_id: i64,
    owner_id: i64,
    hash: Option<String>,
    size: Option<u64>,
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct FindDuplicatesInput {
    user_id: i64,
    collections: Vec<DedupCollection>,
    files: Vec<DedupFile>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct DuplicateItem {
    file_index: usize,
    collection_ids: Vec<i64>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct DuplicateGroup {
    items: Vec<DuplicateItem>,
    item_size: u64,
}

#[derive(Serialize, Tsify)]
pub struct FindDuplicatesOutput {
    groups: Vec<DuplicateGroup>,
}

#[wasm_bindgen(js_name = photosFindDuplicates)]
pub fn find_duplicates(
    input: <FindDuplicatesInput as Tsify>::JsType,
) -> Result<<FindDuplicatesOutput as Tsify>::JsType, Error> {
    let input = FindDuplicatesInput::from_js(input)?;
    let collections: Vec<_> = input
        .collections
        .into_iter()
        .map(|collection| dedup::Collection {
            id: collection.id,
            owner_id: collection.owner_id,
        })
        .collect();
    let files: Vec<_> = input
        .files
        .into_iter()
        .map(|file| dedup::File {
            id: file.id,
            collection_id: file.collection_id,
            owner_id: file.owner_id,
            hash: file.hash,
            size: file.size,
        })
        .collect();
    let groups = dedup::find_duplicates(input.user_id, &collections, &files)
        .into_iter()
        .map(|group| DuplicateGroup {
            items: group
                .items
                .into_iter()
                .map(|item| DuplicateItem {
                    file_index: item.file_index,
                    collection_ids: item.collection_ids,
                })
                .collect(),
            item_size: group.item_size,
        })
        .collect();
    FindDuplicatesOutput { groups }
        .into_js()
        .map_err(Into::into)
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct Duplicate {
    file_id: i64,
    collection_ids: Vec<i64>,
    caption: Option<String>,
    edited_name: Option<String>,
    edited_time: Option<i64>,
}

#[derive(Deserialize, Tsify)]
struct RemovalCollection {
    id: i64,
    key: String,
}

#[derive(Deserialize, Tsify)]
#[serde(rename_all = "camelCase")]
struct RemovalFile {
    id: i64,
    collection_id: i64,
    key: String,
}

#[derive(Deserialize, Tsify)]
pub struct ExecuteDuplicateRemovalInput {
    groups: Vec<Vec<Duplicate>>,
    collections: Vec<RemovalCollection>,
    files: Vec<RemovalFile>,
}

#[derive(Serialize, Tsify)]
#[serde(rename_all = "camelCase")]
pub struct DuplicateRemovalResult {
    trash_ids: Vec<i64>,
}

#[wasm_bindgen(js_name = photosExecuteDuplicateRemoval)]
pub async fn execute_duplicate_removal(
    session: &Session,
    input: <ExecuteDuplicateRemovalInput as Tsify>::JsType,
    on_progress: js_sys::Function,
) -> Result<<DuplicateRemovalResult as Tsify>::JsType, Error> {
    let input = ExecuteDuplicateRemovalInput::from_js(input)?;
    let groups = input
        .groups
        .into_iter()
        .map(|group| {
            group
                .into_iter()
                .map(|item| dedup::Duplicate {
                    file_id: item.file_id,
                    collection_ids: item.collection_ids,
                    caption: item.caption,
                    edited_name: item.edited_name,
                    edited_time: item.edited_time,
                })
                .collect()
        })
        .collect::<Vec<_>>();
    let collections = input
        .collections
        .into_iter()
        .map(|c| {
            Ok(dedup::RemovalCollection {
                id: c.id,
                key: Key::try_from_slice(&b64::decode(&c.key)?)?,
            })
        })
        .collect::<Result<Vec<_>, Error>>()?;
    let files = input
        .files
        .into_iter()
        .map(|f| {
            Ok(dedup::RemovalFile {
                id: f.id,
                collection_id: f.collection_id,
                key: Key::try_from_slice(&b64::decode(&f.key)?)?,
            })
        })
        .collect::<Result<Vec<_>, Error>>()?;
    let trash_ids = dedup::remove_duplicates(session.inner(), &groups, &collections, &files, |p| {
        let _ = on_progress.call2(
            &JsValue::UNDEFINED,
            &JsValue::from_f64(p.completed as f64),
            &JsValue::from_f64(p.total as f64),
        );
    })
    .await?;
    DuplicateRemovalResult { trash_ids }
        .into_js()
        .map_err(Into::into)
}
