use std::io::Write;

use ente_core::{
    Session, b64,
    crypto::{Key, blob, hash, secretbox},
    io::Md5Writer,
};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::TestResult;

pub async fn create_album(session: &Session, name: &str) -> TestResult<(i64, Key)> {
    #[derive(Deserialize)]
    struct Created {
        collection: Id,
    }
    #[derive(Deserialize)]
    struct Id {
        id: i64,
    }
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), &session.master_key);
    let encrypted_name = secretbox::encrypt(name.as_bytes(), &key);
    let created: Created = session
        .api
        .post("/collections")
        .json(&json!({
            "encryptedKey": b64::encode(&wrapped.encrypted_data),
            "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
            "encryptedName": b64::encode(&encrypted_name.encrypted_data),
            "nameDecryptionNonce": b64::encode(encrypted_name.nonce.as_bytes()),
            "type": "album",
            "attributes": {"version": 1}
        }))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok((created.collection.id, key))
}

pub async fn upload_object(session: &Session, bytes: Vec<u8>) -> TestResult<String> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Upload {
        url: String,
        object_key: String,
    }
    let mut checksum_writer = Md5Writer::new(std::io::sink());
    checksum_writer.write_all(&bytes)?;
    let checksum = b64::encode(&checksum_writer.finalize().1);
    let upload: Upload = session
        .api
        .post("/files/upload-url")
        .json(&json!({"contentLength": bytes.len(), "contentMD5": checksum}))
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    session
        .api
        .http()
        .put(&upload.url)
        .header("content-md5", &checksum)
        .header("content-length", &bytes.len().to_string())
        .body(bytes)
        .send()
        .await?
        .error_for_status()?;
    Ok(upload.object_key)
}

pub async fn upload_file(
    session: &Session,
    collection_id: i64,
    collection_key: &Key,
    payload: &[u8],
    title: &str,
    public_metadata: Option<&Value>,
) -> TestResult<(i64, Key)> {
    let key = Key::generate();
    let wrapped = secretbox::encrypt(key.as_bytes(), collection_key);
    let file = blob::encrypt(payload, &key)?;
    let thumbnail = blob::encrypt(b"thumbnail", &key)?;
    let metadata = blob::encrypt_json(
        &json!({
            "title": title,
            "fileType": 0,
            "hash": b64::encode(&hash::hash(payload, None, None)?),
            "creationTime": 1_700_000_000_000_000_i64,
            "modificationTime": 1_700_000_000_000_000_i64
        }),
        &key,
    )?;
    let file_object = upload_object(session, file.encrypted_data).await?;
    let thumbnail_object = upload_object(session, thumbnail.encrypted_data).await?;
    let mut request = json!({
        "collectionID": collection_id,
        "encryptedKey": b64::encode(&wrapped.encrypted_data),
        "keyDecryptionNonce": b64::encode(wrapped.nonce.as_bytes()),
        "file": {
            "objectKey": file_object,
            "decryptionHeader": b64::encode(file.decryption_header.as_bytes())
        },
        "thumbnail": {
            "objectKey": thumbnail_object,
            "decryptionHeader": b64::encode(thumbnail.decryption_header.as_bytes())
        },
        "metadata": {
            "encryptedData": b64::encode(&metadata.encrypted_data),
            "decryptionHeader": b64::encode(metadata.decryption_header.as_bytes())
        }
    });
    if let Some(public) = public_metadata {
        let count = public.as_object().ok_or("Expected metadata object")?.len();
        if count > 0 {
            let encrypted = blob::encrypt_json(public, &key)?;
            request["pubMagicMetadata"] = json!({
                "version": 1,
                "count": count,
                "data": b64::encode(&encrypted.encrypted_data),
                "header": b64::encode(encrypted.decryption_header.as_bytes())
            });
        }
    }
    #[derive(Deserialize)]
    struct Uploaded {
        id: i64,
    }
    let uploaded: Uploaded = session
        .api
        .post("/files")
        .json(&request)
        .send()
        .await?
        .error_for_code()
        .await?
        .json()
        .await?;
    Ok((uploaded.id, key))
}
