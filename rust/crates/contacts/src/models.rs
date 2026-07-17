use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AttachmentType {
    ProfilePicture,
}

impl AttachmentType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ProfilePicture => "profile_picture",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WrappedRootContactKey {
    pub encrypted_key: String,
    pub header: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContactData {
    pub contact_user_id: i64,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContactRecord {
    pub id: String,
    pub contact_user_id: i64,
    pub email: Option<String>,
    pub name: Option<String>,
    pub profile_picture_attachment_id: Option<String>,
    pub is_deleted: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

#[cfg(test)]
mod tests {
    use super::ContactData;

    #[test]
    fn contact_data_ignores_legacy_birth_date() {
        let data: ContactData =
            serde_json::from_str(r#"{"contactUserId":42,"name":"Alex","birthDate":"2001-04-02"}"#)
                .unwrap();

        assert_eq!(data.contact_user_id, 42);
        assert_eq!(data.name, "Alex");
        assert_eq!(
            serde_json::to_string(&data).unwrap(),
            r#"{"contactUserId":42,"name":"Alex"}"#,
        );
    }
}
