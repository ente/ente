use std::future::Future;

use anyhow::Result;
use ente_core::Session;
use ente_photos::{collections::Collection, files::File, source::Documents};

pub struct CollectionEntry {
    pub id: i64,
    pub name: Option<String>,
    pub favorites: bool,
    pub value: Result<(Collection, Documents)>,
}

pub struct FileEntry {
    pub id: i64,
    pub value: Result<(File, Documents)>,
}

pub trait Source {
    fn refresh_catalog(&mut self, session: &Session) -> impl Future<Output = Result<()>>;
    fn catalog_page(&self, after: i64) -> Result<Vec<CollectionEntry>>;
    fn refresh_album(
        &mut self,
        session: &Session,
        id: i64,
    ) -> impl Future<Output = Result<CollectionEntry>>;
    fn file_page(&self, album: i64, after: i64) -> Result<Vec<FileEntry>>;
    fn favorite_page(&self, after: i64) -> Result<Vec<i64>>;
    fn file(&self, album: i64, id: i64) -> Result<FileEntry>;
}
