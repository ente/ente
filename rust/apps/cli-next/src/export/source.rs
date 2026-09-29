use anyhow::{Context, Result};
use ente_core::Session;
use ente_photos_export::{CollectionEntry, FileEntry, Source};

use crate::{
    core_db::{Db, OptionalExtension, SqliteResult, params},
    replica::{AlbumRecord, FileRecord, Replica, read_json},
};

pub struct ReplicaSource<'a> {
    replica: Replica<'a>,
    user_id: i64,
}

impl<'a> ReplicaSource<'a> {
    pub fn new(db: &'a mut Db, user_id: i64) -> Self {
        Self {
            replica: Replica::new(db, user_id),
            user_id,
        }
    }

    fn collection(&self, record: AlbumRecord, name: Option<String>) -> CollectionEntry {
        let id = record.remote.id;
        let favorites = record.remote.kind == "favorites" && record.remote.owner.id == self.user_id;
        let value = record
            .album(self.user_id)
            .and_then(|album| Ok((album, record.documents.context("metadata is unavailable")?)));
        let name = value
            .as_ref()
            .ok()
            .map(|(album, _)| album.name.clone())
            .or(name);
        CollectionEntry {
            id,
            name,
            favorites,
            value,
        }
    }

    fn entry(&self, record: FileRecord) -> FileEntry {
        let id = record.remote.id;
        let value = record
            .file(self.user_id)
            .and_then(|file| Ok((file, record.documents.context("metadata is unavailable")?)));
        FileEntry { id, value }
    }
}

impl Source for ReplicaSource<'_> {
    async fn refresh_catalog(&mut self, session: &Session) -> Result<()> {
        self.replica.sync_collections(session).await
    }

    fn catalog_page(&self, after: i64) -> Result<Vec<CollectionEntry>> {
        let next: Option<(AlbumRecord, Option<String>)> = self.replica.db.read(|db| {
            Ok(db
                .query_row(
                    "SELECT id,record,name FROM photos_collections WHERE id>?1 ORDER BY id LIMIT 1",
                    [after],
                    |r| Ok((read_json(r, 1)?, r.get(2)?)),
                )
                .optional()?)
        })?;
        Ok(next
            .into_iter()
            .map(|(record, name)| self.collection(record, name))
            .collect())
    }

    async fn refresh_album(&mut self, session: &Session, id: i64) -> Result<CollectionEntry> {
        self.replica.retry_album(session, id)?;
        let record = self
            .replica
            .album_record(id)?
            .context("missing album source")?;
        let entry = self.collection(record, None);
        let (album, documents) = entry.value?;
        self.replica.sync_album_files(session, &album).await?;
        Ok(CollectionEntry {
            value: Ok((album, documents)),
            ..entry
        })
    }

    fn file_page(&self, album: i64, after: i64) -> Result<Vec<FileEntry>> {
        let records: Vec<FileRecord> = self.replica.db.read(|db| {
            let mut query = db.prepare(
                "SELECT record FROM photos_files WHERE collection_id=?1 AND id>?2 ORDER BY id LIMIT 128",
            )?;
            Ok(query
                .query_map(params![album, after], |r| read_json(r, 0))?
                .collect::<SqliteResult<_>>()?)
        })?;
        Ok(records
            .into_iter()
            .map(|record| self.entry(record))
            .collect())
    }

    fn favorite_page(&self, after: i64) -> Result<Vec<i64>> {
        Ok(self.replica.db.read(|db| {
            let mut query = db.prepare(
                "SELECT DISTINCT f.id FROM photos_files f JOIN photos_collections c ON c.id=f.collection_id WHERE f.id>?1 AND json_extract(c.record,'$.remote.type')='favorites' AND json_extract(c.record,'$.remote.owner.id')=?2 ORDER BY f.id LIMIT 128",
            )?;
            Ok(query
                .query_map(params![after, self.user_id], |r| r.get(0))?
                .collect::<SqliteResult<_>>()?)
        })?)
    }

    fn file(&self, album: i64, id: i64) -> Result<FileEntry> {
        Ok(self.entry(
            self.replica
                .file_record(album, id)?
                .context("missing chosen file source")?,
        ))
    }
}
