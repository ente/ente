use ente_core::{b64, crypto::hash::hmac_sha256, http::Api};

use crate::{Error, Result, models::TwoFactorType};

pub(crate) fn enforce_auth_payloads(api: &Api) -> bool {
    matches!(
        api.origin_host().as_deref(),
        Some("api.ente.com" | "api.ente.in" | "localhost")
    )
}

pub(crate) fn validate_auth_token(api: &Api, token: &[u8]) -> Result<()> {
    if enforce_auth_payloads(api)
        && (token.len() != b"auth-token".len() + 32 || !token.starts_with(b"auth-token"))
    {
        return Err(Error::Protocol("Invalid login token".into()));
    }
    Ok(())
}

pub(crate) fn deletion_challenge<'a>(api: &Api, plaintext: &'a str) -> Result<&'a str> {
    match plaintext.strip_prefix("delete-jwt") {
        Some(challenge) if !challenge.is_empty() => Ok(challenge),
        None if !enforce_auth_payloads(api) => Ok(plaintext),
        _ => Err(Error::Protocol("Invalid deletion challenge".into())),
    }
}

pub(crate) fn recovery_proof(
    secret: &str,
    factor: TwoFactorType,
    session_id: &str,
) -> Result<String> {
    let factor = match factor {
        TwoFactorType::Totp => "totp",
        TwoFactorType::Passkey => "passkey",
    };
    Ok(b64::encode(&hmac_sha256(
        secret.as_bytes(),
        format!("recovery:{factor}:{session_id}").as_bytes(),
    )?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::make_client;

    #[test]
    fn enforcement_uses_the_configured_hostname() {
        for (origin, expected) in [
            ("https://api.ente.com", true),
            ("https://api.ente.in:443/prefix", true),
            ("http://localhost:8080", true),
            ("https://API.ENTE.COM", true),
            ("https://self-hosted.example", false),
            ("http://127.0.0.1:8080", false),
            ("http://[::1]:8080", false),
            ("https://api.ente.com.example", false),
            ("https://api.ente.com@example.org", false),
            ("https://example.org/api.ente.com", false),
        ] {
            let client = make_client(origin.into());
            assert_eq!(enforce_auth_payloads(&client.api), expected, "{origin}");
            assert_eq!(
                deletion_challenge(&client.api, "delete-jwtjwt").unwrap(),
                "jwt"
            );
            assert_eq!(deletion_challenge(&client.api, "jwt").is_err(), expected);
        }
    }
}
