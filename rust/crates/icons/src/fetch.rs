use std::collections::HashSet;
use std::time::Duration;

use encoding_rs::Encoding;
use ente_core::http::{self, Http, SuccessResponse};
use futures_util::StreamExt;
use scraper::{ElementRef, Html};
use url::Url;

use crate::{discovery, format};

const HTML_LIMIT: usize = 256 * 1024;
const LOOKUP_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("expected an HTTP or HTTPS URL")]
    InvalidUrl,
    #[error("website request failed: {0}")]
    Http(#[from] http::Error),
    #[error("icon lookup timed out")]
    Timeout,
    #[error("icon exceeds the 1 MiB download limit")]
    TooLarge,
    #[error("image validation task failed: {0}")]
    Worker(#[from] tokio::task::JoinError),
}

#[derive(Debug)]
pub struct Icon {
    pub url: Url,
    pub data: Vec<u8>,
}

pub struct Fetcher {
    http: Http,
}

impl Fetcher {
    pub fn new() -> Result<Self, Error> {
        Ok(Self { http: Http::new()? })
    }

    pub async fn fetch(&self, url: &str) -> Result<Option<Icon>, Error> {
        let page = Url::parse(url)
            .ok()
            .filter(|url| matches!(url.scheme(), "http" | "https"))
            .ok_or(Error::InvalidUrl)?;
        tokio::time::timeout(LOOKUP_TIMEOUT, self.find(page))
            .await
            .map_err(|_| Error::Timeout)?
    }

    async fn find(&self, page: Url) -> Result<Option<Icon>, Error> {
        let parent = parent_url(&page);
        let mut error = None;
        for page in std::iter::once(page).chain(parent) {
            match self.site(page).await {
                Ok(Some(icon)) => return Ok(Some(icon)),
                Ok(None) => {}
                Err(failure) => error = Some(failure),
            }
        }
        error.map_or(Ok(None), Err)
    }

    async fn site(&self, page: Url) -> Result<Option<Icon>, Error> {
        let mut error = None;
        let mut candidates = Vec::new();
        let mut fallback_page = page.clone();
        match self.get(&page).await {
            Ok(Some(response)) => {
                fallback_page = response.url().clone();
                let encoding = response
                    .headers()
                    .get("content-type")
                    .and_then(|header| header.to_str().ok())
                    .and_then(content_type_encoding);
                match body(response, HTML_LIMIT, true).await {
                    Ok(bytes) => {
                        let encoding = Encoding::for_bom(&bytes)
                            .map(|(encoding, _)| encoding)
                            .or(encoding)
                            .or_else(|| html_encoding(&bytes));
                        let text = encoding.unwrap_or(encoding_rs::UTF_8).decode(&bytes).0;
                        candidates = discovery::icon_urls(&text, &fallback_page);
                    }
                    Err(failure) => error = Some(failure),
                }
            }
            Ok(None) => {}
            Err(failure) => error = Some(failure),
        }
        if let Ok(fallback) = fallback_page.join("/favicon.ico") {
            candidates.push(fallback);
        }
        if fallback_page.origin() != page.origin()
            && let Ok(fallback) = page.join("/favicon.ico")
        {
            candidates.push(fallback);
        }
        let mut seen = HashSet::new();
        for url in candidates {
            if !seen.insert(url.clone()) {
                continue;
            }
            match self.icon(&url).await {
                Ok(Some(icon)) => return Ok(Some(icon)),
                Ok(None) => {}
                Err(failure) => error = Some(failure),
            }
        }
        error.map_or(Ok(None), Err)
    }

    async fn get(&self, url: &Url) -> Result<Option<SuccessResponse>, Error> {
        let response = self.http.get(url.as_str()).send().await?;
        if matches!(response.status(), 404 | 410) {
            return Ok(None);
        }
        Ok(Some(response.error_for_status()?))
    }

    async fn icon(&self, url: &Url) -> Result<Option<Icon>, Error> {
        let Some(response) = self.get(url).await? else {
            return Ok(None);
        };
        let url = response.url().clone();
        let data = body(response, format::MAX_BYTES, false).await?;
        Ok(
            tokio::task::spawn_blocking(move || format::png(&data).map(|data| Icon { url, data }))
                .await?,
        )
    }
}

async fn body(response: SuccessResponse, limit: usize, prefix: bool) -> Result<Vec<u8>, Error> {
    let mut bytes = Vec::new();
    let mut chunks = std::pin::pin!(response.bytes_stream());
    while let Some(chunk) = chunks.next().await {
        let chunk = chunk?;
        let remaining = limit - bytes.len();
        if !prefix && chunk.len() > remaining {
            return Err(Error::TooLarge);
        }
        bytes.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
        if prefix && bytes.len() == limit {
            break;
        }
    }
    Ok(bytes)
}

fn content_type_encoding(content_type: &str) -> Option<&'static Encoding> {
    content_type.split(';').find_map(|parameter| {
        let (name, value) = parameter.trim().split_once('=')?;
        name.trim()
            .eq_ignore_ascii_case("charset")
            .then(|| Encoding::for_label(value.trim().trim_matches(['\'', '"']).as_bytes()))?
    })
}

fn html_encoding(bytes: &[u8]) -> Option<&'static Encoding> {
    let prefix = String::from_utf8_lossy(&bytes[..bytes.len().min(1024)]);
    let document = Html::parse_document(&prefix);
    let encoding = document
        .root_element()
        .descendants()
        .filter_map(ElementRef::wrap)
        .filter(|element| element.value().name() == "meta")
        .find_map(|element| {
            if let Some(charset) = element.attr("charset") {
                Encoding::for_label(charset.as_bytes())
            } else {
                element
                    .attr("http-equiv")
                    .filter(|value| value.eq_ignore_ascii_case("content-type"))?;
                content_type_encoding(element.attr("content")?)
            }
        })?;
    Some(
        if encoding == encoding_rs::UTF_16LE || encoding == encoding_rs::UTF_16BE {
            encoding_rs::UTF_8
        } else if encoding == encoding_rs::X_USER_DEFINED {
            encoding_rs::WINDOWS_1252
        } else {
            encoding
        },
    )
}

fn parent_url(page: &Url) -> Option<Url> {
    let host = page.domain()?;
    let domain = psl::domain(host.as_bytes())?;
    if !domain.suffix().is_known() || domain.as_bytes() == host.as_bytes() {
        return None;
    }
    let mut parent = page.join("/").ok()?;
    parent
        .set_host(Some(std::str::from_utf8(domain.as_bytes()).ok()?))
        .ok()?;
    parent.set_username("").ok()?;
    parent.set_password(None).ok()?;
    Some(parent)
}

#[cfg(test)]
mod tests;
