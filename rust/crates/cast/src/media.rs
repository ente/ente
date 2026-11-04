use std::{
    cell::Cell,
    fs::{self, File},
    io::{ErrorKind, Write},
    path::{Path, PathBuf},
    rc::Rc,
};

use ente_core::{
    b64,
    crypto::{self, Header, Key, Nonce},
    http::{self, Api, ApiConfig, Auth, Http, SuccessResponse},
};
use futures_util::StreamExt;
use serde::Deserialize;
use thiserror::Error;

const BROKER_RESPONSE_LIMIT: usize = 16 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MediaKind {
    Image,
    Video,
    LivePhoto,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Media {
    pub image_path: Option<PathBuf>,
    pub video_path: Option<PathBuf>,
    pub byte_count: u64,
}

pub struct Download<'a> {
    pub file_id: i64,
    pub title: &'a str,
    pub kind: MediaKind,
    pub encrypted_key: &'a str,
    pub key_decryption_nonce: &'a str,
    pub collection_key: &'a str,
    pub decryption_header: &'a str,
    pub output_directory: &'a Path,
    pub maximum_bytes: u64,
}

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] http::Error),
    #[error(transparent)]
    Crypto(#[from] crypto::Error),
    #[error(transparent)]
    Base64(#[from] b64::DecodeError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    LivePhoto(#[from] ente_live_photo::Error),
    #[error("Cast authentication expired")]
    Unauthorized,
    #[error("HTTP {0}")]
    HttpStatus(u16),
    #[error("Invalid Cast download response")]
    InvalidResponse,
    #[error("Media exceeds the configured byte limit")]
    TooLarge,
    #[error("Media output already exists")]
    OutputExists,
    #[error("Cached media is invalid")]
    InvalidCache,
}

pub struct Client {
    api: Api,
    direct_download: Option<Api>,
}

impl Client {
    pub fn new(
        api_origin: String,
        direct_download_origin: Option<String>,
        cast_token: String,
    ) -> Result<Self, Error> {
        let http = Http::new()?;
        let api = cast_api(&http, api_origin, cast_token.clone());
        let direct_download =
            direct_download_origin.map(|origin| cast_api(&http, origin, cast_token));
        Ok(Self {
            api,
            direct_download,
        })
    }

    pub async fn download(&self, download: Download<'_>) -> Result<Media, Error> {
        let Download {
            file_id,
            title,
            kind,
            encrypted_key,
            key_decryption_nonce,
            collection_key,
            decryption_header,
            output_directory,
            maximum_bytes,
        } = download;
        if maximum_bytes == 0 {
            return Err(Error::TooLarge);
        }
        if output_directory.exists() {
            return Err(Error::OutputExists);
        }
        let parent = output_directory.parent().ok_or(Error::InvalidCache)?;
        let staging = tempfile::Builder::new()
            .prefix(".cast-media-")
            .tempdir_in(parent)?;
        let archive_path = staging.path().join("archive");
        let key = open_file_key(encrypted_key, key_decryption_nonce, collection_key)?;
        let header = Header::try_from_slice(&b64::decode(decryption_header)?)?;
        let response = self.response(file_id).await?;
        download_decrypted(response, &archive_path, &header, &key, maximum_bytes).await?;

        match kind {
            MediaKind::Image | MediaKind::Video => {
                let name = component_name(kind, title);
                fs::rename(&archive_path, staging.path().join(name))?;
            }
            MediaKind::LivePhoto => {
                extract_live_photo(&archive_path, staging.path(), maximum_bytes)?;
                fs::remove_file(&archive_path)?;
            }
        }

        let staged_media = open_cached(staging.path(), kind, maximum_bytes)?;
        let staging_path = staging.keep();
        if let Err(error) = fs::rename(&staging_path, output_directory) {
            let _ = fs::remove_dir_all(staging_path);
            return Err(error.into());
        }
        Ok(Media {
            image_path: staged_media
                .image_path
                .and_then(|path| path.file_name().map(|name| output_directory.join(name))),
            video_path: staged_media
                .video_path
                .and_then(|path| path.file_name().map(|name| output_directory.join(name))),
            byte_count: staged_media.byte_count,
        })
    }

    async fn response(&self, file_id: i64) -> Result<SuccessResponse, Error> {
        if let Some(api) = &self.direct_download {
            let response = api
                .get("/download/")
                .query(&[("fileID", file_id)])
                .send()
                .await?;
            return authenticated_success(response);
        }

        let response = self
            .api
            .get(&format!("/cast/files/download/v3/{file_id}"))
            .send()
            .await?;
        let response = authenticated_success(response)?;
        let body = collect_limited(response, BROKER_RESPONSE_LIMIT).await?;
        let signed: DownloadUrl =
            serde_json::from_slice(&body).map_err(|_| Error::InvalidResponse)?;
        let response = self.api.http().get(&signed.url).send().await?;
        if response.status() != 200 {
            return Err(Error::HttpStatus(response.status()));
        }
        Ok(response.error_for_status()?)
    }
}

pub fn open_cached(directory: &Path, kind: MediaKind, maximum_bytes: u64) -> Result<Media, Error> {
    let mut image_path = None;
    let mut video_path = None;
    let mut byte_count = 0u64;
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if !file_type.is_file() {
            return Err(Error::InvalidCache);
        }
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            return Err(Error::InvalidCache);
        };
        let slot = if valid_component_name(name, "image") {
            &mut image_path
        } else if valid_component_name(name, "video") {
            &mut video_path
        } else {
            return Err(Error::InvalidCache);
        };
        if slot.replace(entry.path()).is_some() {
            return Err(Error::InvalidCache);
        }
        byte_count = byte_count
            .checked_add(entry.metadata()?.len())
            .ok_or(Error::TooLarge)?;
        if byte_count > maximum_bytes {
            return Err(Error::TooLarge);
        }
    }
    let valid = match kind {
        MediaKind::Image => image_path.is_some() && video_path.is_none(),
        MediaKind::Video => image_path.is_none() && video_path.is_some(),
        MediaKind::LivePhoto => image_path.is_some() && video_path.is_some(),
    };
    if !valid {
        return Err(Error::InvalidCache);
    }
    Ok(Media {
        image_path,
        video_path,
        byte_count,
    })
}

fn cast_api(http: &Http, origin: String, cast_token: String) -> Api {
    let mut config = ApiConfig::new(origin);
    config.auth = Some(Auth::Cast(cast_token));
    Api::new(http.clone(), config)
}

fn open_file_key(
    encrypted_key: &str,
    key_decryption_nonce: &str,
    collection_key: &str,
) -> Result<Key, Error> {
    let encrypted_key = b64::decode(encrypted_key)?;
    let nonce = Nonce::try_from_slice(&b64::decode(key_decryption_nonce)?)?;
    let collection_key = Key::try_from_slice(&b64::decode(collection_key)?)?;
    let key = crypto::secretbox::decrypt(&encrypted_key, &nonce, &collection_key)?;
    Ok(Key::try_from_slice(&key)?)
}

fn authenticated_success(response: http::Response) -> Result<SuccessResponse, Error> {
    match response.status() {
        200 => Ok(response.error_for_status()?),
        401 => Err(Error::Unauthorized),
        status => Err(Error::HttpStatus(status)),
    }
}

async fn collect_limited(
    response: SuccessResponse,
    maximum_bytes: usize,
) -> Result<Vec<u8>, Error> {
    if content_length(&response).is_some_and(|length| length > maximum_bytes as u64) {
        return Err(Error::TooLarge);
    }
    let mut body = Vec::new();
    let mut stream = std::pin::pin!(response.bytes_stream());
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        if body.len().saturating_add(chunk.len()) > maximum_bytes {
            return Err(Error::TooLarge);
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

async fn download_decrypted(
    response: SuccessResponse,
    output_path: &Path,
    header: &Header,
    key: &Key,
    maximum_bytes: u64,
) -> Result<(), Error> {
    let maximum_bytes = usize::try_from(maximum_bytes).map_err(|_| Error::TooLarge)?;
    let maximum_encrypted = crypto::stream::estimate_encrypted_size(maximum_bytes);
    if content_length(&response).is_some_and(|length| length > maximum_encrypted as u64) {
        return Err(Error::TooLarge);
    }
    let output = LimitedWriter::new(File::create(output_path)?, maximum_bytes);
    let mut decryptor = crypto::stream::DecryptingWriter::new(header, key, output);
    let mut encrypted_bytes = 0usize;
    let mut stream = std::pin::pin!(response.bytes_stream());
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        encrypted_bytes = encrypted_bytes
            .checked_add(chunk.len())
            .ok_or(Error::TooLarge)?;
        if encrypted_bytes > maximum_encrypted {
            return Err(Error::TooLarge);
        }
        decryptor.write(&chunk).map_err(classify_crypto_error)?;
    }
    let mut output = decryptor.finish().map_err(classify_crypto_error)?;
    output.flush()?;
    Ok(())
}

fn classify_crypto_error(error: crypto::Error) -> Error {
    match &error {
        crypto::Error::Io(error) if error.kind() == ErrorKind::FileTooLarge => Error::TooLarge,
        _ => Error::Crypto(error),
    }
}

fn extract_live_photo(
    archive_path: &Path,
    output_directory: &Path,
    maximum_bytes: u64,
) -> Result<(), Error> {
    let remaining = usize::try_from(maximum_bytes).map_err(|_| Error::TooLarge)?;
    let remaining = Rc::new(Cell::new(remaining));
    let result = ente_live_photo::extract(File::open(archive_path)?, |component, extension| {
        let name = match component {
            ente_live_photo::Component::Image => "image",
            ente_live_photo::Component::Video => "video",
        };
        Ok(SharedLimitedWriter::new(
            File::create(output_directory.join(format!("{name}{extension}")))?,
            remaining.clone(),
        ))
    });
    match result {
        Ok(_) => Ok(()),
        Err(ente_live_photo::Error::Io(error)) if error.kind() == ErrorKind::FileTooLarge => {
            Err(Error::TooLarge)
        }
        Err(error) => Err(error.into()),
    }
}

fn content_length(response: &SuccessResponse) -> Option<u64> {
    response
        .headers()
        .get("content-length")?
        .to_str()
        .ok()?
        .parse()
        .ok()
}

fn component_name(kind: MediaKind, title: &str) -> String {
    let component = match kind {
        MediaKind::Image => "image",
        MediaKind::Video => "video",
        MediaKind::LivePhoto => unreachable!(),
    };
    match title.rsplit_once('.') {
        Some((_, extension)) if valid_extension(extension) => {
            format!("{component}.{}", extension.to_ascii_lowercase())
        }
        _ => component.to_owned(),
    }
}

fn valid_component_name(name: &str, component: &str) -> bool {
    name == component
        || name
            .strip_prefix(component)
            .and_then(|suffix| suffix.strip_prefix('.'))
            .is_some_and(valid_extension)
}

fn valid_extension(extension: &str) -> bool {
    (1..=16).contains(&extension.len())
        && extension.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

struct LimitedWriter {
    file: File,
    remaining: usize,
}

impl LimitedWriter {
    fn new(file: File, maximum_bytes: usize) -> Self {
        Self {
            file,
            remaining: maximum_bytes,
        }
    }
}

impl Write for LimitedWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if bytes.len() > self.remaining {
            return Err(std::io::Error::from(ErrorKind::FileTooLarge));
        }
        let written = self.file.write(bytes)?;
        self.remaining -= written;
        Ok(written)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.file.flush()
    }
}

struct SharedLimitedWriter {
    file: File,
    remaining: Rc<Cell<usize>>,
}

impl SharedLimitedWriter {
    fn new(file: File, remaining: Rc<Cell<usize>>) -> Self {
        Self { file, remaining }
    }
}

impl Write for SharedLimitedWriter {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        let remaining = self.remaining.get();
        if bytes.len() > remaining {
            return Err(std::io::Error::from(ErrorKind::FileTooLarge));
        }
        let written = self.file.write(bytes)?;
        self.remaining.set(remaining - written);
        Ok(written)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.file.flush()
    }
}

#[derive(Deserialize)]
struct DownloadUrl {
    url: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use ente_core::crypto::secretbox;
    use mockito::Matcher;
    use std::io::{Cursor, Read};

    struct Fixture {
        collection_key: Key,
        encrypted_key: String,
        nonce: String,
        file_key: Key,
    }

    impl Fixture {
        fn new() -> Self {
            let collection_key = Key::generate();
            let file_key = Key::generate();
            let encrypted = secretbox::encrypt(file_key.as_bytes(), &collection_key);
            Self {
                collection_key,
                encrypted_key: b64::encode(&encrypted.encrypted_data),
                nonce: b64::encode(encrypted.nonce.as_bytes()),
                file_key,
            }
        }

        fn encrypted_content(&self, plaintext: &[u8]) -> (Vec<u8>, String) {
            let mut encrypted = Vec::new();
            let header = crypto::stream::encrypt_file(
                &mut Cursor::new(plaintext),
                &mut encrypted,
                &self.file_key,
            )
            .unwrap();
            (encrypted, b64::encode(header.as_bytes()))
        }

        fn collection_key(&self) -> String {
            b64::encode(self.collection_key.as_bytes())
        }
    }

    fn live_photo() -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (name, content) in [("image.jpg", b"image"), ("video.mov", b"video")] {
            zip.start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zip.write_all(content).unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    fn expanding_live_photo() -> Vec<u8> {
        let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (name, size) in [("image.jpg", 2 * 1024 * 1024), ("video.mov", 1)] {
            zip.start_file(
                name,
                zip::write::SimpleFileOptions::default()
                    .compression_method(zip::CompressionMethod::Deflated),
            )
            .unwrap();
            std::io::copy(&mut std::io::repeat(0).take(size), &mut zip).unwrap();
        }
        zip.finish().unwrap().into_inner()
    }

    async fn download(
        server: &mut mockito::ServerGuard,
        body: Vec<u8>,
        plaintext_limit: u64,
        kind: MediaKind,
    ) -> (Result<Media, Error>, tempfile::TempDir) {
        let fixture = Fixture::new();
        let (encrypted, header) = fixture.encrypted_content(&body);
        let mock = server
            .mock("GET", "/download/")
            .match_query(Matcher::UrlEncoded("fileID".into(), "42".into()))
            .match_header("x-cast-access-token", "token")
            .with_status(200)
            .with_body(encrypted)
            .create_async()
            .await;
        let parent = tempfile::tempdir().unwrap();
        let output = parent.path().join("42");
        let client = Client::new(server.url(), Some(server.url()), "token".into()).unwrap();
        let media = client
            .download(Download {
                file_id: 42,
                title: "photo.jpg",
                kind,
                encrypted_key: &fixture.encrypted_key,
                key_decryption_nonce: &fixture.nonce,
                collection_key: &fixture.collection_key(),
                decryption_header: &header,
                output_directory: &output,
                maximum_bytes: plaintext_limit,
            })
            .await;
        mock.assert_async().await;
        (media, parent)
    }

    #[tokio::test]
    async fn downloads_and_atomically_publishes_media() {
        let mut server = mockito::Server::new_async().await;
        let (media, _parent) = download(&mut server, b"image".to_vec(), 5, MediaKind::Image).await;
        let media = media.unwrap();
        assert_eq!(media.byte_count, 5);
        assert_eq!(fs::read(media.image_path.unwrap()).unwrap(), b"image");
        assert!(media.video_path.is_none());
    }

    #[tokio::test]
    async fn rejects_declared_and_chunked_overflow_without_output() {
        for chunked in [false, true] {
            let mut server = mockito::Server::new_async().await;
            let fixture = Fixture::new();
            let (encrypted, header) = fixture.encrypted_content(&vec![0; 1025]);
            let mock = server
                .mock("GET", "/download/")
                .match_query(Matcher::UrlEncoded("fileID".into(), "42".into()))
                .match_header("x-cast-access-token", "token")
                .with_status(200);
            let _mock = if chunked {
                mock.with_chunked_body(move |writer| writer.write_all(&encrypted))
                    .create_async()
                    .await
            } else {
                mock.with_body(encrypted).create_async().await
            };
            let parent = tempfile::tempdir().unwrap();
            let output = parent.path().join("42");
            let client = Client::new(server.url(), Some(server.url()), "token".into()).unwrap();
            let result = client
                .download(Download {
                    file_id: 42,
                    title: "photo.jpg",
                    kind: MediaKind::Image,
                    encrypted_key: &fixture.encrypted_key,
                    key_decryption_nonce: &fixture.nonce,
                    collection_key: &fixture.collection_key(),
                    decryption_header: &header,
                    output_directory: &output,
                    maximum_bytes: 1024,
                })
                .await;
            assert!(matches!(result, Err(Error::TooLarge)), "chunked={chunked}");
            assert!(!output.exists());
            assert!(fs::read_dir(parent.path()).unwrap().all(|entry| {
                !entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".cast-media-")
            }));
        }
    }

    #[tokio::test]
    async fn uses_self_hosted_broker_without_forwarding_token() {
        let mut server = mockito::Server::new_async().await;
        let fixture = Fixture::new();
        let (encrypted, header) = fixture.encrypted_content(b"image");
        let file_url = format!("{}/object", server.url());
        let broker = server
            .mock("GET", "/cast/files/download/v3/42")
            .match_header("x-cast-access-token", "token")
            .with_status(200)
            .with_body(serde_json::json!({ "url": file_url }).to_string())
            .create_async()
            .await;
        let object = server
            .mock("GET", "/object")
            .match_header("x-cast-access-token", Matcher::Missing)
            .with_status(200)
            .with_body(encrypted)
            .create_async()
            .await;
        let parent = tempfile::tempdir().unwrap();
        let output = parent.path().join("42");
        let client = Client::new(server.url(), None, "token".into()).unwrap();
        client
            .download(Download {
                file_id: 42,
                title: "photo.jpg",
                kind: MediaKind::Image,
                encrypted_key: &fixture.encrypted_key,
                key_decryption_nonce: &fixture.nonce,
                collection_key: &fixture.collection_key(),
                decryption_header: &header,
                output_directory: &output,
                maximum_bytes: 5,
            })
            .await
            .unwrap();
        broker.assert_async().await;
        object.assert_async().await;
    }

    #[tokio::test]
    async fn validates_live_photo_before_publication() {
        let mut server = mockito::Server::new_async().await;
        let bytes = live_photo();
        let (media, _parent) = download(
            &mut server,
            bytes.clone(),
            bytes.len() as u64,
            MediaKind::LivePhoto,
        )
        .await;
        let media = media.unwrap();
        assert_eq!(fs::read(media.image_path.unwrap()).unwrap(), b"image");
        assert_eq!(fs::read(media.video_path.unwrap()).unwrap(), b"video");
        assert_eq!(media.byte_count, 10);
    }

    #[tokio::test]
    async fn rejects_invalid_live_photo_before_publication() {
        let mut server = mockito::Server::new_async().await;
        let (result, parent) = download(
            &mut server,
            b"not a zip".to_vec(),
            1024,
            MediaKind::LivePhoto,
        )
        .await;
        assert!(matches!(result, Err(Error::LivePhoto(_))));
        assert!(!parent.path().join("42").exists());
        assert!(fs::read_dir(parent.path()).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".cast-media-")
        }));
    }

    #[tokio::test]
    async fn rejects_live_photo_expansion_past_cast_limit() {
        let mut server = mockito::Server::new_async().await;
        let bytes = expanding_live_photo();
        let limit = bytes.len() as u64;
        let (result, parent) = download(&mut server, bytes, limit, MediaKind::LivePhoto).await;
        assert!(matches!(result, Err(Error::TooLarge)));
        assert!(!parent.path().join("42").exists());
    }
}
