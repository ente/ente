use super::*;
use anyhow::{Result, bail};
use ente_core::{Session, crypto::SecretKey, http::ApiConfig};
use ente_photos::{collections, files, source::Documents};
use ente_photos_export::{CollectionEntry, Export, FileEntry, Options, Source, Summary};
use std::{collections::BTreeMap, path::PathBuf};
use tokio::sync::watch;

pub(super) struct Catalog {
    pub user: i64,
    pub key: Key,
    pub albums: BTreeMap<i64, String>,
    pub categories: BTreeMap<i64, (bool, bool)>,
    pub unreadable_album: Option<i64>,
    pub files: BTreeMap<(i64, i64), Value>,
    pub failed_album: Option<i64>,
}

impl Catalog {
    fn album(&self, id: i64) -> CollectionEntry {
        let name = self.albums[&id].clone();
        let (shared, hidden) = self.categories.get(&id).copied().unwrap_or_default();
        let metadata = self.categories.get(&id).map(|_| {
            serde_json::to_vec(&json!({"visibility": if hidden { 2 } else { 0 }})).unwrap()
        });
        CollectionEntry {
            id,
            owner_id: self.user + i64::from(shared),
            name: Some(name.clone()),
            favorites: false,
            value: Ok((
                collections::Collection {
                    id,
                    key: Key::from_bytes(*self.key.as_bytes()),
                    name,
                    kind: collections::Kind::Album,
                    visibility: if hidden {
                        collections::Visibility::Hidden
                    } else {
                        collections::Visibility::Visible
                    },
                    owner_id: self.user + i64::from(shared),
                    updated_at_micros: 100,
                },
                Documents {
                    original: Vec::new(),
                    public: None,
                    private: if shared { None } else { metadata.clone() },
                    shared: if shared { metadata } else { None },
                },
            )),
        }
    }

    fn entry(&self, record: &Value) -> Result<FileEntry> {
        let remote = serde_json::from_value(record.clone())?;
        let (key, documents) = files::decrypt(&remote, &self.key)?;
        let file = files::interpret(&remote, &key, &documents, self.user)?;
        Ok(FileEntry {
            id: file.id,
            value: Ok((file, documents)),
        })
    }
}

impl Source for Catalog {
    async fn refresh_catalog(&mut self, _: &Session) -> Result<()> {
        Ok(())
    }
    fn catalog_page(&self, after: i64) -> Result<Vec<CollectionEntry>> {
        Ok(self
            .albums
            .keys()
            .copied()
            .filter(|id| *id > after)
            .map(|id| {
                let mut entry = self.album(id);
                if self.unreadable_album == Some(id) {
                    entry.value = Err(anyhow::anyhow!("fixture unreadable album"));
                }
                entry
            })
            .collect())
    }
    async fn refresh_album(&mut self, _: &Session, id: i64) -> Result<CollectionEntry> {
        if self.failed_album == Some(id) {
            bail!("fixture source refresh failed");
        }
        Ok(self.album(id))
    }
    fn file_page(&self, album: i64, after: i64) -> Result<Vec<FileEntry>> {
        self.files
            .iter()
            .filter(|((a, f), _)| *a == album && *f > after)
            .map(|(_, record)| self.entry(record))
            .collect()
    }
    fn favorite_page(&self, _: i64) -> Result<Vec<i64>> {
        Ok(Vec::new())
    }
    fn file(&self, album: i64, id: i64) -> Result<FileEntry> {
        self.entry(&self.files[&(album, id)])
    }
}

pub(super) struct Engine {
    pub directory: tempfile::TempDir,
    session: Session,
    pub catalog: Catalog,
    pub database: String,
    pub hardlinks: bool,
}

impl Engine {
    pub fn new(server: &mockito::ServerGuard, catalog: Catalog) -> Self {
        Self {
            directory: tempfile::tempdir().unwrap(),
            session: Session::new(
                ApiConfig::new(server.url()),
                catalog.user,
                Key::generate(),
                Key::generate(),
                SecretKey::generate(),
            )
            .unwrap(),
            catalog,
            database: "export.db".into(),
            hardlinks: false,
        }
    }

    pub fn root(&self) -> PathBuf {
        self.directory.path().join("photos")
    }

    pub fn db(&self) -> rusqlite::Connection {
        rusqlite::Connection::open(self.directory.path().join(&self.database)).unwrap()
    }

    pub fn options(&self, adopt: bool, albums: &[&str]) -> Options {
        Options {
            albums: albums.iter().map(|s| (*s).into()).collect(),
            exclude_albums: Vec::new(),
            exclude_shared: false,
            exclude_hidden: false,
            adopt,
            hardlinks: self.hardlinks,
            jobs: std::num::NonZeroUsize::new(1).unwrap(),
        }
    }

    pub fn prepare(&mut self, options: Options) -> Result<Export> {
        let mut export = Export::open(&self.root(), &self.session.master_key, options)?;
        let (_send, mut cancel) = watch::channel(false);
        let db = self.db();
        tokio::runtime::Runtime::new()?.block_on(export.prepare(
            db,
            |path| {
                let db = rusqlite::Connection::open(path)?;
                db.pragma_update(None, "key", b64::encode(Key::generate().as_bytes()))?;
                Ok(db)
            },
            &mut self.catalog,
            &self.session,
            &mut cancel,
            &|line| eprintln!("{line}"),
        ))?;
        Ok(export)
    }

    pub fn execute(&self, export: Export) -> Result<Summary> {
        self.execute_with_report(export, &|line| eprintln!("{line}"))
    }

    pub fn execute_with_report(
        &self,
        mut export: Export,
        report: &(dyn Fn(&str) + Sync),
    ) -> Result<Summary> {
        let (send, cancel) = watch::channel(false);
        tokio::runtime::Runtime::new()?
            .block_on(async { export.execute(&self.session, &send, &cancel, report) })
    }

    pub fn run(&mut self, adopt: bool, albums: &[&str]) -> Result<Summary> {
        let export = self.prepare(self.options(adopt, albums))?;
        self.execute(export)
    }
}
