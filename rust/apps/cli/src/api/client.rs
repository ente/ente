use crate::models::account::App;
use crate::models::error::Result;
use ente_core::http::{self, Api, ApiConfig, Auth, Http, RetryProfile};
use ente_core::urls::PRODUCTION_API_ORIGIN;
use std::sync::RwLock;

pub(crate) const USER_AGENT: &str = concat!("ente-rs/", env!("CARGO_PKG_VERSION"));
const FILES_ORIGIN: &str = "https://files.ente.com";
const THUMBNAILS_ORIGIN: &str = "https://thumbnails.ente.com";

pub struct AppClient {
    origin: String,
    app: App,
    museum: Api,
    proxies: Option<DownloadProxies>,
    token: RwLock<Option<String>>,
}

pub(crate) struct DownloadProxies {
    pub(crate) files: Api,
    pub(crate) thumbnails: Api,
}

impl AppClient {
    pub fn new(origin: Option<String>, app: App) -> Result<Self> {
        let http = Http::new()?;
        let origin = origin.unwrap_or_else(|| PRODUCTION_API_ORIGIN.to_string());
        let client_package = app.client_package();
        let museum = new_api(&http, &origin, client_package);
        let proxies = (origin == PRODUCTION_API_ORIGIN).then(|| DownloadProxies {
            files: new_api(&http, FILES_ORIGIN, client_package),
            thumbnails: new_api(&http, THUMBNAILS_ORIGIN, client_package),
        });
        Ok(Self {
            origin,
            app,
            museum,
            proxies,
            token: RwLock::new(None),
        })
    }

    pub fn set_token(&self, token: &str) {
        self.museum.set_auth(Some(Auth::User(token.to_owned())));
        if let Some(proxies) = &self.proxies {
            proxies.files.set_auth(Some(Auth::User(token.to_owned())));
            proxies
                .thumbnails
                .set_auth(Some(Auth::User(token.to_owned())));
        }
        *self.token.write().unwrap() = Some(token.to_owned());
    }

    pub fn token(&self) -> Option<String> {
        self.token.read().unwrap().clone()
    }

    pub fn origin(&self) -> &str {
        &self.origin
    }

    pub fn app(&self) -> App {
        self.app
    }

    pub(crate) fn api(&self) -> &Api {
        &self.museum
    }

    pub(crate) fn download_proxies(&self) -> Option<&DownloadProxies> {
        self.proxies.as_ref()
    }

    pub(crate) async fn download_url(&self, url: &str) -> Result<Vec<u8>> {
        Ok(
            http::retry_with_profile(RetryProfile::Background, || async {
                self.museum
                    .http()
                    .get(url)
                    .send()
                    .await?
                    .error_for_status()?
                    .bytes()
                    .await
            })
            .await?,
        )
    }
}

fn new_api(http: &Http, origin: &str, client_package: &str) -> Api {
    Api::new(
        http.clone(),
        ApiConfig {
            origin: origin.to_owned(),
            client_package: Some(client_package.to_owned()),
            client_version: None,
            user_agent: Some(USER_AGENT.to_string()),
            auth: None,
        },
    )
}

pub(crate) async fn download_from_proxy(api: &Api, file_id: i64) -> Result<Vec<u8>> {
    Ok(
        http::retry_with_profile(RetryProfile::Background, || async {
            api.get("/")
                .query(&[("fileID", file_id)])
                .send()
                .await?
                .error_for_status()?
                .bytes()
                .await
        })
        .await?,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};

    #[test]
    fn selects_download_backend_from_origin() {
        let production = AppClient::new(None, App::Photos).unwrap();
        assert!(production.download_proxies().is_some());

        let self_hosted = AppClient::new(Some("https://example.com".into()), App::Photos).unwrap();
        assert!(self_hosted.download_proxies().is_none());
    }

    #[tokio::test]
    async fn app_clients_keep_museum_auth_scoped_to_app() {
        let mut server = Server::new_async().await;
        let auth_download = server
            .mock("GET", "/")
            .match_query(Matcher::UrlEncoded("fileID".into(), "1".into()))
            .match_header("x-auth-token", "auth-token")
            .match_header("x-client-package", "io.ente.auth")
            .with_body("auth")
            .create_async()
            .await;
        let photos_download = server
            .mock("GET", "/")
            .match_query(Matcher::UrlEncoded("fileID".into(), "2".into()))
            .match_header("x-auth-token", "photos-token")
            .match_header("x-client-package", "io.ente.photos")
            .with_body("photos")
            .create_async()
            .await;
        let auth_client = AppClient::new(Some(server.url()), App::Auth).unwrap();
        auth_client.set_token("auth-token");
        let photos_client = AppClient::new(Some(server.url()), App::Photos).unwrap();
        photos_client.set_token("photos-token");

        let auth_bytes = download_from_proxy(auth_client.api(), 1).await.unwrap();
        let photos_bytes = download_from_proxy(photos_client.api(), 2).await.unwrap();

        auth_download.assert_async().await;
        photos_download.assert_async().await;
        assert_eq!(auth_bytes, b"auth");
        assert_eq!(photos_bytes, b"photos");
    }
}
