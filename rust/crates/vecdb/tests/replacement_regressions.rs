use ente_vecdb::{AttrValue, Attribute, SearchParams, StorageKind, VecDb, VecDbError};
use std::error::Error;

fn normalized(mut values: Vec<f32>) -> Vec<f32> {
    let norm = values.iter().map(|value| value * value).sum::<f32>().sqrt();
    for value in &mut values {
        *value /= norm;
    }
    values
}

fn unit_vector(seed: u64, dims: usize) -> Vec<f32> {
    let mut state = seed;
    normalized(
        (0..dims)
            .map(|_| {
                state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
                let mut value = state;
                value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
                value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
                value ^= value >> 31;
                ((value >> 40) as f32 / (1u64 << 24) as f32) * 2.0 - 1.0
            })
            .collect(),
    )
}

fn assert_found(db: &VecDb, key: &str, vector: &[f32]) -> Result<(), Box<dyn Error>> {
    for exact in [true, false] {
        for (limit, max_distance) in [(None, Some(0.2)), (Some(1), None), (Some(1), Some(0.2))] {
            let params = SearchParams {
                limit,
                max_distance,
                exact,
                ..Default::default()
            };
            let found = db.search(vector, &params)?;
            assert!(
                found.iter().any(|hit| hit.key == key),
                "missing {key}, params={params:?}, stats={:?}, found={found:?}",
                db.stats()?,
            );
        }
    }
    Ok(())
}

#[derive(Clone, Copy, Debug)]
enum Churn {
    Alternating,
    Near,
    RemoveReadd,
    NearRetiredPile,
    NewKeyNearRetiredPile,
}

fn assert_churn_searchable(scenario: Churn) -> Result<(), Box<dyn Error>> {
    for dims in [32, 512] {
        for storage in [StorageKind::F32, StorageKind::I8] {
            let dir = tempfile::tempdir()?;
            let path = dir.path().join("db");
            let db = VecDb::open(&path, dims, Some(storage))?;
            let keys: Vec<String> = (0..3000).map(|index| format!("key-{index}")).collect();
            let vectors: Vec<Vec<f32>> = (0..3000)
                .map(|index| unit_vector(0xE000_0000 + index, dims))
                .collect();
            db.bulk_add(&keys, &vectors)?;
            let alternate = unit_vector(0xF000_0000, dims);
            let mut latest = vectors[7].clone();
            let rounds = match scenario {
                Churn::Alternating => 66,
                Churn::Near | Churn::RemoveReadd => 40,
                Churn::NearRetiredPile | Churn::NewKeyNearRetiredPile => 200,
            };
            for round in 0..rounds {
                latest = match scenario {
                    Churn::Near => normalized(
                        vectors[7]
                            .iter()
                            .map(|value| value + (round + 1) as f32 * 1.0e-7)
                            .collect(),
                    ),
                    Churn::RemoveReadd => vectors[7].clone(),
                    _ if round % 2 == 0 => alternate.clone(),
                    _ => vectors[7].clone(),
                };
                if matches!(scenario, Churn::RemoveReadd) {
                    assert!(db.remove("key-7")?);
                }
                db.add("key-7", &latest)?;
            }
            let mut key = "key-7";
            if matches!(scenario, Churn::NewKeyNearRetiredPile) {
                assert!(db.remove(key)?);
                key = "new-key";
            }
            if matches!(
                scenario,
                Churn::NearRetiredPile | Churn::NewKeyNearRetiredPile
            ) {
                latest = normalized(
                    vectors[7]
                        .iter()
                        .zip(&alternate)
                        .map(|(value, noise)| value + 0.05 * noise)
                        .collect(),
                );
                let distance = 1.0
                    - latest
                        .iter()
                        .zip(&vectors[7])
                        .map(|(a, b)| a * b)
                        .sum::<f32>();
                assert!(distance > 0.0001 && distance < 0.01);
                db.add(key, &latest)?;
            }
            let stats = db.stats()?;
            assert_eq!(stats.live_count, 3000);
            assert!(stats.dead_count >= rounds);
            assert_found(&db, key, &latest)?;
            db.flush()?;
            drop(db);
            let reader = VecDb::open_read_only(&path, dims, Some(storage))?;
            assert_found(&reader, key, &latest)?;
            drop(reader);
            let reopened = VecDb::open(&path, dims, Some(storage))?;
            assert_found(&reopened, key, &latest)?;
            println!(
                "{storage} {dims} {scenario:?}: dead={}, found before and after reopen",
                stats.dead_count
            );
        }
    }
    Ok(())
}

#[test]
fn alternating_replacements_remain_searchable() -> Result<(), Box<dyn Error>> {
    assert_churn_searchable(Churn::Alternating)
}

#[test]
fn near_replacements_remain_searchable() -> Result<(), Box<dyn Error>> {
    assert_churn_searchable(Churn::Near)
}

#[test]
fn remove_readd_remains_searchable() -> Result<(), Box<dyn Error>> {
    assert_churn_searchable(Churn::RemoveReadd)
}

#[test]
fn nearby_replacement_remains_searchable_beyond_the_retired_candidate_budget()
-> Result<(), Box<dyn Error>> {
    assert_churn_searchable(Churn::NearRetiredPile)
}

#[test]
fn new_key_remains_searchable_beyond_the_retired_candidate_budget() -> Result<(), Box<dyn Error>> {
    assert_churn_searchable(Churn::NewKeyNearRetiredPile)
}

#[test]
fn sole_live_key_remains_searchable_through_retired_layers() {
    for dims in [32, 512] {
        for storage in [StorageKind::F32, StorageKind::I8] {
            for remove_other in [false, true] {
                let dir = tempfile::tempdir().unwrap();
                let path = dir.path().join("db");
                let db = VecDb::open(&path, dims, Some(storage)).unwrap();
                let original = unit_vector(7, dims);
                let alternate = unit_vector(8, dims);
                if remove_other {
                    db.add("other", &alternate).unwrap();
                }
                db.add("key", &original).unwrap();
                if remove_other {
                    assert!(db.remove("other").unwrap());
                }
                for round in 0..50 {
                    let vector = if round % 2 == 0 {
                        &alternate
                    } else {
                        &original
                    };
                    db.add("key", vector).unwrap();
                    assert_found(&db, "key", vector).unwrap();
                }
                assert!(db.stats().unwrap().dead_count >= 50);
                db.flush().unwrap();
                drop(db);
                let reader = VecDb::open_read_only(&path, dims, Some(storage)).unwrap();
                assert_found(&reader, "key", &original).unwrap();
                drop(reader);
                let reopened = VecDb::open(&path, dims, Some(storage)).unwrap();
                assert_found(&reopened, "key", &original).unwrap();
            }
        }
    }
}

#[test]
fn superseded_invalid_entries_leave_the_entire_batch_unchanged() -> Result<(), Box<dyn Error>> {
    for storage in [StorageKind::F32, StorageKind::I8] {
        for unchanged_last in [false, true] {
            let dir = tempfile::tempdir()?;
            let path = dir.path().join("db");
            let db = VecDb::open(&path, 32, Some(storage))?;
            let good = unit_vector(1, 32);
            if unchanged_last {
                db.add("key", &good)?;
            }
            let stats = db.stats()?;
            let bytes = std::fs::read(&path)?;
            let keys = vec!["fresh".to_owned(), "key".to_owned(), "key".to_owned()];
            assert!(matches!(
                db.bulk_add(&keys, &[good.clone(), vec![1.0; 8], good.clone()]),
                Err(VecDbError::DimensionMismatch {
                    expected: 32,
                    actual: 8
                })
            ));
            let bad_attrs = vec![
                None,
                Some(vec![Attribute {
                    name: String::new(),
                    value: AttrValue::Bool(true),
                }]),
                None,
            ];
            assert!(matches!(
                db.bulk_add_with_attrs(
                    &keys,
                    &[good.clone(), good.clone(), good.clone()],
                    &bad_attrs
                ),
                Err(VecDbError::InvalidAttributes(_))
            ));
            let duplicate = Attribute {
                name: "name".to_owned(),
                value: AttrValue::Bool(true),
            };
            assert!(matches!(
                db.bulk_add_with_attrs(
                    &keys,
                    &[good.clone(), good.clone(), good.clone()],
                    &[None, Some(vec![duplicate.clone(), duplicate]), None]
                ),
                Err(VecDbError::InvalidAttributes(_))
            ));
            assert_eq!(db.stats()?, stats);
            assert_eq!(std::fs::read(&path)?, bytes);
            assert!(!db.contains("fresh")?);
            assert_eq!(db.contains("key")?, unchanged_last);
            let alternate = unit_vector(2, 32);
            db.bulk_add(&keys[1..], &[alternate, good.clone()])?;
            assert_eq!(db.stats()?.live_count, 1);
            assert_eq!(db.stats()?.dead_count, 0);
            assert_found(&db, "key", &good)?;
            if unchanged_last {
                assert_eq!(db.stats()?, stats);
                assert_eq!(std::fs::read(&path)?, bytes);
            }
        }
    }
    Ok(())
}
