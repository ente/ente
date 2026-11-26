uniffi::setup_scaffolding!("cast");

pub mod log;

use std::sync::Arc;

use ente_core::crypto;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum CastCryptoError {
    #[error("{detail}")]
    Other { detail: String },
}

#[derive(Debug, Error, uniffi::Error)]
pub enum CastMediaError {
    #[error("{detail}")]
    Unauthorized { detail: String },
    #[error("{detail}")]
    TooLarge { detail: String },
    #[error("{detail}")]
    InvalidMedia { detail: String },
    #[error("{detail}")]
    Other { detail: String },
}

impl From<ente_cast::media::Error> for CastMediaError {
    fn from(error: ente_cast::media::Error) -> Self {
        let detail = ente_core::error::chain(&error);
        match error {
            ente_cast::media::Error::Unauthorized => Self::Unauthorized { detail },
            ente_cast::media::Error::TooLarge => Self::TooLarge { detail },
            ente_cast::media::Error::LivePhoto(_)
            | ente_cast::media::Error::InvalidCache
            | ente_cast::media::Error::Crypto(_) => Self::InvalidMedia { detail },
            _ => Self::Other { detail },
        }
    }
}

impl From<crypto::Error> for CastCryptoError {
    fn from(err: crypto::Error) -> Self {
        CastCryptoError::Other {
            detail: ente_core::error::chain(&err),
        }
    }
}

impl From<ente_cast::Error> for CastCryptoError {
    fn from(err: ente_cast::Error) -> Self {
        CastCryptoError::Other {
            detail: ente_core::error::chain(&err),
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct CastPayload {
    pub collection_id: i64,
    pub cast_token: String,
    pub collection_key: String,
}

impl From<ente_cast::CastPayload> for CastPayload {
    fn from(payload: ente_cast::CastPayload) -> Self {
        Self {
            collection_id: payload.collection_id,
            cast_token: payload.cast_token,
            collection_key: payload.collection_key,
        }
    }
}

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum CastMediaKind {
    Image,
    Video,
    LivePhoto,
}

impl From<CastMediaKind> for ente_cast::media::MediaKind {
    fn from(kind: CastMediaKind) -> Self {
        match kind {
            CastMediaKind::Image => Self::Image,
            CastMediaKind::Video => Self::Video,
            CastMediaKind::LivePhoto => Self::LivePhoto,
        }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct CastMediaDownloadRequest {
    pub file_id: i64,
    pub title: String,
    pub kind: CastMediaKind,
    pub encrypted_key: String,
    pub key_decryption_nonce: String,
    pub collection_key: String,
    pub decryption_header: String,
    pub output_directory: String,
    pub maximum_bytes: u64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct CastMedia {
    pub image_path: Option<String>,
    pub video_path: Option<String>,
    pub byte_count: u64,
}

impl From<ente_cast::media::Media> for CastMedia {
    fn from(media: ente_cast::media::Media) -> Self {
        Self {
            image_path: media
                .image_path
                .map(|path| path.to_string_lossy().into_owned()),
            video_path: media
                .video_path
                .map(|path| path.to_string_lossy().into_owned()),
            byte_count: media.byte_count,
        }
    }
}

#[derive(uniffi::Object)]
pub struct CastMediaClient {
    inner: ente_cast::media::Client,
}

#[uniffi::export]
impl CastMediaClient {
    #[uniffi::constructor]
    pub fn new(
        api_origin: String,
        direct_download_origin: Option<String>,
        cast_token: String,
    ) -> Result<Arc<Self>, CastMediaError> {
        Ok(Arc::new(Self {
            inner: ente_cast::media::Client::new(api_origin, direct_download_origin, cast_token)?,
        }))
    }

    #[uniffi::method(async_runtime = "tokio")]
    pub async fn download(
        &self,
        request: CastMediaDownloadRequest,
    ) -> Result<CastMedia, CastMediaError> {
        let CastMediaDownloadRequest {
            file_id,
            title,
            kind,
            encrypted_key,
            key_decryption_nonce,
            collection_key,
            decryption_header,
            output_directory,
            maximum_bytes,
        } = request;
        Ok(self
            .inner
            .download(ente_cast::media::Download {
                file_id,
                title: &title,
                kind: kind.into(),
                encrypted_key: &encrypted_key,
                key_decryption_nonce: &key_decryption_nonce,
                collection_key: &collection_key,
                decryption_header: &decryption_header,
                output_directory: std::path::Path::new(&output_directory),
                maximum_bytes,
            })
            .await?
            .into())
    }

    pub fn open_cached(
        &self,
        directory: String,
        kind: CastMediaKind,
        maximum_bytes: u64,
    ) -> Result<CastMedia, CastMediaError> {
        Ok(ente_cast::media::open_cached(
            std::path::Path::new(&directory),
            kind.into(),
            maximum_bytes,
        )?
        .into())
    }
}

#[derive(uniffi::Object)]
pub struct CastReceiver {
    inner: ente_cast::ReceiverCredentials,
}

#[uniffi::export]
impl CastReceiver {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: ente_cast::ReceiverCredentials::generate(),
        })
    }

    pub fn public_key(&self) -> String {
        self.inner.public_key()
    }

    pub fn pq_public_key(&self) -> String {
        self.inner.pq_public_key()
    }

    pub fn open_payload(&self, encrypted_payload: String) -> Result<CastPayload, CastCryptoError> {
        Ok(self.inner.open_payload(&encrypted_payload)?.into())
    }
}

#[uniffi::export]
pub fn open_secret_box(
    ciphertext: &[u8],
    nonce: &[u8],
    key: &[u8],
) -> Result<Vec<u8>, CastCryptoError> {
    let nonce = crypto::Nonce::try_from_slice(nonce)?;
    let key = crypto::Key::try_from_slice(key)?;
    Ok(crypto::secretbox::decrypt(ciphertext, &nonce, &key)?)
}

#[uniffi::export]
pub fn decrypt_secret_stream(
    encrypted_data: &[u8],
    header: &[u8],
    key: &[u8],
) -> Result<Vec<u8>, CastCryptoError> {
    let header = crypto::Header::try_from_slice(header)?;
    let key = crypto::Key::try_from_slice(key)?;
    Ok(crypto::stream::decrypt_file_data(
        encrypted_data,
        &header,
        &key,
    )?)
}
