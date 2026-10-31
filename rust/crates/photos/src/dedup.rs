use std::collections::{HashMap, HashSet};

mod removal;

pub use removal::{
    RemovalCollection, RemovalError, RemovalFile, RemovalProgress, execute_removal,
    remove_duplicates,
};

pub struct Collection {
    pub id: i64,
    pub owner_id: i64,
}

pub struct File {
    pub id: i64,
    pub collection_id: i64,
    pub owner_id: i64,
    pub hash: Option<String>,
    pub size: Option<u64>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Item {
    pub file_index: usize,
    pub collection_ids: Vec<i64>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Group {
    pub items: Vec<Item>,
    pub item_size: u64,
}

pub fn find_duplicates(user_id: i64, collections: &[Collection], files: &[File]) -> Vec<Group> {
    let allowed: HashSet<_> = collections
        .iter()
        .filter(|collection| collection.owner_id == user_id)
        .map(|collection| collection.id)
        .collect();
    let mut by_id = HashMap::<i64, (usize, usize)>::new();
    let mut by_hash = HashMap::<&str, usize>::new();
    let mut groups = Vec::<Group>::new();
    for (file_index, file) in files.iter().enumerate() {
        if file.owner_id != user_id || !allowed.contains(&file.collection_id) {
            continue;
        }
        let Some(hash) = file.hash.as_deref().filter(|hash| !hash.is_empty()) else {
            continue;
        };
        if let Some(&(group_index, item_index)) = by_id.get(&file.id) {
            let ids = &mut groups[group_index].items[item_index].collection_ids;
            if !ids.contains(&file.collection_id) {
                ids.push(file.collection_id);
            }
            continue;
        }
        let group_index = *by_hash.entry(hash).or_insert_with(|| {
            groups.push(Group {
                items: Vec::new(),
                item_size: 0,
            });
            groups.len() - 1
        });
        let group = &mut groups[group_index];
        by_id.insert(file.id, (group_index, group.items.len()));
        group.items.push(Item {
            file_index,
            collection_ids: vec![file.collection_id],
        });
        if group.item_size == 0 {
            group.item_size = file.size.unwrap_or(0);
        }
    }
    groups
        .into_iter()
        .filter(|group| group.items.len() > 1 && group.item_size != 0)
        .collect()
}

#[derive(Default)]
pub struct Duplicate {
    pub file_id: i64,
    pub collection_ids: Vec<i64>,
    pub caption: Option<String>,
    pub edited_name: Option<String>,
    pub edited_time: Option<i64>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Addition {
    pub collection_id: i64,
    pub file_ids: Vec<i64>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct RemovalPlan {
    pub additions: Vec<Addition>,
    pub trash_ids: Vec<i64>,
}

pub fn plan_removal(groups: &[Vec<Duplicate>]) -> RemovalPlan {
    let mut plan = RemovalPlan::default();
    let mut by_collection = HashMap::<i64, usize>::new();
    for items in groups {
        if items.len() < 2 {
            continue;
        }
        let retained = items
            .iter()
            .find(|item| {
                item.caption
                    .as_ref()
                    .is_some_and(|caption| !caption.is_empty())
            })
            .or_else(|| {
                items.iter().find(|item| {
                    item.edited_name.as_ref().map_or_else(
                        || item.edited_time.is_some_and(|time| time != 0),
                        |name| !name.is_empty(),
                    )
                })
            })
            .unwrap_or(&items[0]);
        let mut memberships: HashSet<_> = retained.collection_ids.iter().copied().collect();
        for item in items {
            if item.file_id == retained.file_id {
                continue;
            }
            plan.trash_ids.push(item.file_id);
            for &collection_id in &item.collection_ids {
                if !memberships.insert(collection_id) {
                    continue;
                }
                let index = *by_collection.entry(collection_id).or_insert_with(|| {
                    plan.additions.push(Addition {
                        collection_id,
                        file_ids: Vec::new(),
                    });
                    plan.additions.len() - 1
                });
                plan.additions[index].file_ids.push(retained.file_id);
            }
        }
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(id: i64, collection_id: i64, hash: &str, size: Option<u64>) -> File {
        File {
            id,
            collection_id,
            owner_id: 1,
            hash: Some(hash.into()),
            size,
        }
    }

    fn collections() -> Vec<Collection> {
        vec![
            Collection {
                id: 11,
                owner_id: 1,
            },
            Collection {
                id: 12,
                owner_id: 1,
            },
            Collection {
                id: 13,
                owner_id: 2,
            },
        ]
    }

    #[test]
    fn groups_distinct_owned_files_and_preserves_all_eligible_memberships() {
        let mut foreign = file(3, 11, "hash", Some(100));
        foreign.owner_id = 2;
        let files = vec![
            file(1, 11, "hash", Some(100)),
            file(1, 12, "hash", Some(100)),
            file(1, 12, "hash", Some(100)),
            file(2, 12, "hash", Some(100)),
            foreign,
            file(4, 13, "hash", Some(100)),
            file(5, 99, "hash", Some(100)),
            file(6, 11, "", Some(100)),
        ];
        assert_eq!(
            find_duplicates(1, &collections(), &files),
            vec![Group {
                items: vec![
                    Item {
                        file_index: 0,
                        collection_ids: vec![11, 12]
                    },
                    Item {
                        file_index: 3,
                        collection_ids: vec![12]
                    }
                ],
                item_size: 100,
            }]
        );
    }

    #[test]
    fn ignores_singletons_symlinks_missing_hashes_and_unknown_sizes() {
        let files = vec![
            file(1, 11, "single", Some(100)),
            file(1, 12, "single", Some(100)),
            file(2, 11, "no-size", None),
            file(3, 11, "no-size", Some(0)),
            File {
                hash: None,
                ..file(4, 11, "", Some(100))
            },
            File {
                hash: None,
                ..file(5, 11, "", Some(100))
            },
        ];
        assert!(find_duplicates(1, &collections(), &files).is_empty());
        assert!(find_duplicates(1, &[], &files).is_empty());
    }

    #[test]
    fn uses_first_nonzero_size_without_requiring_matching_live_photo_zip_sizes() {
        let files = vec![
            file(1, 11, "image:video", None),
            file(2, 11, "image:video", Some(150)),
            file(3, 12, "image:video", Some(200)),
            file(4, 11, "other", Some(90)),
            file(5, 11, "other", Some(100)),
        ];
        let groups = find_duplicates(1, &collections(), &files);
        assert_eq!(
            groups
                .iter()
                .map(|group| group.item_size)
                .collect::<Vec<_>>(),
            vec![150, 90]
        );
        assert_eq!(groups[0].items.len(), 3);
    }

    fn duplicate(id: i64, collection_ids: &[i64]) -> Duplicate {
        Duplicate {
            file_id: id,
            collection_ids: collection_ids.into(),
            ..Default::default()
        }
    }

    #[test]
    fn retains_captions_before_edits_and_batches_missing_album_memberships() {
        let groups = vec![
            vec![
                Duplicate {
                    edited_name: Some("renamed".into()),
                    ..duplicate(1, &[11, 12])
                },
                Duplicate {
                    caption: Some("caption".into()),
                    ..duplicate(2, &[12])
                },
                duplicate(3, &[11, 13]),
            ],
            vec![duplicate(4, &[12]), duplicate(5, &[11])],
        ];
        assert_eq!(
            plan_removal(&groups),
            RemovalPlan {
                additions: vec![
                    Addition {
                        collection_id: 11,
                        file_ids: vec![2, 4]
                    },
                    Addition {
                        collection_id: 13,
                        file_ids: vec![2]
                    }
                ],
                trash_ids: vec![1, 3, 5],
            }
        );
    }

    #[test]
    fn retention_ties_follow_input_order_and_empty_edits_do_not_win() {
        let mut items = vec![
            duplicate(1, &[11]),
            duplicate(2, &[11]),
            duplicate(3, &[11]),
        ];
        assert_eq!(plan_removal(&[vec![]]), RemovalPlan::default());
        assert_eq!(
            plan_removal(&[vec![duplicate(1, &[11])]]),
            RemovalPlan::default()
        );
        items[1].edited_time = Some(123);
        assert_eq!(
            plan_removal(std::slice::from_ref(&items)).trash_ids,
            vec![1, 3]
        );
        items[1].edited_name = Some(String::new());
        assert_eq!(
            plan_removal(std::slice::from_ref(&items)).trash_ids,
            vec![2, 3]
        );
        items[1].caption = Some("first caption".into());
        items[2].caption = Some("second caption".into());
        assert_eq!(
            plan_removal(std::slice::from_ref(&items)).trash_ids,
            vec![1, 3]
        );
        items[1].caption = Some(String::new());
        assert_eq!(
            plan_removal(std::slice::from_ref(&items)).trash_ids,
            vec![1, 2]
        );
        assert!(plan_removal(&[items]).additions.is_empty());
    }

    #[test]
    fn detection_and_removal_preserve_every_album_membership_combination() {
        let collections: Vec<_> = (11..=13).map(|id| Collection { id, owner_id: 1 }).collect();
        for first in 1..8 {
            for second in 1..8 {
                for third in 1..8 {
                    let mut files = Vec::new();
                    let mut memberships = HashMap::<i64, HashSet<i64>>::new();
                    for (index, mask) in [first, second, third].into_iter().enumerate() {
                        let id = index as i64 + 1;
                        for bit in 0..3 {
                            if mask & (1 << bit) != 0 {
                                let collection_id = 11 + bit;
                                files.push(file(id, collection_id, "hash", Some(100)));
                                memberships.entry(collection_id).or_default().insert(id);
                            }
                        }
                    }
                    let expected_albums: HashSet<_> = memberships.keys().copied().collect();
                    let groups = find_duplicates(1, &collections, &files);
                    assert_eq!(groups.len(), 1);
                    assert_eq!(groups[0].items.len(), 3);
                    let selected: Vec<_> = groups
                        .into_iter()
                        .map(|group| {
                            group
                                .items
                                .into_iter()
                                .map(|item| {
                                    let id = files[item.file_index].id;
                                    Duplicate {
                                        caption: (id == 2).then(|| "keep".into()),
                                        ..duplicate(id, &item.collection_ids)
                                    }
                                })
                                .collect()
                        })
                        .collect();
                    let plan = plan_removal(&selected);
                    assert_eq!(plan.trash_ids, vec![1, 3]);
                    for addition in plan.additions {
                        memberships
                            .entry(addition.collection_id)
                            .or_default()
                            .extend(addition.file_ids);
                    }
                    for ids in memberships.values_mut() {
                        ids.retain(|id| !plan.trash_ids.contains(id));
                        assert_eq!(*ids, HashSet::from([2]));
                    }
                    assert_eq!(
                        memberships.keys().copied().collect::<HashSet<_>>(),
                        expected_albums
                    );
                }
            }
        }
    }
}
