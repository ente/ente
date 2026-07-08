//! Legacy HTTP client, superseded by [`crate::http`].
//!
//! [`HttpClient`] is an Ente API client bound to one base URL. It sends Ente's
//! client headers on every request, and the auth token once one is set.
//! [`ObjectStoreHttpClient`], from [`HttpClient::object_store`], is a bare
//! client for presigned object-store transfers, sending only the headers it is
//! given.

use std::error::Error as StdError;
use std::fmt::Write as _;
use std::future::Future;
use std::sync::RwLock;
#[cfg(not(target_arch = "wasm32"))]
use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderName, HeaderValue, LOCATION};
#[cfg(not(target_arch = "wasm32"))]
use reqwest::redirect::Policy;
use reqwest::{Response, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::Zeroizing;

const TOKEN_HEADER: &str = "X-Auth-Token";
const CLIENT_PKG_HEADER: &str = "X-Client-Package";
const CLIENT_VERSION_HEADER: &str = "X-Client-Version";

const MAX_REDIRECTS: usize = 5;

/// HTTP client errors.
#[derive(Error, Debug)]
pub enum Error {
    /// Network error - connection failed, timeout, etc.
    #[error("Network error: {0}")]
    Network(String),

    /// Server returned an HTTP error status.
    #[error("HTTP {status}: {message}")]
    Http {
        /// Optional structured server error code.
        code: Option<String>,
        /// Error message or response body.
        message: String,
        /// HTTP status code.
        status: u16,
    },

    /// Failed to parse JSON response.
    #[error("JSON parse error: {0}")]
    Parse(String),

    /// Invalid base URL or request path.
    #[error("Invalid URL: {0}")]
    InvalidUrl(String),
}

impl Error {
    /// Return the HTTP status code if this is an HTTP error.
    pub fn status_code(&self) -> Option<u16> {
        match self {
            Error::Http { status, .. } => Some(*status),
            _ => None,
        }
    }

    /// Return the structured server error code when available.
    pub fn api_code(&self) -> Option<&str> {
        match self {
            Error::Http { code, .. } => code.as_deref(),
            _ => None,
        }
    }

    /// Return the server message when available.
    pub fn api_message(&self) -> Option<&str> {
        match self {
            Error::Http { message, .. } => Some(message.as_str()),
            _ => None,
        }
    }

    fn with_request_context(self, context: &str) -> Self {
        fn append(message: String, context: &str) -> String {
            format!("{message} {context}")
        }

        match self {
            Error::Network(message) => Error::Network(append(message, context)),
            Error::Http {
                status,
                code,
                message,
            } => Error::Http {
                status,
                code,
                message: append(message, context),
            },
            Error::Parse(message) => Error::Parse(append(message, context)),
            Error::InvalidUrl(message) => Error::InvalidUrl(append(message, context)),
        }
    }
}

impl From<reqwest::Error> for Error {
    fn from(e: reqwest::Error) -> Self {
        let message = format_reqwest_error(&e);
        if let Some(status) = e.status() {
            Error::Http {
                status: status.as_u16(),
                code: None,
                message,
            }
        } else {
            Error::Network(message)
        }
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Error::Parse(e.to_string())
    }
}

#[derive(Deserialize)]
struct ApiErrorBody {
    code: Option<String>,
    message: Option<String>,
}

fn parse_api_error_body(body: &str) -> (Option<String>, String) {
    let Ok(parsed) = serde_json::from_str::<ApiErrorBody>(body) else {
        return (None, body.to_string());
    };
    let message = parsed
        .message
        .or_else(|| parsed.code.clone())
        .unwrap_or_else(|| body.to_string());
    (parsed.code, message)
}

fn format_reqwest_error(error: &reqwest::Error) -> String {
    let mut message = error.to_string();

    let mut kinds = Vec::new();
    if error.is_timeout() {
        kinds.push("timeout");
    }
    #[cfg(not(target_arch = "wasm32"))]
    if error.is_connect() {
        kinds.push("connect");
    }
    if error.is_request() {
        kinds.push("request");
    }
    if error.is_body() {
        kinds.push("body");
    }
    if error.is_decode() {
        kinds.push("decode");
    }
    if error.is_redirect() {
        kinds.push("redirect");
    }
    if !kinds.is_empty() {
        let _ = write!(message, " [kind: {}]", kinds.join(","));
    }

    let mut source_chain = Vec::new();
    let mut source = StdError::source(error);
    while let Some(cause) = source {
        source_chain.push(cause.to_string());
        source = cause.source();
    }
    if !source_chain.is_empty() {
        let _ = write!(message, " [caused by: {}]", source_chain.join(" -> "));
    }

    message
}

fn request_context(method: &str, url: &str, query: &[(&str, String)]) -> String {
    format!("[request: {method} {}]", request_target(url, query))
}

fn request_target(url: &str, query: &[(&str, String)]) -> String {
    let Ok(mut parsed) = Url::parse(url) else {
        return url.to_string();
    };

    if !query.is_empty() {
        let mut pairs = parsed.query_pairs_mut();
        for (key, value) in query {
            pairs.append_pair(key, value);
        }
    }

    match parsed.query() {
        Some(query) => format!("{}?{query}", parsed.path()),
        None => parsed.path().to_string(),
    }
}

/// Response from the /ping endpoint.
#[derive(Deserialize, Debug)]
pub struct PingResponse {
    /// "pong"
    pub message: String,
    /// Git commit hash of the server.
    pub id: String,
}

/// Authenticated HTTP client configuration.
#[derive(Clone, Default)]
pub struct HttpConfig {
    /// Base API URL.
    pub base_url: String,
    /// Optional auth token sent via `X-Auth-Token`.
    pub auth_token: Option<String>,
    /// Optional user agent.
    pub user_agent: Option<String>,
    /// Optional client package header.
    pub client_package: Option<String>,
    /// Optional client version header.
    pub client_version: Option<String>,
    /// Optional request timeout.
    pub timeout_secs: Option<u64>,
}

impl std::fmt::Debug for HttpConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpConfig")
            .field("base_url", &self.base_url)
            .field(
                "auth_token",
                &self.auth_token.as_ref().map(|_| "<redacted>"),
            )
            .field("user_agent", &self.user_agent)
            .field("client_package", &self.client_package)
            .field("client_version", &self.client_version)
            .field("timeout_secs", &self.timeout_secs)
            .finish()
    }
}

/// HTTP client for the Ente API.
///
/// The client is bound to one base URL during creation. It sends Ente's
/// required HTTP headers on every request, and the auth token once one is set.
///
/// Request `path`s are trusted endpoints, joined to the base URL verbatim, so
/// they must not be attacker-controlled.
pub struct HttpClient {
    client: reqwest::Client,
    no_redirect_client: reqwest::Client,
    base_url: String,
    auth_token: RwLock<Option<Zeroizing<String>>>,
    #[cfg(not(target_arch = "wasm32"))]
    user_agent: Option<String>,
    client_package: Option<String>,
    client_version: Option<String>,
}

/// Bare HTTP client for presigned object-store transfers.
#[derive(Clone)]
pub struct ObjectStoreHttpClient {
    client: reqwest::Client,
}

impl HttpClient {
    /// Create a client with the given base URL.
    pub fn new(base_url: &str) -> Result<Self, Error> {
        Self::new_with_config(HttpConfig {
            base_url: base_url.to_string(),
            ..HttpConfig::default()
        })
    }

    /// Create a client with auth/header configuration.
    ///
    /// # Errors
    ///
    /// Returns [`Error::InvalidUrl`] if the base URL does not parse, or if it
    /// carries a query or fragment.
    pub fn new_with_config(config: HttpConfig) -> Result<Self, Error> {
        let base_url = config.base_url.trim_end_matches('/').to_string();
        let base = Url::parse(&base_url)
            .map_err(|e| Error::InvalidUrl(format!("invalid base URL: {e}")))?;
        if base.query().is_some() || base.fragment().is_some() {
            return Err(Error::InvalidUrl(
                "base URL must not contain a query or fragment".to_string(),
            ));
        }

        #[cfg(not(target_arch = "wasm32"))]
        let mut builder = reqwest::Client::builder();
        #[cfg(target_arch = "wasm32")]
        let builder = reqwest::Client::builder();
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(timeout) = config.timeout_secs {
            builder = builder.timeout(Duration::from_secs(timeout));
        }
        let client = builder.build().map_err(Error::from)?;

        #[cfg(not(target_arch = "wasm32"))]
        let mut no_redirect_builder = reqwest::Client::builder().redirect(Policy::none());
        #[cfg(target_arch = "wasm32")]
        let no_redirect_builder = reqwest::Client::builder();
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(timeout) = config.timeout_secs {
            no_redirect_builder = no_redirect_builder.timeout(Duration::from_secs(timeout));
        }
        let no_redirect_client = no_redirect_builder.build().map_err(Error::from)?;

        Ok(Self {
            client,
            no_redirect_client,
            base_url,
            auth_token: RwLock::new(config.auth_token.map(Zeroizing::new)),
            #[cfg(not(target_arch = "wasm32"))]
            user_agent: config.user_agent,
            client_package: config.client_package,
            client_version: config.client_version,
        })
    }

    /// Replace the auth token used for authenticated requests.
    pub fn set_auth_token(&self, auth_token: Option<String>) {
        *self
            .auth_token
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = auth_token.map(Zeroizing::new);
    }

    /// Create a bare client for presigned object-store requests.
    pub fn object_store(&self) -> ObjectStoreHttpClient {
        ObjectStoreHttpClient {
            client: self.no_redirect_client.clone(),
        }
    }

    /// GET request, returning the response body as text.
    pub async fn get(&self, path: &str) -> Result<String, Error> {
        let url = self.request_url(path)?;
        let context = request_context("GET", &url, &[]);
        let request = self.client.get(&url).headers(self.build_headers()?);
        send_and_parse(request, &context, parse_text_response).await
    }

    /// GET request returning JSON.
    pub async fn get_json<T: DeserializeOwned>(
        &self,
        path: &str,
        query: &[(&str, String)],
    ) -> Result<T, Error> {
        let url = self.request_url(path)?;
        let context = request_context("GET", &url, query);
        let request = self
            .client
            .get(&url)
            .headers(self.build_headers()?)
            .query(query);
        send_and_parse(request, &context, parse_json_response).await
    }

    /// GET request returning `None` for 404.
    pub async fn get_json_optional<T: DeserializeOwned>(
        &self,
        path: &str,
        query: &[(&str, String)],
    ) -> Result<Option<T>, Error> {
        let url = self.request_url(path)?;
        let context = request_context("GET", &url, query);
        let request = self
            .client
            .get(&url)
            .headers(self.build_headers()?)
            .query(query);
        send_and_parse(request, &context, |response| async move {
            if response.status().as_u16() == 404 {
                Ok(None)
            } else {
                parse_json_response(response).await.map(Some)
            }
        })
        .await
    }

    /// POST JSON request.
    pub async fn post_json<T: DeserializeOwned, B: Serialize + Sync + ?Sized>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T, Error> {
        let url = self.request_url(path)?;
        let context = request_context("POST", &url, &[]);
        let request = self
            .client
            .post(&url)
            .headers(self.build_headers()?)
            .json(body);
        send_and_parse(request, &context, parse_json_response).await
    }

    /// POST JSON request expecting an empty response body.
    pub async fn post_empty<B: Serialize + Sync + ?Sized>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<(), Error> {
        let url = self.request_url(path)?;
        let context = request_context("POST", &url, &[]);
        let request = self
            .client
            .post(&url)
            .headers(self.build_headers()?)
            .json(body);
        send_and_parse(request, &context, parse_empty_response).await
    }

    /// PUT JSON request.
    pub async fn put_json<T: DeserializeOwned, B: Serialize + Sync + ?Sized>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T, Error> {
        let url = self.request_url(path)?;
        let context = request_context("PUT", &url, &[]);
        let request = self
            .client
            .put(&url)
            .headers(self.build_headers()?)
            .json(body);
        send_and_parse(request, &context, parse_json_response).await
    }

    /// PUT JSON request expecting an empty response body.
    pub async fn put_empty<B: Serialize + Sync + ?Sized>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<(), Error> {
        let url = self.request_url(path)?;
        let context = request_context("PUT", &url, &[]);
        let request = self
            .client
            .put(&url)
            .headers(self.build_headers()?)
            .json(body);
        send_and_parse(request, &context, parse_empty_response).await
    }

    /// DELETE request expecting an empty response body.
    pub async fn delete_empty(&self, path: &str, query: &[(&str, String)]) -> Result<(), Error> {
        let url = self.request_url(path)?;
        let context = request_context("DELETE", &url, query);
        let request = self
            .client
            .delete(&url)
            .headers(self.build_headers()?)
            .query(query);
        send_and_parse(request, &context, parse_empty_response).await
    }

    /// DELETE request returning JSON.
    pub async fn delete_json<T: DeserializeOwned>(
        &self,
        path: &str,
        query: &[(&str, String)],
    ) -> Result<T, Error> {
        let url = self.request_url(path)?;
        let context = request_context("DELETE", &url, query);
        let request = self
            .client
            .delete(&url)
            .headers(self.build_headers()?)
            .query(query);
        send_and_parse(request, &context, parse_json_response).await
    }

    /// Ping the API, returns [PingResponse].
    pub async fn ping(&self) -> Result<PingResponse, Error> {
        self.get_json("/ping", &[]).await
    }

    fn request_url(&self, path: &str) -> Result<String, Error> {
        if !path.starts_with('/') {
            return Err(Error::InvalidUrl(
                "request paths must start with '/'".to_string(),
            ));
        }
        debug_assert!(
            !path_contains_dot_segments(path),
            "request paths must be trusted endpoint paths without dot segments"
        );

        Ok(format!("{}{}", self.base_url, path))
    }

    fn build_headers(&self) -> Result<HeaderMap, Error> {
        let mut headers = self.build_public_headers()?;
        if let Some(auth_token) = self
            .auth_token
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
        {
            let token =
                HeaderValue::from_str(auth_token).map_err(|e| Error::Parse(e.to_string()))?;
            headers.insert(TOKEN_HEADER, token);
        }
        Ok(headers)
    }

    fn build_public_headers(&self) -> Result<HeaderMap, Error> {
        let mut headers = HeaderMap::new();
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(user_agent) = &self.user_agent {
            let value =
                HeaderValue::from_str(user_agent).map_err(|e| Error::Parse(e.to_string()))?;
            headers.insert(reqwest::header::USER_AGENT, value);
        }
        if let Some(client_package) = &self.client_package {
            let value =
                HeaderValue::from_str(client_package).map_err(|e| Error::Parse(e.to_string()))?;
            headers.insert(CLIENT_PKG_HEADER, value);
        }
        if let Some(client_version) = &self.client_version {
            let value =
                HeaderValue::from_str(client_version).map_err(|e| Error::Parse(e.to_string()))?;
            headers.insert(CLIENT_VERSION_HEADER, value);
        }
        Ok(headers)
    }
}

impl ObjectStoreHttpClient {
    /// Download bytes from a presigned URL without Ente headers.
    pub async fn get_bytes(&self, url: &str) -> Result<Vec<u8>, Error> {
        get_bytes_with_client(&self.client, url).await
    }

    /// Upload raw bytes to a presigned URL without Ente headers.
    pub async fn put_bytes(
        &self,
        url: &str,
        body: &[u8],
        headers: &[(&str, String)],
    ) -> Result<(), Error> {
        put_bytes_with_client(&self.client, url, body, headers).await
    }
}

async fn send_and_parse<T, F, Fut>(
    request: reqwest::RequestBuilder,
    context: &str,
    parse: F,
) -> Result<T, Error>
where
    F: FnOnce(Response) -> Fut,
    Fut: Future<Output = Result<T, Error>>,
{
    let outcome = async {
        let response = request.send().await?;
        parse(response).await
    }
    .await;
    outcome.map_err(|error| error.with_request_context(context))
}

async fn get_bytes_with_client(client: &reqwest::Client, url: &str) -> Result<Vec<u8>, Error> {
    let mut current_url = parse_url(url)?;
    for _ in 0..MAX_REDIRECTS {
        let response = client.get(current_url.clone()).send().await?;
        if response.status().is_redirection()
            && let Some(location) = response.headers().get(LOCATION)
        {
            current_url = resolve_redirect(&current_url, location)?;
            continue;
        }
        return parse_bytes_response(response).await;
    }

    Err(Error::InvalidUrl("too many redirects".to_string()))
}

async fn put_bytes_with_client(
    client: &reqwest::Client,
    url: &str,
    body: &[u8],
    headers: &[(&str, String)],
) -> Result<(), Error> {
    let header_map = build_header_map(headers)?;
    let mut current_url = parse_url(url)?;
    for _ in 0..MAX_REDIRECTS {
        let response = client
            .put(current_url.clone())
            .headers(header_map.clone())
            .body(body.to_vec())
            .send()
            .await?;
        if response.status().is_redirection()
            && let Some(location) = response.headers().get(LOCATION)
        {
            current_url = resolve_redirect(&current_url, location)?;
            continue;
        }
        return parse_empty_response(response).await;
    }

    Err(Error::InvalidUrl("too many redirects".to_string()))
}

fn build_header_map(headers: &[(&str, String)]) -> Result<HeaderMap, Error> {
    let mut header_map = HeaderMap::new();
    for (name, value) in headers {
        let header_name =
            HeaderName::from_bytes(name.as_bytes()).map_err(|e| Error::Parse(e.to_string()))?;
        let header_value = HeaderValue::from_str(value).map_err(|e| Error::Parse(e.to_string()))?;
        header_map.insert(header_name, header_value);
    }
    Ok(header_map)
}

fn parse_url(url: &str) -> Result<Url, Error> {
    Url::parse(url).map_err(|e| Error::InvalidUrl(format!("invalid url: {e}")))
}

fn resolve_redirect(current_url: &Url, location: &HeaderValue) -> Result<Url, Error> {
    let next = location
        .to_str()
        .map_err(|e| Error::InvalidUrl(format!("invalid redirect location: {e}")))?;
    Url::parse(next)
        .or_else(|_| current_url.join(next))
        .map_err(|e| Error::InvalidUrl(format!("invalid redirect location: {e}")))
}

/// Pass through successful responses; turn error statuses into [`Error::Http`].
async fn check_success(response: Response) -> Result<Response, Error> {
    if response.status().is_success() {
        return Ok(response);
    }
    let status = response.status().as_u16();
    let body = response
        .text()
        .await
        .unwrap_or_else(|_| "failed to read error body".to_string());
    let (code, message) = parse_api_error_body(&body);
    Err(Error::Http {
        status,
        code,
        message,
    })
}

async fn parse_text_response(response: Response) -> Result<String, Error> {
    check_success(response)
        .await?
        .text()
        .await
        .map_err(Into::into)
}

async fn parse_json_response<T: DeserializeOwned>(response: Response) -> Result<T, Error> {
    let text = parse_text_response(response).await?;
    serde_json::from_str(&text).map_err(Into::into)
}

async fn parse_empty_response(response: Response) -> Result<(), Error> {
    check_success(response).await.map(drop)
}

async fn parse_bytes_response(response: Response) -> Result<Vec<u8>, Error> {
    check_success(response)
        .await?
        .bytes()
        .await
        .map(|bytes| bytes.to_vec())
        .map_err(Into::into)
}

fn path_contains_dot_segments(path: &str) -> bool {
    path.split(['?', '#'])
        .next()
        .unwrap_or(path)
        .split('/')
        .any(|segment| {
            matches!(segment, "." | "..")
                || segment.eq_ignore_ascii_case("%2e")
                || segment.eq_ignore_ascii_case("%2e%2e")
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};

    fn test_client(base_url: &str) -> HttpClient {
        HttpClient::new_with_config(HttpConfig {
            base_url: base_url.to_string(),
            ..HttpConfig::default()
        })
        .expect("test client creation should succeed")
    }

    #[test]
    fn test_client_creation() {
        let client = test_client("https://api.ente.com/");
        assert_eq!(client.base_url, "https://api.ente.com");
    }

    #[test]
    fn test_parse_error_conversion() {
        let bad_json = "not json";
        let err: Result<PingResponse, Error> = serde_json::from_str(bad_json).map_err(|e| e.into());
        assert!(matches!(err, Err(Error::Parse(_))))
    }

    #[test]
    fn test_parse_api_error_body_prefers_message_and_preserves_code() {
        let (code, message) =
            parse_api_error_body(r#"{"code":"TOO_MANY_WRONG_ATTEMPTS","message":"wait"}"#);
        assert_eq!(code.as_deref(), Some("TOO_MANY_WRONG_ATTEMPTS"));
        assert_eq!(message, "wait");
    }

    #[test]
    fn test_parse_api_error_body_falls_back_to_code_when_message_missing() {
        let (code, message) = parse_api_error_body(r#"{"code":"SESSION_EXPIRED"}"#);
        assert_eq!(code.as_deref(), Some("SESSION_EXPIRED"));
        assert_eq!(message, "SESSION_EXPIRED");
    }

    #[test]
    fn test_request_url_uses_string_join() {
        let client = test_client("https://api.ente.com/v1");
        let url = client.request_url("/ping").unwrap();
        assert_eq!(url, "https://api.ente.com/v1/ping");
    }

    #[test]
    fn test_request_url_preserves_query_and_special_bytes() {
        let client = test_client("https://api.ente.com/v1");
        let url = client.request_url("/%2e%2e%5cadmin?fresh=true").unwrap();
        assert_eq!(url, "https://api.ente.com/v1/%2e%2e%5cadmin?fresh=true");
    }

    #[test]
    fn test_path_contains_dot_segments() {
        assert!(!path_contains_dot_segments("/ping?fresh=true"));
        assert!(path_contains_dot_segments("/../admin"));
        assert!(path_contains_dot_segments("/safe/%2e%2e/admin"));
        assert!(path_contains_dot_segments("/safe/%2E/admin"));
    }

    #[test]
    fn test_request_url_rejects_missing_leading_slash() {
        let client = test_client("https://api.ente.com");
        let err = client.request_url("ping").unwrap_err();
        assert!(matches!(err, Error::InvalidUrl(_)));
    }

    #[test]
    fn test_new_rejects_invalid_base_url() {
        assert!(matches!(
            HttpClient::new("not a url"),
            Err(Error::InvalidUrl(_))
        ));
    }

    #[test]
    fn test_new_rejects_base_url_with_query() {
        assert!(matches!(
            HttpClient::new("https://api.ente.com/v1?stale=true"),
            Err(Error::InvalidUrl(_))
        ));
    }

    #[test]
    fn test_new_rejects_base_url_with_fragment() {
        assert!(matches!(
            HttpClient::new("https://api.ente.com/v1#old"),
            Err(Error::InvalidUrl(_))
        ));
    }

    #[test]
    fn test_set_auth_token_replaces_token() {
        let client = test_client("https://api.ente.com");
        client.set_auth_token(Some("token-1".to_string()));
        assert_eq!(
            client
                .auth_token
                .read()
                .unwrap()
                .as_ref()
                .map(|token| token.as_str()),
            Some("token-1")
        );
        client.set_auth_token(None);
        assert_eq!(
            client
                .auth_token
                .read()
                .unwrap()
                .as_ref()
                .map(|token| token.as_str()),
            None
        );
    }

    #[tokio::test]
    async fn object_store_client_only_sends_explicit_headers() {
        let mut server = Server::new_async().await;
        let get_mock = server
            .mock("GET", "/download")
            .match_header("x-auth-token", Matcher::Missing)
            .match_header("x-client-package", Matcher::Missing)
            .match_header("x-client-version", Matcher::Missing)
            .match_header("user-agent", Matcher::Missing)
            .with_status(200)
            .with_body("ok")
            .create_async()
            .await;
        let put_mock = server
            .mock("PUT", "/upload")
            .match_header("content-md5", "digest")
            .match_header("x-auth-token", Matcher::Missing)
            .match_header("x-client-package", Matcher::Missing)
            .match_header("x-client-version", Matcher::Missing)
            .match_header("user-agent", Matcher::Missing)
            .with_status(200)
            .create_async()
            .await;

        let client = HttpClient::new_with_config(HttpConfig {
            base_url: server.url(),
            auth_token: Some("auth-token".to_string()),
            user_agent: Some("ente-core-test".to_string()),
            client_package: Some("io.ente.photos".to_string()),
            client_version: Some("1.0.0".to_string()),
            timeout_secs: None,
        })
        .unwrap();
        let object_store = client.object_store();

        let bytes = object_store
            .get_bytes(&format!("{}/download", server.url()))
            .await
            .unwrap();
        object_store
            .put_bytes(
                &format!("{}/upload", server.url()),
                b"payload",
                &[("Content-MD5", "digest".to_string())],
            )
            .await
            .unwrap();

        get_mock.assert_async().await;
        put_mock.assert_async().await;
        assert_eq!(bytes, b"ok");
    }

    #[tokio::test]
    async fn api_json_calls_still_follow_redirects() {
        let mut server = Server::new_async().await;

        let redirect_mock = server
            .mock("GET", "/ping")
            .match_header("x-auth-token", "auth-token")
            .with_status(302)
            .with_header("location", "/pong")
            .create_async()
            .await;

        let target_mock = server
            .mock("GET", "/pong")
            .match_header("x-auth-token", "auth-token")
            .with_status(200)
            .with_body(
                serde_json::json!({
                    "message": "pong",
                    "id": "redirected"
                })
                .to_string(),
            )
            .create_async()
            .await;

        let client = HttpClient::new_with_config(HttpConfig {
            base_url: server.url(),
            auth_token: Some("auth-token".to_string()),
            user_agent: None,
            client_package: None,
            client_version: None,
            timeout_secs: None,
        })
        .unwrap();

        let response: PingResponse = client.get_json("/ping", &[]).await.unwrap();

        redirect_mock.assert_async().await;
        target_mock.assert_async().await;
        assert_eq!(response.message, "pong");
        assert_eq!(response.id, "redirected");
    }
}
