use crate::api::client::{AppClient, download_from_proxy};
use crate::api::models::{
    Collection, File, GetCollectionsResponse, GetDiffResponse, GetFileResponse, GetFileUrlResponse,
    GetFilesResponse, GetThumbnailUrlResponse, UserDetails,
};
use crate::models::error::Result;
use ente_core::http;

pub struct ApiMethods<'a> {
    client: &'a AppClient,
}

impl<'a> ApiMethods<'a> {
    pub fn new(client: &'a AppClient) -> Self {
        Self { client }
    }

    pub async fn get_user_details(&self) -> Result<UserDetails> {
        let api = self.client.api();
        Ok(http::retry(|| async {
            api.get("/users/details")
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn get_collections(&self, since_time: i64) -> Result<Vec<Collection>> {
        let api = self.client.api();
        let response: GetCollectionsResponse = http::retry(|| async {
            api.get("/collections/v2")
                .query(&[("sinceTime", since_time.to_string())])
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.collections)
    }

    pub async fn get_collection(&self, collection_id: i64) -> Result<Collection> {
        let api = self.client.api();
        Ok(http::retry(|| async {
            api.get(&format!("/collections/{collection_id}"))
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?)
    }

    pub async fn get_collection_files(
        &self,
        collection_id: i64,
        since_time: i64,
    ) -> Result<(Vec<File>, bool)> {
        let api = self.client.api();
        let response: GetFilesResponse = http::retry(|| async {
            api.get("/collections/v2/diff")
                .query(&[
                    ("collectionID", collection_id.to_string()),
                    ("sinceTime", since_time.to_string()),
                ])
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok((response.diff, response.has_more))
    }

    pub async fn get_file(&self, collection_id: i64, file_id: i64) -> Result<File> {
        let api = self.client.api();
        let response: GetFileResponse = http::retry(|| async {
            api.get("/collections/file")
                .query(&[
                    ("collectionID", collection_id.to_string()),
                    ("fileID", file_id.to_string()),
                ])
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.file)
    }

    pub async fn get_diff(&self, since_time: i64, limit: i32) -> Result<(Vec<File>, bool)> {
        let api = self.client.api();
        let response: GetDiffResponse = http::retry(|| async {
            api.get("/diff")
                .query(&[
                    ("sinceTime", since_time.to_string()),
                    ("limit", limit.to_string()),
                ])
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok((response.diff, response.has_more))
    }

    async fn get_signed_file_url(&self, file_id: i64) -> Result<String> {
        let api = self.client.api();
        let response: GetFileUrlResponse = http::retry(|| async {
            api.get(&format!("/files/download/v2/{file_id}"))
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.url)
    }

    async fn get_signed_thumbnail_url(&self, file_id: i64) -> Result<String> {
        let api = self.client.api();
        let response: GetThumbnailUrlResponse = http::retry(|| async {
            api.get(&format!("/files/preview/v2/{file_id}"))
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok(response.url)
    }

    pub async fn download_file(&self, file_id: i64) -> Result<Vec<u8>> {
        match self.client.download_proxies() {
            Some(proxies) => download_from_proxy(&proxies.files, file_id).await,
            None => {
                let url = self.get_signed_file_url(file_id).await?;
                self.client.download_url(&url).await
            }
        }
    }

    pub async fn download_thumbnail(&self, file_id: i64) -> Result<Vec<u8>> {
        match self.client.download_proxies() {
            Some(proxies) => download_from_proxy(&proxies.thumbnails, file_id).await,
            None => {
                let url = self.get_signed_thumbnail_url(file_id).await?;
                self.client.download_url(&url).await
            }
        }
    }

    pub async fn get_trash(&self, since_time: i64) -> Result<(Vec<File>, bool)> {
        let api = self.client.api();
        let response: GetDiffResponse = http::retry(|| async {
            api.get("/trash/v2")
                .query(&[("sinceTime", since_time.to_string())])
                .send()
                .await?
                .error_for_code()
                .await?
                .json()
                .await
        })
        .await?;
        Ok((response.diff, response.has_more))
    }

    pub async fn delete_from_trash(&self, file_ids: &[i64]) -> Result<()> {
        let api = self.client.api();
        let body = serde_json::json!({ "fileIDs": file_ids });
        http::retry(|| async {
            api.post("/trash/delete")
                .json(&body)
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?;
        Ok(())
    }

    pub async fn empty_trash(&self) -> Result<()> {
        let api = self.client.api();
        http::retry(|| async {
            api.delete("/trash/empty")
                .send()
                .await?
                .error_for_code()
                .await?;
            Ok(())
        })
        .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockito::{Matcher, Server};

    #[tokio::test]
    async fn test_self_hosted_download_uses_signed_url() {
        let mut server = Server::new_async().await;
        let signed_url = format!("{}/object", server.url());
        let url_mock = server
            .mock("GET", "/files/download/v2/12345")
            .match_header("x-auth-token", "token")
            .match_header("x-client-package", "io.ente.locker")
            .with_body(format!(r#"{{"url":"{signed_url}"}}"#))
            .create_async()
            .await;
        let download_mock = server
            .mock("GET", "/object")
            .match_header("x-auth-token", Matcher::Missing)
            .match_header("x-client-package", Matcher::Missing)
            .with_body("file")
            .create_async()
            .await;
        let client =
            AppClient::new(Some(server.url()), crate::models::account::App::Locker).unwrap();
        client.set_token("token");

        let bytes = ApiMethods::new(&client).download_file(12345).await.unwrap();

        url_mock.assert_async().await;
        download_mock.assert_async().await;
        assert_eq!(bytes, b"file");
    }
}
