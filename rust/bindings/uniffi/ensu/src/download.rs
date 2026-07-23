use ente_model_download::download;

#[derive(Debug, Clone, uniffi::Enum)]
pub enum DownloadError {
    Cancelled,
    Validation { message: String },
    Http { status: u16 },
    Network { message: String },
    SizeMismatch { expected: u64, actual: u64 },
    Protocol { message: String },
    InvalidTarget { message: String },
    StorageFull,
    Io { message: String },
}

impl From<download::Error> for DownloadError {
    fn from(value: download::Error) -> Self {
        match value {
            download::Error::Cancelled => Self::Cancelled,
            download::Error::Target { source, .. } => Self::from(*source),
            download::Error::Fallback { single, .. } => Self::from(*single),
            download::Error::Validation(message) => Self::Validation { message },
            download::Error::Http(status) => Self::Http { status },
            download::Error::Network(message) => Self::Network { message },
            download::Error::SizeMismatch { expected, actual } => {
                Self::SizeMismatch { expected, actual }
            }
            download::Error::Protocol(message) => Self::Protocol { message },
            download::Error::InvalidTarget(message) => Self::InvalidTarget { message },
            download::Error::StorageFull => Self::StorageFull,
            download::Error::Io(err) => Self::Io {
                message: err.to_string(),
            },
            download::Error::Json(err) => Self::Io {
                message: err.to_string(),
            },
        }
    }
}
