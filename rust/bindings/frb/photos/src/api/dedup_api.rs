use ente_photos::dedup;

pub struct DedupCollection {
    pub id: i64,
    pub owner_id: i64,
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

pub struct DuplicateAddition {
    pub collection_id: i64,
    pub file_ids: Vec<i64>,
}

pub struct DuplicateRemovalPlan {
    pub additions: Vec<DuplicateAddition>,
    pub trash_ids: Vec<i64>,
}

pub fn plan_duplicate_removal(groups: Vec<Vec<Duplicate>>) -> DuplicateRemovalPlan {
    let groups: Vec<_> = groups
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
    let plan = dedup::plan_removal(&groups);
    DuplicateRemovalPlan {
        additions: plan
            .additions
            .into_iter()
            .map(|addition| DuplicateAddition {
                collection_id: addition.collection_id,
                file_ids: addition.file_ids,
            })
            .collect(),
        trash_ids: plan.trash_ids,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detection_to_removal_preserves_memberships_and_captioned_file() {
        let collections = vec![
            DedupCollection {
                id: 11,
                owner_id: 1,
            },
            DedupCollection {
                id: 12,
                owner_id: 1,
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
        let file_ids: Vec<_> = files.iter().map(|file| file.id).collect();
        let groups = find_duplicates(1, collections, files);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].item_size, 100);
        assert_eq!(groups[0].items.len(), 2);
        assert_eq!(groups[0].items[0].file_index, 0);
        assert_eq!(groups[0].items[0].collection_ids, vec![11, 12]);
        assert_eq!(groups[0].items[1].file_index, 2);

        let selected = groups
            .into_iter()
            .map(|group| {
                group
                    .items
                    .into_iter()
                    .map(|item| {
                        let file_id = file_ids[item.file_index];
                        Duplicate {
                            file_id,
                            collection_ids: item.collection_ids,
                            caption: (file_id == 2).then(|| "keep caption".into()),
                            edited_name: (file_id == 1).then(|| "edited name".into()),
                            edited_time: Some(123),
                        }
                    })
                    .collect()
            })
            .collect();
        let plan = plan_duplicate_removal(selected);
        assert_eq!(plan.trash_ids, vec![1]);
        assert_eq!(plan.additions.len(), 1);
        assert_eq!(plan.additions[0].collection_id, 11);
        assert_eq!(plan.additions[0].file_ids, vec![2]);
    }
}
