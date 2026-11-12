mod text_embeddings;

use text_embeddings::{QUERY_EMBEDDINGS, TextEmbedding};

use crate::ml_store::{ClipQuery, FillState, Index, MlStore, Result, SearchParams};

#[derive(Clone, Debug, PartialEq)]
pub struct DiscoverQuery {
    pub query: String,
    pub minimum_similarity: f64,
}

pub fn matches(store: &MlStore, queries: &[DiscoverQuery]) -> Result<Vec<Vec<i64>>> {
    let (positions, clip_queries): (Vec<usize>, Vec<ClipQuery>) = queries
        .iter()
        .enumerate()
        .filter_map(|(position, query)| Some((position, clip_query(query)?)))
        .unzip();
    let found = match index_matches(store, &clip_queries) {
        Ok(Some(found)) => found,
        Ok(None) => scan_matches(store, &clip_queries)?,
        Err(error) => {
            log::warn!("Discover index search failed, scanning the clip table instead: {error}");
            scan_matches(store, &clip_queries)?
        }
    };
    let mut matches = vec![Vec::new(); queries.len()];
    for (position, file_ids) in positions.into_iter().zip(found) {
        matches[position] = file_ids;
    }
    Ok(matches)
}

fn clip_query(query: &DiscoverQuery) -> Option<ClipQuery> {
    let Some((_, embedding)) = QUERY_EMBEDDINGS
        .iter()
        .find(|(text, _)| *text == query.query)
    else {
        log::warn!("no Discover text embedding for {:?}", query.query);
        return None;
    };
    Some(ClipQuery {
        embedding: unit(embedding),
        minimum_similarity: query.minimum_similarity,
    })
}

fn unit(embedding: &TextEmbedding) -> Vec<f32> {
    let norm = embedding
        .iter()
        .map(|&value| f32::from(value).powi(2))
        .sum::<f32>()
        .sqrt();
    embedding
        .iter()
        .map(|&value| f32::from(value) / norm)
        .collect()
}

fn index_matches(store: &MlStore, queries: &[ClipQuery]) -> Result<Option<Vec<Vec<i64>>>> {
    if store.fill_state(Index::Clip)? != FillState::Filled {
        return Ok(None);
    }
    queries
        .iter()
        .map(|query| {
            let params = SearchParams {
                limit: None,
                max_distance: Some((1.0 - query.minimum_similarity) as f32),
                exact: true,
                allowed_keys: None,
            };
            Ok(store
                .search(Index::Clip, &query.embedding, &params)?
                .into_iter()
                .filter_map(|found| found.key.parse().ok())
                .collect())
        })
        .collect::<Result<_>>()
        .map(Some)
}

fn scan_matches(store: &MlStore, queries: &[ClipQuery]) -> Result<Vec<Vec<i64>>> {
    Ok(store
        .scan_clip_similarities(queries)?
        .into_iter()
        .map(|similarities| {
            similarities
                .into_iter()
                .map(|similarity| similarity.file_id)
                .collect()
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;
    use std::path::Path;

    use super::text_embeddings::QUERY_EMBEDDINGS;
    use super::{DiscoverQuery, matches, unit};
    use crate::ml_db::ClipEmbedding;
    use crate::ml_store::{Index, MlStore};

    fn query(text: &str, minimum_similarity: f64) -> DiscoverQuery {
        DiscoverQuery {
            query: text.to_owned(),
            minimum_similarity,
        }
    }

    fn clip(file_id: i64, embedding: Vec<f32>) -> ClipEmbedding {
        ClipEmbedding {
            file_id,
            embedding: embedding.into_iter().map(f64::from).collect(),
            version: 1,
        }
    }

    fn normalized(vector: Vec<f32>) -> Vec<f32> {
        let norm = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
        vector.into_iter().map(|value| value / norm).collect()
    }

    fn prompt_rows() -> (String, Vec<ClipEmbedding>) {
        let (text, embedding) = &QUERY_EMBEDDINGS[0];
        let prompt = unit(embedding);
        let other = unit(&QUERY_EMBEDDINGS[1].1);
        let overlap: f32 = prompt.iter().zip(&other).map(|(a, b)| a * b).sum();
        let orthogonal = normalized(
            other
                .iter()
                .zip(&prompt)
                .map(|(o, p)| o - overlap * p)
                .collect(),
        );
        let between = normalized(
            prompt
                .iter()
                .zip(&orthogonal)
                .map(|(p, o)| 0.6 * p + 0.8 * o)
                .collect(),
        );
        (
            text.to_string(),
            vec![clip(1, orthogonal), clip(2, between), clip(3, prompt)],
        )
    }

    fn queries(prompt: &str) -> [DiscoverQuery; 4] {
        [
            query(prompt, 0.99),
            query("not a discover prompt", -1.0),
            query(prompt, 0.5),
            query(prompt, -1.0),
        ]
    }

    fn open(directory: &Path) -> MlStore {
        MlStore::open(directory.join("ente.ml.db")).unwrap()
    }

    #[test]
    fn scans_until_the_index_is_filled_then_searches_the_index() {
        let directory = tempfile::tempdir().unwrap();
        let store = open(directory.path());
        let (prompt, rows) = prompt_rows();
        store.db().insert_clip_rows(&rows).unwrap();
        let queries = queries(&prompt);

        let scanned = matches(&store, &queries).unwrap();
        store.fill_clip_index(false).unwrap();
        store
            .db()
            .insert_clip_rows(&[clip(4, unit(&QUERY_EMBEDDINGS[0].1))])
            .unwrap();
        let indexed = matches(&store, &queries).unwrap();

        assert_eq!(scanned[0], [3]);
        assert!(scanned[1].is_empty());
        assert_eq!(scanned[2], [3, 2]);
        assert_eq!(scanned[3], [3, 2, 1]);
        assert_eq!(indexed, scanned);
    }

    #[test]
    fn scans_when_the_index_is_unusable() {
        let directory = tempfile::tempdir().unwrap();
        let store = open(directory.path());
        std::fs::create_dir(directory.path().join("ente.ml.vecdb.clip")).unwrap();
        let (prompt, rows) = prompt_rows();
        store.db().insert_clip_rows(&rows).unwrap();

        assert!(store.fill_state(Index::Clip).is_err());
        assert_eq!(
            matches(&store, &queries(&prompt)).unwrap(),
            [vec![3], vec![], vec![3, 2], vec![3, 2, 1]]
        );
    }

    #[test]
    fn every_bundled_discover_prompt_has_an_embedding() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../mobile/apps/photos/assets/discover.json");
        let prompts: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let bundled: HashSet<&str> = prompts["prompts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|prompt| prompt["query"].as_str().unwrap())
            .collect();
        let embedded: HashSet<&str> = QUERY_EMBEDDINGS.iter().map(|(text, _)| *text).collect();

        assert_eq!(
            bundled, embedded,
            "regenerate the embeddings with `cargo run -p ente-ml --example text_embeddings --release`"
        );
    }
}
