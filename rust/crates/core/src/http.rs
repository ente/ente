//! HTTP client for the Ente API.
//!
//! These are thin wrappers over [`reqwest`] with Ente-specific ergonomics.
//! [`Http`] is a transparent wrapper that adds nothing of its own to a request;
//! beyond its convenience methods it exists so that a single connection pool can
//! be shared across clients (an `Http` is cheap to clone, and clones share the
//! pool). [`Api`] is tailored to one Ente API origin, with pluggable
//! authentication and built-in Ente headers.
//!
//! The interface mirrors reqwest, so if you know reqwest you will feel at home.

use std::future::Future;
use std::sync::{PoisonError, RwLock};
use std::time::Duration;

#[cfg(target_arch = "wasm32")]
use gloo_timers::future::sleep;
#[cfg(not(target_arch = "wasm32"))]
use tokio::time::sleep;

use reqwest::header::{HeaderName, HeaderValue};
use reqwest::{Method, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::ZeroizeOnDrop;

const CLIENT_PACKAGE: HeaderName = HeaderName::from_static("x-client-package");
const CLIENT_VERSION: HeaderName = HeaderName::from_static("x-client-version");
const AUTH_TOKEN: HeaderName = HeaderName::from_static("x-auth-token");
const ACCESS_TOKEN: HeaderName = HeaderName::from_static("x-auth-access-token");
const ACCESS_TOKEN_JWT: HeaderName = HeaderName::from_static("x-auth-access-token-jwt");
const LINK_DEVICE_TOKEN: HeaderName = HeaderName::from_static("x-auth-link-device-token");
const CAST_ACCESS_TOKEN: HeaderName = HeaderName::from_static("x-cast-access-token");

/// An error from an HTTP request.
#[derive(Error, Debug)]
pub enum Error {
    /// The request could not be sent, or the response could not be read.
    #[error(transparent)]
    Network(NetworkError),

    /// The server responded with a non-2xx status.
    #[error("HTTP {status} at {path}")]
    Http {
        /// The HTTP status code.
        status: u16,
        /// The request path that failed, with its query stripped.
        path: String,
    },

    /// The server responded with a non-2xx status, and its body carried an
    /// Ente API error code.
    #[error("HTTP {status} {code} at {path}")]
    Api {
        /// The HTTP status code.
        status: u16,
        /// The request path that failed, with its query stripped.
        path: String,
        /// The server's error code, e.g. `USER_NOT_REGISTERED`.
        code: String,
    },

    /// The response arrived, but its body was not the expected JSON.
    #[error(transparent)]
    Parse(ParseError),
}

/// The underlying failure of a [`Network`](Error::Network) error.
#[derive(Error, Debug)]
#[error(transparent)]
pub struct NetworkError(reqwest::Error);

/// The underlying failure of a [`Parse`](Error::Parse) error.
#[derive(Error, Debug)]
#[error(transparent)]
pub struct ParseError(serde_json::Error);

impl Error {
    /// A connection could not be established.
    pub fn is_connect(&self) -> bool {
        #[cfg(not(target_arch = "wasm32"))]
        {
            matches!(self, Error::Network(e) if e.0.is_connect())
        }
        #[cfg(target_arch = "wasm32")]
        {
            false
        }
    }

    /// The request timed out.
    pub fn is_timeout(&self) -> bool {
        matches!(self, Error::Network(e) if e.0.is_timeout())
    }

    /// The HTTP status code, if the server responded with a non-2xx status.
    pub fn status_code(&self) -> Option<u16> {
        match self {
            Error::Http { status, .. } | Error::Api { status, .. } => Some(*status),
            _ => None,
        }
    }

    /// Returns `true` if the request failed in transit, or if the server
    /// answered with a 429 or a 5xx status.
    pub fn is_retryable(&self) -> bool {
        match self {
            Error::Network(e) => e.0.is_request() || e.0.is_body(),
            Error::Http { status, .. } | Error::Api { status, .. } => {
                *status == 429 || *status >= 500
            }
            Error::Parse(_) => false,
        }
    }
}

impl From<reqwest::Error> for Error {
    fn from(mut e: reqwest::Error) -> Self {
        if let Some(url) = e.url_mut() {
            url.set_query(None);
        }
        Error::Network(NetworkError(e))
    }
}

/// A bare HTTP client for requests to arbitrary URLs.
///
/// Cloning is cheap and shares one connection pool.
#[derive(Clone)]
pub struct Http {
    client: reqwest::Client,
}

impl Http {
    /// Create a transport with default connect and read timeouts.
    pub fn new() -> Result<Self, Error> {
        let builder = reqwest::Client::builder();
        #[cfg(not(target_arch = "wasm32"))]
        let builder = builder
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(30));
        Ok(Http {
            client: builder.build()?,
        })
    }

    /// Start a GET request to `url`.
    pub fn get(&self, url: &str) -> RequestBuilder {
        self.request(Method::GET, url)
    }

    /// Start a POST request to `url`.
    pub fn post(&self, url: &str) -> RequestBuilder {
        self.request(Method::POST, url)
    }

    /// Start a PUT request to `url`.
    pub fn put(&self, url: &str) -> RequestBuilder {
        self.request(Method::PUT, url)
    }

    /// Start a DELETE request to `url`.
    pub fn delete(&self, url: &str) -> RequestBuilder {
        self.request(Method::DELETE, url)
    }

    /// Start a HEAD request to `url`.
    pub fn head(&self, url: &str) -> RequestBuilder {
        self.request(Method::HEAD, url)
    }

    fn request(&self, method: Method, url: &str) -> RequestBuilder {
        RequestBuilder(self.client.request(method, url))
    }
}

/// How an [`Api`] authenticates its requests.
///
/// An `Api` uses a single scheme for its lifetime. To act as more than one
/// identity at once, hold several `Api`s over the same [`Http`].
#[derive(ZeroizeOnDrop)]
pub enum Auth {
    /// A logged-in user, sent as the `X-Auth-Token` header.
    User(String),
    /// A viewer of a public album, sent as `X-Auth-Access-Token` with an optional
    /// password JWT and link-device token.
    PublicAlbum {
        /// The album access token.
        access_token: String,
        /// The password-protected album's JWT, if the album has a password.
        jwt: Option<String>,
        /// The link-device token, if one has been issued.
        link_device: Option<String>,
    },
    /// A cast session, sent as the `X-Cast-Access-Token` header.
    Cast(String),
}

impl Auth {
    fn apply(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match self {
            Auth::User(token) => sensitive_header(builder, AUTH_TOKEN, token),
            Auth::PublicAlbum {
                access_token,
                jwt,
                link_device,
            } => {
                let mut builder = sensitive_header(builder, ACCESS_TOKEN, access_token);
                if let Some(jwt) = jwt {
                    builder = sensitive_header(builder, ACCESS_TOKEN_JWT, jwt);
                }
                if let Some(link_device) = link_device {
                    builder = sensitive_header(builder, LINK_DEVICE_TOKEN, link_device);
                }
                builder
            }
            Auth::Cast(token) => sensitive_header(builder, CAST_ACCESS_TOKEN, token),
        }
    }
}

fn sensitive_header(
    builder: reqwest::RequestBuilder,
    name: HeaderName,
    value: &str,
) -> reqwest::RequestBuilder {
    match HeaderValue::from_str(value) {
        Ok(mut value) => {
            value.set_sensitive(true);
            builder.header(name, value)
        }
        // reqwest hits the same parse failure, and reports it at send time.
        Err(_) => builder.header(name, value),
    }
}

/// Settings for building an [`Api`].
pub struct ApiConfig {
    /// The Ente API origin: scheme, host, and port, e.g. `https://api.ente.com`.
    pub origin: String,
    /// The client package, sent as `X-Client-Package` (e.g. `io.ente.photos`).
    pub client_package: Option<String>,
    /// The client version, sent as `X-Client-Version`.
    pub client_version: Option<String>,
    /// The user agent to send. Ignored on wasm.
    pub user_agent: Option<String>,
    /// The authentication to start with, or `None` to start unauthenticated.
    pub auth: Option<Auth>,
}

impl ApiConfig {
    /// Config with only the origin set.
    pub fn new(origin: String) -> Self {
        Self {
            origin,
            client_package: None,
            client_version: None,
            user_agent: None,
            auth: None,
        }
    }
}

/// An Ente API client, bound to a single origin.
///
/// Requests take a path relative to that origin and automatically carry the Ente
/// client headers and the credentials of the [`Auth`] scheme.
pub struct Api {
    http: Http,
    origin: String,
    client_package: Option<String>,
    client_version: Option<String>,
    #[cfg(not(target_arch = "wasm32"))]
    user_agent: Option<String>,
    auth: RwLock<Option<Auth>>,
}

impl Api {
    /// Build a client over `http`, sharing its connection pool.
    pub fn new(http: Http, config: ApiConfig) -> Self {
        Self {
            http,
            origin: config.origin,
            client_package: config.client_package,
            client_version: config.client_version,
            #[cfg(not(target_arch = "wasm32"))]
            user_agent: config.user_agent,
            auth: RwLock::new(config.auth),
        }
    }

    /// The bare transport underneath, for requests to other hosts.
    pub fn http(&self) -> &Http {
        &self.http
    }

    /// Change the authentication used for subsequent requests, e.g. after login.
    pub fn set_auth(&self, auth: Option<Auth>) {
        *self.auth.write().unwrap_or_else(PoisonError::into_inner) = auth;
    }

    /// Start a GET request to `path`, relative to the origin.
    pub fn get(&self, path: &str) -> RequestBuilder {
        self.request(Method::GET, path)
    }

    /// Start a POST request to `path`, relative to the origin.
    pub fn post(&self, path: &str) -> RequestBuilder {
        self.request(Method::POST, path)
    }

    /// Start a PUT request to `path`, relative to the origin.
    pub fn put(&self, path: &str) -> RequestBuilder {
        self.request(Method::PUT, path)
    }

    /// Start a DELETE request to `path`, relative to the origin.
    pub fn delete(&self, path: &str) -> RequestBuilder {
        self.request(Method::DELETE, path)
    }

    /// Start a HEAD request to `path`, relative to the origin.
    pub fn head(&self, path: &str) -> RequestBuilder {
        self.request(Method::HEAD, path)
    }

    /// Check that the server is reachable.
    pub async fn ping(&self) -> Result<PingResponse, Error> {
        self.get("/ping")
            .send()
            .await?
            .error_for_status()?
            .json()
            .await
    }

    fn request(&self, method: Method, path: &str) -> RequestBuilder {
        let mut builder = match Url::parse(&self.origin) {
            Ok(mut url) => {
                url.set_path(path);
                self.http.client.request(method, url)
            }
            // reqwest hits the same parse failure, and reports it at send time.
            Err(_) => self.http.client.request(method, self.origin.as_str()),
        };
        if let Some(client_package) = &self.client_package {
            builder = builder.header(CLIENT_PACKAGE, client_package);
        }
        if let Some(version) = &self.client_version {
            builder = builder.header(CLIENT_VERSION, version);
        }
        #[cfg(not(target_arch = "wasm32"))]
        if let Some(user_agent) = &self.user_agent {
            builder = builder.header(reqwest::header::USER_AGENT, user_agent);
        }
        if let Some(auth) = &*self.auth.read().unwrap_or_else(PoisonError::into_inner) {
            builder = auth.apply(builder);
        }
        RequestBuilder(builder)
    }
}

/// A request under construction.
///
/// Configure it by chaining methods, then [`send`](Self::send) it.
#[must_use = "a request is only sent when you call send()"]
pub struct RequestBuilder(reqwest::RequestBuilder);

impl RequestBuilder {
    /// Add URL query parameters, serialized from any [`Serialize`] value with
    /// `serde_urlencoded`.
    pub fn query<Q: Serialize + ?Sized>(self, query: &Q) -> Self {
        Self(self.0.query(query))
    }

    /// Add a header.
    pub fn header(self, name: &str, value: &str) -> Self {
        Self(self.0.header(name, value))
    }

    /// Set the body to `body` serialized as JSON, with a JSON `Content-Type`.
    pub fn json<B: Serialize + ?Sized>(self, body: &B) -> Self {
        Self(self.0.json(body))
    }

    /// Set the body to raw bytes.
    pub fn body(self, body: Vec<u8>) -> Self {
        Self(self.0.body(body))
    }

    /// Send the request, returning the [`Response`] for any status.
    pub async fn send(self) -> Result<Response, Error> {
        Ok(Response(self.0.send().await?))
    }
}

/// The response to a sent request.
///
/// The usual flow is to call [`error_for_status`](Self::error_for_status) to
/// turn a non-2xx status into an error, then read the body with
/// [`json`](Self::json), [`text`](Self::text), [`bytes`](Self::bytes), or
/// [`bytes_stream`](Self::bytes_stream).
///
/// The [`status`](Self::status) and [`header`](Self::header)s are also available
/// directly.
#[derive(Debug)]
pub struct Response(reqwest::Response);

impl Response {
    /// The HTTP status code.
    pub fn status(&self) -> u16 {
        self.0.status().as_u16()
    }

    /// The value of a response header, if present and valid UTF-8.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.0.headers().get(name).and_then(|v| v.to_str().ok())
    }

    /// All the response headers.
    pub fn headers(&self) -> &reqwest::header::HeaderMap {
        self.0.headers()
    }

    /// Return an [`Error::Http`] if the status is not 2xx, otherwise the response.
    pub fn error_for_status(self) -> Result<Self, Error> {
        if self.0.status().is_success() {
            Ok(self)
        } else {
            Err(Error::Http {
                status: self.0.status().as_u16(),
                path: self.0.url().path().to_owned(),
            })
        }
    }

    /// Return an [`Error::Api`] carrying the server's error code if the
    /// status is not 2xx, otherwise the response.
    ///
    /// A variant of [`error_for_status`](Self::error_for_status) for call
    /// sites that need to act on the error code that the Ente API includes
    /// in its error responses. When the body does not carry a code, this
    /// returns the same [`Error::Http`] that `error_for_status` would.
    pub async fn error_for_code(self) -> Result<Self, Error> {
        if self.0.status().is_success() {
            return Ok(self);
        }
        let status = self.status();
        let path = self.0.url().path().to_owned();
        match serde_json::from_slice::<ApiErrorEnvelope>(&self.bytes().await?) {
            Ok(envelope) => Err(Error::Api {
                status,
                path,
                code: envelope.code,
            }),
            Err(_) => Err(Error::Http { status, path }),
        }
    }

    /// Read the whole body and deserialize it as JSON.
    pub async fn json<T: DeserializeOwned>(self) -> Result<T, Error> {
        serde_json::from_slice(&self.0.bytes().await?).map_err(|e| Error::Parse(ParseError(e)))
    }

    /// Read the whole body as text.
    pub async fn text(self) -> Result<String, Error> {
        Ok(self.0.text().await?)
    }

    /// Read the whole body as bytes.
    pub async fn bytes(self) -> Result<Vec<u8>, Error> {
        Ok(self.0.bytes().await?.into())
    }
}

#[cfg(not(target_arch = "wasm32"))]
mod body_stream {
    use std::pin::Pin;
    use std::task::{Context, Poll};

    use bytes::Bytes;
    use futures_core::Stream;

    use super::{Error, Response};

    impl Response {
        /// Stream the body in chunks instead of buffering it, for large downloads.
        pub fn bytes_stream(self) -> impl Stream<Item = Result<Bytes, Error>> + Send {
            BytesStream(Box::pin(self.0.bytes_stream()))
        }
    }

    struct BytesStream(Pin<Box<dyn Stream<Item = reqwest::Result<Bytes>> + Send>>);

    impl Stream for BytesStream {
        type Item = Result<Bytes, Error>;

        fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
            self.0
                .as_mut()
                .poll_next(cx)
                .map(|chunk| chunk.map(|chunk| chunk.map_err(Error::from)))
        }
    }
}

/// The Ente API's error body, e.g. `{"code": "USER_NOT_REGISTERED", ...}`.
#[derive(Deserialize)]
struct ApiErrorEnvelope {
    code: String,
}

/// The reply from the `/ping` endpoint.
#[derive(Deserialize, Debug)]
pub struct PingResponse {
    /// Always `"pong"`.
    pub message: String,
    /// The server's git commit hash.
    pub id: String,
}

/// How persistently to retry a failed request.
///
/// Both profiles make one original attempt and up to three retries. The
/// delays match the web client's retry schedules.
#[derive(Clone, Copy, Debug)]
pub enum RetryProfile {
    /// For requests a user is waiting on. Retries after 2, 5, and 10 seconds.
    Interactive,
    /// For unattended work, where waiting longer handles remote hiccups
    /// better. Retries after 10, 30, and 120 seconds.
    Background,
}

impl RetryProfile {
    fn delays(self) -> [Duration; 3] {
        match self {
            RetryProfile::Interactive => [2, 5, 10].map(Duration::from_secs),
            RetryProfile::Background => [10, 30, 120].map(Duration::from_secs),
        }
    }
}

/// Run `operation`, retrying failures per [`RetryProfile::Interactive`].
///
/// A failure is retried when [`Error::is_retryable`] says so: the request
/// failed in transit, or the server answered with a 429 or a 5xx status.
/// Any other error returns immediately.
///
/// Each retry runs the whole closure again, so wrap only operations that
/// are safe to repeat.
pub async fn retry<T, F, Fut>(operation: F) -> Result<T, Error>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, Error>>,
{
    retry_with_profile(RetryProfile::Interactive, operation).await
}

/// Like [`retry`](retry()), but with an explicitly chosen profile.
pub async fn retry_with_profile<T, F, Fut>(profile: RetryProfile, operation: F) -> Result<T, Error>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, Error>>,
{
    retry_with_delays(&profile.delays(), operation).await
}

async fn retry_with_delays<T, F, Fut>(delays: &[Duration], mut operation: F) -> Result<T, Error>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, Error>>,
{
    let mut delays = delays.iter();
    loop {
        match operation().await {
            Ok(value) => return Ok(value),
            Err(error) if error.is_retryable() => match delays.next() {
                Some(delay) => {
                    log::warn!("retrying in {delay:?}: {error}");
                    sleep(*delay).await;
                }
                None => return Err(error),
            },
            Err(error) => return Err(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use futures_core::Stream;
    use mockito::{Matcher, Server, ServerGuard};

    use super::*;

    fn api(server: &ServerGuard, auth: Option<Auth>) -> Api {
        Api::new(
            Http::new().unwrap(),
            ApiConfig {
                origin: server.url(),
                client_package: Some("io.ente.test".into()),
                client_version: Some("1.0".into()),
                user_agent: None,
                auth,
            },
        )
    }

    #[tokio::test]
    async fn api_sends_client_and_auth_headers() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/ping")
            .match_header("x-client-package", "io.ente.test")
            .match_header("x-client-version", "1.0")
            .match_header("x-auth-token", "tok")
            .with_body(r#"{"message":"pong","id":"abc"}"#)
            .create_async()
            .await;

        let api = api(&server, Some(Auth::User("tok".into())));
        let response = api.ping().await.unwrap();

        mock.assert_async().await;
        assert_eq!(response.message, "pong");
        assert_eq!(response.id, "abc");
    }

    #[tokio::test]
    async fn api_sends_public_album_auth_headers() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/public-collection/info")
            .match_header("x-auth-access-token", "at")
            .match_header("x-auth-access-token-jwt", "jwt")
            .match_header("x-auth-link-device-token", "ld")
            .match_header("x-auth-token", Matcher::Missing)
            .create_async()
            .await;

        let api = api(
            &server,
            Some(Auth::PublicAlbum {
                access_token: "at".into(),
                jwt: Some("jwt".into()),
                link_device: Some("ld".into()),
            }),
        );
        let response = api.get("/public-collection/info").send().await.unwrap();

        mock.assert_async().await;
        assert_eq!(response.status(), 200);
    }

    #[tokio::test]
    async fn set_auth_changes_subsequent_requests() {
        let mut server = Server::new_async().await;
        let unauthed = server
            .mock("GET", "/a")
            .match_header("x-auth-token", Matcher::Missing)
            .create_async()
            .await;
        let authed = server
            .mock("GET", "/b")
            .match_header("x-auth-token", "tok")
            .create_async()
            .await;

        let api = api(&server, None);
        api.get("/a").send().await.unwrap();
        api.set_auth(Some(Auth::User("tok".into())));
        api.get("/b").send().await.unwrap();

        unauthed.assert_async().await;
        authed.assert_async().await;
    }

    #[tokio::test]
    async fn http_sends_only_explicit_headers() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("PUT", "/upload")
            .match_header("x-client-package", Matcher::Missing)
            .match_header("x-client-version", Matcher::Missing)
            .match_header("x-auth-token", Matcher::Missing)
            .match_header("content-type", Matcher::Missing)
            .match_header("content-md5", "digest")
            .match_body("payload")
            .create_async()
            .await;

        let http = Http::new().unwrap();
        http.put(&format!("{}/upload", server.url()))
            .header("Content-MD5", "digest")
            .body(b"payload".to_vec())
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();

        mock.assert_async().await;
    }

    #[tokio::test]
    async fn json_body_sets_content_type() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("POST", "/echo")
            .match_header("content-type", "application/json")
            .match_body(Matcher::JsonString(r#"{"a":1}"#.into()))
            .create_async()
            .await;

        let api = api(&server, None);
        api.post("/echo")
            .json(&serde_json::json!({"a": 1}))
            .send()
            .await
            .unwrap();

        mock.assert_async().await;
    }

    #[tokio::test]
    async fn error_for_status_strips_the_query() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/download")
            .match_query(Matcher::Any)
            .with_status(403)
            .create_async()
            .await;

        let api = api(&server, None);
        let err = api
            .get("/download")
            .query(&[("X-Amz-Signature", "secret")])
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap_err();

        let Error::Http { status, path } = &err else {
            panic!("expected Error::Http, got {err:?}");
        };
        assert_eq!(*status, 403);
        assert_eq!(path, "/download");
        assert!(!err.to_string().contains("secret"));
    }

    #[tokio::test]
    async fn error_for_code_reads_the_code() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/x")
            .with_status(401)
            .with_body(r#"{"code":"SESSION_EXPIRED","message":"session expired"}"#)
            .create_async()
            .await;

        let api = api(&server, None);
        let err = api
            .get("/x")
            .send()
            .await
            .unwrap()
            .error_for_code()
            .await
            .unwrap_err();

        assert!(matches!(
            &err,
            Error::Api { status: 401, path, code }
                if path == "/x" && code == "SESSION_EXPIRED"
        ));
        assert_eq!(err.to_string(), "HTTP 401 SESSION_EXPIRED at /x");
        assert_eq!(err.status_code(), Some(401));
    }

    #[tokio::test]
    async fn error_for_code_without_a_code_is_a_plain_http_error() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/x")
            .with_status(502)
            .with_body("<html>bad gateway</html>")
            .create_async()
            .await;

        let api = api(&server, None);
        let err = api
            .get("/x")
            .send()
            .await
            .unwrap()
            .error_for_code()
            .await
            .unwrap_err();

        assert!(matches!(
            &err,
            Error::Http { status: 502, path } if path == "/x"
        ));
    }

    #[tokio::test]
    async fn error_for_code_passes_a_2xx_through() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/x")
            .with_body("ok")
            .create_async()
            .await;

        let api = api(&server, None);
        let response = api.get("/x").send().await.unwrap();
        let body = response
            .error_for_code()
            .await
            .unwrap()
            .text()
            .await
            .unwrap();
        assert_eq!(body, "ok");
    }

    #[tokio::test]
    async fn invalid_json_is_a_parse_error() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/ping")
            .with_body("not json")
            .create_async()
            .await;

        let api = api(&server, None);
        let err = api.ping().await.unwrap_err();
        assert!(matches!(err, Error::Parse(_)));
    }

    #[tokio::test]
    async fn query_parameters_are_encoded() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/search")
            .match_query(Matcher::UrlEncoded("q".into(), "a b&c".into()))
            .create_async()
            .await;

        let api = api(&server, None);
        api.get("/search")
            .query(&[("q", "a b&c")])
            .send()
            .await
            .unwrap();

        mock.assert_async().await;
    }

    #[tokio::test]
    async fn status_and_header_read_directly() {
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/maybe")
            .with_status(404)
            .with_header("x-request-id", "rid")
            .create_async()
            .await;

        let api = api(&server, None);
        let response = api.get("/maybe").send().await.unwrap();
        assert_eq!(response.status(), 404);
        assert_eq!(response.header("x-request-id"), Some("rid"));
        assert_eq!(response.header("x-absent"), None);
    }

    #[tokio::test]
    async fn bytes_stream_yields_the_body() {
        let body: Vec<u8> = (0..100_000).map(|i| (i % 251) as u8).collect();
        let mut server = Server::new_async().await;
        server
            .mock("GET", "/file")
            .with_body(&body)
            .create_async()
            .await;

        let http = Http::new().unwrap();
        let response = http
            .get(&format!("{}/file", server.url()))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();

        let mut stream = std::pin::pin!(response.bytes_stream());
        let mut out = Vec::new();
        while let Some(chunk) = std::future::poll_fn(|cx| stream.as_mut().poll_next(cx)).await {
            out.extend_from_slice(&chunk.unwrap());
        }
        assert_eq!(out, body);
    }

    #[tokio::test]
    async fn path_cannot_change_the_host() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/@evil.example/ping")
            .match_header("x-auth-token", "tok")
            .create_async()
            .await;

        let api = api(&server, Some(Auth::User("tok".into())));
        api.get("@evil.example/ping").send().await.unwrap();

        mock.assert_async().await;
    }

    #[tokio::test]
    async fn malformed_origin_fails_at_send() {
        let api = Api::new(Http::new().unwrap(), ApiConfig::new("not a url".into()));
        let err = api.get("/ping").send().await.unwrap_err();
        assert!(matches!(err, Error::Network(_)));
    }

    #[tokio::test]
    async fn origin_trailing_slash_is_tolerated() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/ping")
            .with_body(r#"{"message":"pong","id":"abc"}"#)
            .create_async()
            .await;

        let api = Api::new(
            Http::new().unwrap(),
            ApiConfig::new(format!("{}/", server.url())),
        );
        api.ping().await.unwrap();

        mock.assert_async().await;
    }

    #[tokio::test]
    async fn retry_retries_retryable_failures() {
        let mut server = Server::new_async().await;
        let failure = server
            .mock("GET", "/x")
            .with_status(500)
            .expect(1)
            .create_async()
            .await;
        let success = server
            .mock("GET", "/x")
            .with_body("ok")
            .expect(1)
            .create_async()
            .await;

        let api = api(&server, None);
        let body = retry_with_delays(&[Duration::ZERO; 3], || async {
            api.get("/x").send().await?.error_for_status()?.text().await
        })
        .await
        .unwrap();

        assert_eq!(body, "ok");
        failure.assert_async().await;
        success.assert_async().await;
    }

    #[tokio::test]
    async fn retry_returns_non_retryable_failures_immediately() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/x")
            .with_status(404)
            .expect(1)
            .create_async()
            .await;

        let api = api(&server, None);
        let err = retry_with_delays(&[Duration::ZERO; 3], || async {
            api.get("/x").send().await?.error_for_status()?.text().await
        })
        .await
        .unwrap_err();

        assert_eq!(err.status_code(), Some(404));
        mock.assert_async().await;
    }

    #[tokio::test]
    async fn retry_gives_up_once_the_delays_are_exhausted() {
        let mut server = Server::new_async().await;
        let mock = server
            .mock("GET", "/x")
            .with_status(500)
            .expect(4)
            .create_async()
            .await;

        let api = api(&server, None);
        let err = retry_with_delays(&[Duration::ZERO; 3], || async {
            api.get("/x").send().await?.error_for_status()?.text().await
        })
        .await
        .unwrap_err();

        assert_eq!(err.status_code(), Some(500));
        mock.assert_async().await;
    }
}
