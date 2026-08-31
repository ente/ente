use std::sync::RwLock;

use ente_contacts::{
    AttachmentType, ContactData, ContactOutput, ContactRecord, WrappedRootContactKey,
};
use ente_core::{
    Session, b64,
    crypto::{Key, SecretVec, blob, secretbox},
    http::{Api, ApiConfig, Auth, Http},
};
use mockito::{Matcher, Server};

fn sample_contact() -> ContactData {
    ContactData {
        contact_user_id: 42,
        name: "B Test".to_string(),
    }
}

fn open(
    base_url: String,
    master_key: Vec<u8>,
    cached_wrapped_root_contact_key: Option<WrappedRootContactKey>,
) -> ente_contacts::Result<Client> {
    let api = Api::new(
        Http::new()?,
        ApiConfig {
            origin: base_url,
            client_package: Some("io.ente.photos".to_string()),
            client_version: Some("1.0.0".to_string()),
            user_agent: Some("ente-contacts-test".to_string()),
            auth: Some(Auth::User("auth-token".to_string())),
        },
    );
    Ok(Client {
        session: Session {
            api,
            master_key: SecretVec::new(master_key),
        },
        wrapped_root_contact_key: RwLock::new(cached_wrapped_root_contact_key),
    })
}

struct Client {
    session: Session,
    wrapped_root_contact_key: RwLock<Option<WrappedRootContactKey>>,
}

impl Client {
    fn cached_root_key(&self) -> Option<WrappedRootContactKey> {
        self.wrapped_root_contact_key.read().unwrap().clone()
    }

    fn value<T>(&self, output: ContactOutput<T>) -> T {
        if let Some(key) = output.wrapped_root_contact_key {
            *self.wrapped_root_contact_key.write().unwrap() = Some(key);
        }
        output.value
    }

    async fn create_contact(&self, data: &ContactData) -> ente_contacts::Result<ContactRecord> {
        let cached = self.cached_root_key();
        Ok(self.value(ente_contacts::create_contact(&self.session, cached.as_ref(), data).await?))
    }

    async fn get_contact(&self, contact_id: &str) -> ente_contacts::Result<ContactRecord> {
        let cached = self.cached_root_key();
        Ok(self
            .value(ente_contacts::get_contact(&self.session, cached.as_ref(), contact_id).await?))
    }

    async fn get_diff(
        &self,
        since_time: i64,
        limit: u16,
    ) -> ente_contacts::Result<Vec<ContactRecord>> {
        let cached = self.cached_root_key();
        Ok(self.value(
            ente_contacts::get_diff(&self.session, cached.as_ref(), since_time, limit).await?,
        ))
    }

    async fn set_profile_picture(
        &self,
        contact_id: &str,
        bytes: &[u8],
    ) -> ente_contacts::Result<ContactRecord> {
        let cached = self.cached_root_key();
        Ok(self.value(
            ente_contacts::set_profile_picture(&self.session, cached.as_ref(), contact_id, bytes)
                .await?,
        ))
    }

    async fn get_profile_picture(&self, contact_id: &str) -> ente_contacts::Result<Vec<u8>> {
        let cached = self.cached_root_key();
        Ok(self.value(
            ente_contacts::get_profile_picture(&self.session, cached.as_ref(), contact_id).await?,
        ))
    }

    async fn delete_profile_picture(
        &self,
        contact_id: &str,
    ) -> ente_contacts::Result<ContactRecord> {
        let cached = self.cached_root_key();
        Ok(self.value(
            ente_contacts::delete_profile_picture(&self.session, cached.as_ref(), contact_id)
                .await?,
        ))
    }

    async fn get_attachment_encrypted(
        &self,
        attachment_type: AttachmentType,
        attachment_id: &str,
    ) -> ente_contacts::Result<Vec<u8>> {
        ente_contacts::get_attachment_encrypted(&self.session, attachment_type, attachment_id).await
    }
}

fn wrap_root(root_key: &[u8], master_key: &[u8]) -> WrappedRootContactKey {
    let encrypted = secretbox::encrypt(root_key, &Key::try_from_slice(master_key).unwrap());
    WrappedRootContactKey {
        encrypted_key: b64::encode(&encrypted.encrypted_data),
        header: b64::encode(encrypted.nonce.as_bytes()),
    }
}

fn live_entity_json(
    id: &str,
    data: &ContactData,
    email: Option<&str>,
    root_key: &[u8],
    profile_picture_attachment_id: Option<&str>,
) -> serde_json::Value {
    let contact_key = Key::generate().as_bytes().to_vec();
    let encrypted_key = b64::encode(&secretbox::encrypt_combined(
        &contact_key,
        &Key::try_from_slice(root_key).unwrap(),
    ));
    let encrypted_data = b64::encode(
        &blob::encrypt_json_combined(data, &Key::try_from_slice(&contact_key).unwrap()).unwrap(),
    );

    serde_json::json!({
        "id": id,
        "contactUserID": data.contact_user_id,
        "email": email,
        "profilePictureAttachmentID": profile_picture_attachment_id,
        "encryptedKey": encrypted_key,
        "encryptedData": encrypted_data,
        "isDeleted": false,
        "createdAt": 100,
        "updatedAt": 200
    })
}

#[tokio::test]
async fn get_contact_fetches_root_key_when_unresolved_context_reads_live_contact() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let server_root_key = Key::generate().as_bytes().to_vec();
    let server_wrapped_root = wrap_root(&server_root_key, &master_key);
    let contact = sample_contact();

    let root_fetch_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": server_wrapped_root.encrypted_key,
                "header": server_wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let get_contact_mock = server
        .mock("GET", "/contacts/ct_contact1")
        .with_status(200)
        .with_body(
            live_entity_json(
                "ct_contact1",
                &contact,
                Some("b@test.test"),
                &server_root_key,
                None,
            )
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let client = open(server.url(), master_key, None).unwrap();
    let fetched = client.get_contact("ct_contact1").await.unwrap();

    root_fetch_mock.assert_async().await;
    get_contact_mock.assert_async().await;
    assert_eq!(client.cached_root_key(), Some(server_wrapped_root));
    assert_eq!(fetched.name.as_deref(), Some(contact.name.as_str()));
}

#[tokio::test]
async fn create_contact_uses_cached_wrapped_root_contact_key_without_fetching_remote_key() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);
    let contact = sample_contact();
    let resolved_email = "b@test.test";

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .expect(0)
        .create_async()
        .await;

    let create_mock = server
        .mock("POST", "/contacts")
        .match_header("x-auth-token", "auth-token")
        .match_body(Matcher::PartialJson(serde_json::json!({
            "contactUserID": contact.contact_user_id
        })))
        .with_status(200)
        .with_body(
            live_entity_json(
                "ct_contact1",
                &contact,
                Some(resolved_email),
                &root_key,
                None,
            )
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, Some(wrapped_root)).unwrap();

    let created = ctx.create_contact(&contact).await.unwrap();

    root_mock.assert_async().await;
    create_mock.assert_async().await;
    assert_eq!(created.id, "ct_contact1");
    assert_eq!(created.contact_user_id, contact.contact_user_id);
    assert_eq!(created.email.as_deref(), Some(resolved_email));
}

#[tokio::test]
async fn set_profile_picture_uses_signed_upload_url_and_commit() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);
    let contact = sample_contact();
    let picture_bytes = b"profile-picture-bytes".to_vec();
    let resolved_email = "b@test.test";

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .create_async()
        .await;

    let current_entity = live_entity_json(
        "ct_picture1",
        &contact,
        Some(resolved_email),
        &root_key,
        None,
    );

    let get_contact_for_upload = server
        .mock("GET", "/contacts/ct_picture1")
        .with_status(200)
        .with_body(current_entity.to_string())
        .expect(1)
        .create_async()
        .await;

    let upload_url = format!("{}/upload/ua_picture1", server.url());
    let upload_url_mock = server
        .mock("POST", "/attachments/profile_picture/upload-url")
        .with_status(200)
        .with_body(
            serde_json::json!({
                "attachmentID": "ua_picture1",
                "url": upload_url
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let upload_bytes_mock = server
        .mock("PUT", "/upload/ua_picture1")
        .match_header("x-auth-token", Matcher::Missing)
        .match_header("x-client-package", Matcher::Missing)
        .match_header("x-client-version", Matcher::Missing)
        .match_header("user-agent", Matcher::Missing)
        .match_header(
            "content-md5",
            Matcher::Regex(r"^[A-Za-z0-9+/]+={0,2}$".to_string()),
        )
        .with_status(200)
        .expect(1)
        .create_async()
        .await;

    let attached_entity = live_entity_json(
        "ct_picture1",
        &contact,
        Some(resolved_email),
        &root_key,
        Some("ua_picture1"),
    );
    let commit_mock = server
        .mock("PUT", "/contacts/ct_picture1/attachments/profile_picture")
        .with_status(200)
        .with_body(attached_entity.to_string())
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, None).unwrap();

    let updated = ctx
        .set_profile_picture("ct_picture1", &picture_bytes)
        .await
        .unwrap();

    root_mock.assert_async().await;
    get_contact_for_upload.assert_async().await;
    upload_url_mock.assert_async().await;
    upload_bytes_mock.assert_async().await;
    commit_mock.assert_async().await;

    assert_eq!(
        updated.profile_picture_attachment_id.as_deref(),
        Some("ua_picture1")
    );
}

#[tokio::test]
async fn get_profile_picture_uses_signed_download_url() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);
    let contact = sample_contact();
    let picture_bytes = b"profile-picture-bytes".to_vec();

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .create_async()
        .await;

    let attached_entity = live_entity_json(
        "ct_picture1",
        &contact,
        Some("b@test.test"),
        &root_key,
        Some("ua_picture1"),
    );
    let contact_key = secretbox::decrypt_combined(
        &b64::decode(attached_entity["encryptedKey"].as_str().unwrap()).unwrap(),
        &Key::try_from_slice(&root_key).unwrap(),
    )
    .unwrap();
    let encrypted_picture =
        blob::encrypt_combined(&picture_bytes, &Key::try_from_slice(&contact_key).unwrap())
            .unwrap();

    let get_contact_mock = server
        .mock("GET", "/contacts/ct_picture1")
        .with_status(200)
        .with_body(attached_entity.to_string())
        .expect(1)
        .create_async()
        .await;

    let signed_download_url = format!("{}/download/ua_picture1", server.url());
    let signed_url_mock = server
        .mock("GET", "/attachments/profile_picture/ua_picture1")
        .with_status(200)
        .with_body(
            serde_json::json!({
                "url": signed_download_url
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let download_mock = server
        .mock("GET", "/download/ua_picture1")
        .match_header("x-auth-token", Matcher::Missing)
        .match_header("x-client-package", Matcher::Missing)
        .match_header("x-client-version", Matcher::Missing)
        .match_header("user-agent", Matcher::Missing)
        .with_status(200)
        .with_body(encrypted_picture.clone())
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, None).unwrap();

    let downloaded = ctx.get_profile_picture("ct_picture1").await.unwrap();

    root_mock.assert_async().await;
    get_contact_mock.assert_async().await;
    signed_url_mock.assert_async().await;
    download_mock.assert_async().await;
    assert_eq!(downloaded, picture_bytes);
}

#[tokio::test]
async fn delete_profile_picture_fetches_root_key_when_unresolved_context_decodes_live_response() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);
    let contact = sample_contact();

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let deleted_attachment_entity = live_entity_json(
        "ct_picture1",
        &contact,
        Some("b@test.test"),
        &root_key,
        None,
    );

    let delete_mock = server
        .mock(
            "DELETE",
            "/contacts/ct_picture1/attachments/profile_picture",
        )
        .with_status(200)
        .with_body(deleted_attachment_entity.to_string())
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, None).unwrap();

    let updated = ctx.delete_profile_picture("ct_picture1").await.unwrap();

    root_mock.assert_async().await;
    delete_mock.assert_async().await;
    assert_eq!(updated.id, "ct_picture1");
    assert_eq!(updated.profile_picture_attachment_id, None);
}

#[tokio::test]
async fn get_attachment_uses_generic_signed_download_url() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);
    let payload = b"generic-attachment-bytes".to_vec();

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .expect(0)
        .create_async()
        .await;

    let signed_download_url = format!("{}/download/ua_generic1", server.url());
    let signed_url_mock = server
        .mock("GET", "/attachments/profile_picture/ua_generic1")
        .with_status(200)
        .with_body(
            serde_json::json!({
                "url": signed_download_url
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let download_mock = server
        .mock("GET", "/download/ua_generic1")
        .match_header("x-auth-token", Matcher::Missing)
        .match_header("x-client-package", Matcher::Missing)
        .match_header("x-client-version", Matcher::Missing)
        .match_header("user-agent", Matcher::Missing)
        .with_status(200)
        .with_body(payload.clone())
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, None).unwrap();

    let downloaded = ctx
        .get_attachment_encrypted(AttachmentType::ProfilePicture, "ua_generic1")
        .await
        .unwrap();

    root_mock.assert_async().await;
    signed_url_mock.assert_async().await;
    download_mock.assert_async().await;
    assert_eq!(downloaded, payload);
}

#[tokio::test]
async fn deleted_contacts_surface_as_tombstones() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let root_key = Key::generate().as_bytes().to_vec();
    let wrapped_root = wrap_root(&root_key, &master_key);

    let root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "userID": 7,
                "type": "contact",
                "encryptedKey": wrapped_root.encrypted_key,
                "header": wrapped_root.header,
                "createdAt": 1
            })
            .to_string(),
        )
        .expect(0)
        .create_async()
        .await;

    let diff_mock = server
        .mock("GET", "/contacts/diff")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("sinceTime".into(), "0".into()),
            Matcher::UrlEncoded("limit".into(), "10".into()),
        ]))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "diff": [{
                    "id": "ct_deleted1",
                    "contactUserID": 42,
                    "profilePictureAttachmentID": null,
                    "encryptedKey": null,
                    "encryptedData": null,
                    "isDeleted": true,
                    "createdAt": 100,
                    "updatedAt": 200
                }]
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, None).unwrap();
    let diff = ctx.get_diff(0, 10).await.unwrap();

    root_mock.assert_async().await;
    diff_mock.assert_async().await;
    assert_eq!(diff.len(), 1);
    assert!(diff[0].is_deleted);
    assert_eq!(diff[0].id, "ct_deleted1");
    assert_eq!(diff[0].contact_user_id, 42);
    assert_eq!(diff[0].email, None);
}

#[tokio::test]
async fn get_diff_uses_cached_wrapped_root_contact_key_for_reads_without_fetching_remote_key() {
    let mut server = Server::new_async().await;
    let master_key = Key::generate().as_bytes().to_vec();
    let cached_wrapped_root_contact_key = Key::generate().as_bytes().to_vec();
    let cached_wrapped_root = wrap_root(&cached_wrapped_root_contact_key, &master_key);
    let contact = sample_contact();

    let no_fetch_root_mock = server
        .mock("GET", "/user-entity/key")
        .match_query(Matcher::UrlEncoded("type".into(), "contact".into()))
        .with_status(500)
        .expect(0)
        .create_async()
        .await;

    let diff_mock = server
        .mock("GET", "/contacts/diff")
        .match_query(Matcher::AllOf(vec![
            Matcher::UrlEncoded("sinceTime".into(), "0".into()),
            Matcher::UrlEncoded("limit".into(), "10".into()),
        ]))
        .with_status(200)
        .with_body(
            serde_json::json!({
                "diff": [live_entity_json(
                    "ct_contact1",
                    &contact,
                    Some("b@test.test"),
                    &cached_wrapped_root_contact_key,
                    None,
                )]
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;

    let ctx = open(server.url(), master_key, Some(cached_wrapped_root)).unwrap();

    let diff = ctx.get_diff(0, 10).await.unwrap();

    no_fetch_root_mock.assert_async().await;
    diff_mock.assert_async().await;
    assert_eq!(diff.len(), 1);
    assert_eq!(diff[0].name.as_deref(), Some(contact.name.as_str()));
}
