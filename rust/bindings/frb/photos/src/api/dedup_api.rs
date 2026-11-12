#[cfg(any(feature = "flutter", frb_expand))]
use ente_core::crypto::Key;
#[cfg(any(feature = "flutter", frb_expand))]
use ente_frb_lib::session::{Session, SessionError};
use ente_photos::dedup;

#[cfg(any(feature = "flutter", frb_expand))]
use crate::frb_generated::StreamSink;

pub struct DedupCollection {
    pub id: i64,
    pub owner_id: i64,
    pub is_hidden: bool,
}

pub struct DedupFile {
    pub id: i64,
    pub collection_id: i64,
    pub owner_id: i64,
    pub hash: Option<String>,
    pub size: Option<u64>,
}

pub struct DuplicateItem {
    pub file_index: usize,
    pub collection_ids: Vec<i64>,
}

pub struct DuplicateGroup {
    pub items: Vec<DuplicateItem>,
    pub item_size: u64,
}

pub fn find_duplicates(
    user_id: i64,
    collections: Vec<DedupCollection>,
    files: Vec<DedupFile>,
) -> Vec<DuplicateGroup> {
    let collections: Vec<_> = collections
        .into_iter()
        .map(|collection| dedup::Collection {
            id: collection.id,
            owner_id: collection.owner_id,
            is_hidden: collection.is_hidden,
        })
        .collect();
    let files: Vec<_> = files
        .into_iter()
        .map(|file| dedup::File {
            id: file.id,
            collection_id: file.collection_id,
            owner_id: file.owner_id,
            hash: file.hash,
            size: file.size,
        })
        .collect();
    dedup::find_duplicates(user_id, &collections, &files)
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
        .collect()
}

pub struct Duplicate {
    pub file_id: i64,
    pub collection_ids: Vec<i64>,
    pub caption: Option<String>,
    pub edited_name: Option<String>,
    pub edited_time: Option<i64>,
}

pub struct RemovalCollection {
    pub id: i64,
    pub key: Vec<u8>,
}

pub struct RemovalFile {
    pub id: i64,
    pub collection_id: i64,
    pub key: Vec<u8>,
}

pub struct ExecuteDuplicateRemovalInput {
    pub groups: Vec<Vec<Duplicate>>,
    pub collections: Vec<RemovalCollection>,
    pub files: Vec<RemovalFile>,
}

#[cfg(any(feature = "flutter", frb_expand))]
pub enum DuplicateRemovalEvent {
    Progress { completed: usize, total: usize },
    Completed { trash_ids: Vec<i64> },
    Failed { error: SessionError },
}

#[cfg(any(feature = "flutter", frb_expand))]
pub async fn execute_duplicate_removal(
    session: &Session,
    input: ExecuteDuplicateRemovalInput,
    events: StreamSink<DuplicateRemovalEvent>,
) {
    let result = remove_duplicates(session, input, &events).await;
    let _ = events.add(match result {
        Ok(trash_ids) => DuplicateRemovalEvent::Completed { trash_ids },
        Err(error) => DuplicateRemovalEvent::Failed { error },
    });
}

#[cfg(any(feature = "flutter", frb_expand))]
async fn remove_duplicates(
    session: &Session,
    input: ExecuteDuplicateRemovalInput,
    events: &StreamSink<DuplicateRemovalEvent>,
) -> Result<Vec<i64>, SessionError> {
    let groups: Vec<_> = input
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
        .collect();
    let collections = input
        .collections
        .into_iter()
        .map(|collection| {
            Ok(dedup::RemovalCollection {
                id: collection.id,
                key: Key::try_from_slice(&collection.key)?,
            })
        })
        .collect::<Result<Vec<_>, SessionError>>()?;
    let files = input
        .files
        .into_iter()
        .map(|file| {
            Ok(dedup::RemovalFile {
                id: file.id,
                collection_id: file.collection_id,
                key: Key::try_from_slice(&file.key)?,
            })
        })
        .collect::<Result<Vec<_>, SessionError>>()?;
    dedup::remove_duplicates(
        session.as_ref(),
        &groups,
        &collections,
        &files,
        |progress| {
            let _ = events.add(DuplicateRemovalEvent::Progress {
                completed: progress.completed,
                total: progress.total,
            });
        },
    )
    .await
    .map_err(SessionError::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detection_preserves_memberships() {
        let collections = vec![
            DedupCollection {
                id: 11,
                owner_id: 1,
                is_hidden: false,
            },
            DedupCollection {
                id: 12,
                owner_id: 1,
                is_hidden: false,
            },
        ];
        let files: Vec<_> = [(1, 11), (1, 12), (2, 12)]
            .into_iter()
            .map(|(id, collection_id)| DedupFile {
                id,
                collection_id,
                owner_id: 1,
                hash: Some("hash".into()),
                size: Some(100),
            })
            .collect();
        let groups = find_duplicates(1, collections, files);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].item_size, 100);
        assert_eq!(groups[0].items.len(), 2);
        assert_eq!(groups[0].items[0].file_index, 0);
        assert_eq!(groups[0].items[0].collection_ids, vec![11, 12]);
        assert_eq!(groups[0].items[1].file_index, 2);
    }
}
