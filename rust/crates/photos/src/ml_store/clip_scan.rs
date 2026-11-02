use std::num::NonZeroUsize;

use super::fill::decode_clip;
use super::{Error, Index, MlStore, Result};
use crate::face_clustering::dot;

const SCAN_PAGE: NonZeroUsize = NonZeroUsize::new(1000).unwrap();

#[derive(Clone, Debug, PartialEq)]
pub struct ClipQuery {
    pub embedding: Vec<f32>,
    pub minimum_similarity: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClipSimilarity {
    pub file_id: i64,
    pub similarity: f64,
}

impl MlStore {
    pub fn scan_clip_similarities(
        &self,
        queries: &[ClipQuery],
    ) -> Result<Vec<Vec<ClipSimilarity>>> {
        for query in queries {
            if query.embedding.len() != Index::Clip.dims() {
                return Err(Error::InvalidArgument(format!(
                    "clip query has {} values, expected {}",
                    query.embedding.len(),
                    Index::Clip.dims()
                )));
            }
        }
        let mut similarities = vec![Vec::new(); queries.len()];
        let mut before_file_id = None;
        loop {
            let page = self.db.get_clip_rows_before(before_file_id, SCAN_PAGE)?;
            let Some(last_row) = page.last() else {
                break;
            };
            before_file_id = Some(last_row.file_id);
            for row in page {
                let Some(embedding) = decode_clip(&row.file_id.to_string(), &row.embedding) else {
                    continue;
                };
                for (query, matches) in queries.iter().zip(&mut similarities) {
                    let similarity = dot(&embedding, &query.embedding);
                    if similarity >= query.minimum_similarity {
                        matches.push(ClipSimilarity {
                            file_id: row.file_id,
                            similarity,
                        });
                    }
                }
            }
        }
        for matches in &mut similarities {
            matches.sort_by(|first, second| second.similarity.total_cmp(&first.similarity));
        }
        Ok(similarities)
    }
}

#[cfg(test)]
mod tests {
    use ente_vecdb::SearchParams;

    use super::{ClipQuery, ClipSimilarity};
    use crate::ml_db::{CLIP_EMBEDDING_DIMENSIONS, ClipEmbedding};
    use crate::ml_store::tests::{clip, clips, one_hot, open, open_with_unusable_clip_index};
    use crate::ml_store::{Error, Index, MlStore};

    fn query(hot: usize, minimum_similarity: f64) -> ClipQuery {
        ClipQuery {
            embedding: one_hot(CLIP_EMBEDDING_DIMENSIONS, hot),
            minimum_similarity,
        }
    }

    fn matching_every_file(minimum_similarity: f64) -> ClipQuery {
        ClipQuery {
            embedding: vec![1.0; CLIP_EMBEDDING_DIMENSIONS],
            minimum_similarity,
        }
    }

    fn scoring(file_id: i64, similarity: f64) -> ClipEmbedding {
        let mut row = clip(0);
        row.file_id = file_id;
        row.embedding[0] = similarity;
        row
    }

    fn scored(file_id: i64, similarity: f64) -> ClipSimilarity {
        ClipSimilarity {
            file_id,
            similarity,
        }
    }

    fn file_ids(store: &MlStore, query: ClipQuery) -> Vec<i64> {
        store.scan_clip_similarities(&[query]).unwrap()[0]
            .iter()
            .map(|similarity| similarity.file_id)
            .collect()
    }

    #[test]
    fn scan_returns_files_at_or_above_the_threshold_best_first() {
        let (_directory, store) = open();
        store
            .db()
            .insert_clip_rows(&[
                scoring(1, 0.25),
                scoring(2, 0.75),
                scoring(3, 0.5),
                scoring(4, 0.125),
            ])
            .unwrap();

        assert_eq!(
            store.scan_clip_similarities(&[query(0, 0.25)]).unwrap(),
            [vec![scored(2, 0.75), scored(3, 0.5), scored(1, 0.25)]]
        );
    }

    #[test]
    fn each_query_keeps_its_own_threshold_and_position() {
        let (_directory, store) = open();
        store.db().insert_clip_rows(&clips([1, 2])).unwrap();

        assert_eq!(
            store
                .scan_clip_similarities(&[query(2, 0.5), query(1, 1.5), query(1, 0.5)])
                .unwrap(),
            [vec![scored(2, 1.0)], vec![], vec![scored(1, 1.0)]]
        );
    }

    #[test]
    fn scan_reads_every_page_exactly_once() {
        let (_directory, store) = open();
        store.db().insert_clip_rows(&clips(1..=2500)).unwrap();

        assert_eq!(
            file_ids(&store, matching_every_file(0.0)),
            (1..=2500).rev().collect::<Vec<_>>()
        );
    }

    #[test]
    fn scan_answers_while_the_clip_index_is_unusable() {
        let (_directory, store) = open_with_unusable_clip_index();
        store.db().insert_clip_rows(&clips([1])).unwrap();

        assert!(matches!(
            store.search(
                Index::Clip,
                &query(1, 0.5).embedding,
                &SearchParams::default()
            ),
            Err(Error::Index(_))
        ));
        assert_eq!(file_ids(&store, query(1, 0.5)), [1]);
    }

    #[test]
    fn scan_skips_the_rows_the_index_rejects() {
        let (_directory, store) = open();
        let mut rows = clips([1, 2, 3, 4]);
        rows[1].embedding[0] = f64::INFINITY;
        rows[2].embedding.pop();
        rows[3].embedding.clear();
        store.db().insert_clip_rows(&rows).unwrap();

        assert_eq!(file_ids(&store, matching_every_file(0.0)), [1]);
    }

    #[test]
    fn scan_rejects_queries_of_the_wrong_length() {
        let (_directory, store) = open();
        let mut short = query(0, 0.0);
        short.embedding.pop();

        assert!(matches!(
            store.scan_clip_similarities(&[query(0, 0.0), short]),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn an_empty_table_gives_each_query_an_empty_result() {
        let (_directory, store) = open();

        assert_eq!(
            store
                .scan_clip_similarities(&[query(0, 0.0), query(1, 0.0)])
                .unwrap(),
            [vec![], vec![]]
        );
    }
}
