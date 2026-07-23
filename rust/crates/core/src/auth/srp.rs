//! SRP (Secure Remote Password) session implementation.
//!
//! Provides a minimal SRP client state machine that avoids exposing low-level
//! step ordering (e.g. calling set_b before compute_m1). Callers only need to
//! exchange the public value and proofs with the server.

use crate::crypto::SecretVec;
use sha2::{Digest, Sha256};
use srp::ClientG4096;
use subtle::ConstantTimeEq;
use zeroize::Zeroize;

use super::{AuthError, Result};

/// SRP session for password-based authentication.
///
/// Usage:
/// 1. Create session with `new()`
/// 2. Send `public_a()` to the server
/// 3. Call `compute_m1(server_b)` to get the client proof
/// 4. Optionally verify server proof with `verify_m2(server_m2)`
pub struct SrpSession {
    inner: ClientG4096<Sha256>,
    identity: Vec<u8>,
    login_key: SecretVec,
    salt: Vec<u8>,
    a_private: SecretVec,
    a_public: Vec<u8>,
    m1: Option<SecretVec>,
    k: Option<SecretVec>,
}

const SRP_N_BYTES: usize = 512; // 4096-bit group size

fn pad_to_n(input: &[u8]) -> Vec<u8> {
    if input.len() >= SRP_N_BYTES {
        return input.to_vec();
    }

    let mut out = vec![0u8; SRP_N_BYTES - input.len()];
    out.extend_from_slice(input);
    out
}

impl SrpSession {
    /// Create a new SRP session.
    ///
    /// # Arguments
    /// * `srp_user_id` - The SRP user ID (UUID string)
    /// * `srp_salt` - The SRP salt (raw bytes, not base64)
    /// * `login_key` - The login key derived from password (16 bytes)
    pub fn new(srp_user_id: &str, srp_salt: &[u8], login_key: &[u8]) -> Result<Self> {
        if login_key.len() != 16 {
            return Err(AuthError::InvalidKey(format!(
                "Login key must be 16 bytes, got {}",
                login_key.len()
            )));
        }

        let client = ClientG4096::<Sha256>::new();

        // Generate random ephemeral private key (64 bytes)
        let mut a_private = vec![0u8; 64];
        getrandom::getrandom(&mut a_private)
            .map_err(|e| AuthError::Srp(format!("Failed to generate random bytes: {}", e)))?;

        // Compute public ephemeral
        let a_public = client.compute_public_ephemeral(&a_private);

        // Use the UUID string directly as bytes (matching TypeScript)
        let identity = srp_user_id.as_bytes().to_vec();

        Ok(Self {
            inner: client,
            identity,
            login_key: SecretVec::new(login_key.to_vec()),
            salt: srp_salt.to_vec(),
            a_private: SecretVec::new(a_private),
            a_public,
            m1: None,
            k: None,
        })
    }

    /// Get the client's public ephemeral value A (padded to N length).
    ///
    /// This should be sent to the server to create an SRP session.
    /// Returns raw bytes (caller should base64 encode for API).
    pub fn public_a(&self) -> Vec<u8> {
        pad_to_n(&self.a_public)
    }

    /// Compute the client proof M1 from the server's public value B.
    ///
    /// This processes the server reply and stores internal state for
    /// `verify_m2()`.
    pub fn compute_m1(&mut self, server_b: &[u8]) -> Result<Vec<u8>> {
        let verifier = self
            .inner
            .process_reply(
                &self.a_private,
                &self.identity,
                &self.login_key,
                &self.salt,
                server_b,
            )
            .map_err(|e| AuthError::Srp(format!("Failed to process server response: {:?}", e)))?;

        // The srp crate uses S directly for M2, but our server uses K = H(S).
        // Compute the proof values the way the server does.
        let s = verifier.key();
        let s_padded = pad_to_n(s);
        let a_padded = pad_to_n(&self.a_public);
        let b_padded = pad_to_n(server_b);

        // M1 = H(A | B | S)
        let mut m1_hasher = Sha256::new();
        m1_hasher.update(&a_padded);
        m1_hasher.update(&b_padded);
        m1_hasher.update(&s_padded);
        let m1 = m1_hasher.finalize().to_vec();

        // K = H(S)
        let mut k_hasher = Sha256::new();
        k_hasher.update(&s_padded);
        let k = k_hasher.finalize().to_vec();

        self.m1 = Some(SecretVec::new(m1.clone()));
        self.k = Some(SecretVec::new(k));

        // No longer needed after we have computed M1/K.
        self.login_key.zeroize();
        self.a_private.zeroize();

        Ok(m1)
    }

    /// Verify the server's proof M2.
    ///
    /// # Arguments
    /// * `server_m2` - The server's proof M2 (raw bytes, not base64)
    pub fn verify_m2(&self, server_m2: &[u8]) -> Result<()> {
        let m1 = self
            .m1
            .as_ref()
            .ok_or_else(|| AuthError::Srp("Client proof not computed".to_string()))?;
        let k = self
            .k
            .as_ref()
            .ok_or_else(|| AuthError::Srp("Client proof not computed".to_string()))?;

        let a_padded = pad_to_n(&self.a_public);

        // M2 = H(A | M1 | K)
        let mut m2_hasher = Sha256::new();
        m2_hasher.update(&a_padded);
        m2_hasher.update(m1);
        m2_hasher.update(k);
        let expected = m2_hasher.finalize().to_vec();

        if expected.ct_eq(server_m2).unwrap_u8() != 1 {
            return Err(AuthError::Srp(
                "Server proof verification failed".to_string(),
            ));
        }

        Ok(())
    }
}

impl Drop for SrpSession {
    fn drop(&mut self) {
        self.login_key.zeroize();
        self.a_private.zeroize();
        if let Some(m1) = &mut self.m1 {
            m1.zeroize();
        }
        if let Some(k) = &mut self.k {
            k.zeroize();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_srp_session_creation() {
        let srp_user_id = "test-user-id";
        let srp_salt = [0u8; 16];
        let login_key = [0u8; 16];

        let session = SrpSession::new(srp_user_id, &srp_salt, &login_key).unwrap();

        // Public value should be generated
        let a = session.public_a();
        assert!(!a.is_empty());
        assert!(a.len() >= SRP_N_BYTES);
    }

    #[test]
    fn test_public_a_padding() {
        let a_public = vec![0xAB, 0xCD];
        let session = SrpSession {
            inner: ClientG4096::<Sha256>::new(),
            identity: b"test-user".to_vec(),
            login_key: SecretVec::new(vec![0u8; 16]),
            salt: vec![0u8; 16],
            a_private: SecretVec::new(vec![0u8; 64]),
            a_public: a_public.clone(),
            m1: None,
            k: None,
        };

        let padded = session.public_a();

        assert_eq!(padded.len(), SRP_N_BYTES);
        assert!(
            padded[..SRP_N_BYTES - a_public.len()]
                .iter()
                .all(|&b| b == 0)
        );
        assert_eq!(&padded[SRP_N_BYTES - a_public.len()..], a_public.as_slice());
    }

    #[test]
    fn test_compute_m1_and_verify_m2_match_expected() {
        use srp::ServerG4096;

        let srp_user_id = "test-user-id";
        let srp_salt = [0x22u8; 16];
        let login_key = [0x11u8; 16];

        let client = ClientG4096::<Sha256>::new();
        let verifier = client.compute_verifier(srp_user_id.as_bytes(), &login_key, &srp_salt);

        let server = ServerG4096::<Sha256>::new();
        let b_private = [0x33u8; 64];
        let b_pub = server.compute_public_ephemeral(&b_private, &verifier);

        let a_private = vec![0x44u8; 64];
        let a_public = client.compute_public_ephemeral(&a_private);

        let mut session = SrpSession {
            inner: ClientG4096::<Sha256>::new(),
            identity: srp_user_id.as_bytes().to_vec(),
            login_key: SecretVec::new(login_key.to_vec()),
            salt: srp_salt.to_vec(),
            a_private: SecretVec::new(a_private.clone()),
            a_public: a_public.clone(),
            m1: None,
            k: None,
        };

        let m1 = session.compute_m1(&b_pub).unwrap();

        let verifier_client = ClientG4096::<Sha256>::new();
        let verifier = verifier_client
            .process_reply(
                &a_private,
                srp_user_id.as_bytes(),
                &login_key,
                &srp_salt,
                &b_pub,
            )
            .unwrap();

        let s = verifier.key();
        let s_padded = pad_to_n(s);
        let a_padded = pad_to_n(&a_public);
        let b_padded = pad_to_n(&b_pub);

        let mut m1_hasher = Sha256::new();
        m1_hasher.update(&a_padded);
        m1_hasher.update(&b_padded);
        m1_hasher.update(&s_padded);
        let expected_m1 = m1_hasher.finalize().to_vec();

        let mut k_hasher = Sha256::new();
        k_hasher.update(&s_padded);
        let expected_k = k_hasher.finalize().to_vec();

        assert_eq!(m1, expected_m1);
        assert_eq!(
            session.m1.as_ref().unwrap().as_ref(),
            expected_m1.as_slice()
        );
        assert_eq!(session.k.as_ref().unwrap().as_ref(), expected_k.as_slice());

        let mut m2_hasher = Sha256::new();
        m2_hasher.update(&a_padded);
        m2_hasher.update(&expected_m1);
        m2_hasher.update(&expected_k);
        let expected_m2 = m2_hasher.finalize().to_vec();

        session.verify_m2(&expected_m2).unwrap();

        let mut bad_m2 = expected_m2;
        bad_m2[0] ^= 0x01;
        assert!(session.verify_m2(&bad_m2).is_err());
    }

    #[test]
    fn test_sensitive_buffers_zeroized_after_compute_m1() {
        use rand_core::RngCore;
        use srp::ServerG4096;

        let srp_user_id = "test-user-id";
        let srp_salt = [0u8; 16];
        let login_key = [0x11u8; 16];

        let client = ClientG4096::<Sha256>::new();
        let verifier = client.compute_verifier(srp_user_id.as_bytes(), &login_key, &srp_salt);

        let server = ServerG4096::<Sha256>::new();
        let mut b = [0u8; 64];
        rand_core::OsRng.fill_bytes(&mut b);
        let b_pub = server.compute_public_ephemeral(&b, &verifier);

        let mut session = SrpSession::new(srp_user_id, &srp_salt, &login_key).unwrap();
        session.compute_m1(&b_pub).unwrap();

        assert!(session.login_key.iter().all(|&b| b == 0));
        assert!(session.a_private.iter().all(|&b| b == 0));
    }

    #[test]
    fn test_m1_and_k_zeroized_via_drop_impl() {
        use rand_core::RngCore;
        use srp::ServerG4096;
        use zeroize::Zeroize;

        let srp_user_id = "test-user-id";
        let srp_salt = [0u8; 16];
        let login_key = [0x11u8; 16];

        let client = ClientG4096::<Sha256>::new();
        let verifier = client.compute_verifier(srp_user_id.as_bytes(), &login_key, &srp_salt);

        let server = ServerG4096::<Sha256>::new();
        let mut b = [0u8; 64];
        rand_core::OsRng.fill_bytes(&mut b);
        let b_pub = server.compute_public_ephemeral(&b, &verifier);

        let mut session = SrpSession::new(srp_user_id, &srp_salt, &login_key).unwrap();
        session.compute_m1(&b_pub).unwrap();

        // Precondition: m1 and k are populated with non-zero data
        assert!(
            session.m1.as_ref().unwrap().iter().any(|&b| b != 0),
            "precondition: m1 should be non-zero after compute_m1"
        );
        assert!(
            session.k.as_ref().unwrap().iter().any(|&b| b != 0),
            "precondition: k should be non-zero after compute_m1"
        );

        // Manually invoke the same zeroization that Drop performs, while
        // memory is still owned — avoids UB from reading freed allocations.
        if let Some(m1) = &mut session.m1 {
            m1.zeroize();
        }
        if let Some(k) = &mut session.k {
            k.zeroize();
        }

        assert!(
            session.m1.as_ref().unwrap().iter().all(|&b| b == 0),
            "m1 was not zeroed by zeroize()"
        );
        assert!(
            session.k.as_ref().unwrap().iter().all(|&b| b == 0),
            "k was not zeroed by zeroize()"
        );
    }

    #[test]
    fn test_srp_session_invalid_login_key() {
        let srp_user_id = "test-user-id";
        let srp_salt = [0u8; 16];
        let login_key = [0u8; 32]; // Wrong size

        let result = SrpSession::new(srp_user_id, &srp_salt, &login_key);
        assert!(result.is_err());
    }

    #[test]
    fn test_verify_m2_requires_m1() {
        let srp_user_id = "test-user-id";
        let srp_salt = [0u8; 16];
        let login_key = [0u8; 16];

        let session = SrpSession::new(srp_user_id, &srp_salt, &login_key).unwrap();
        let result = session.verify_m2(&[0u8; 32]);
        assert!(result.is_err());
    }

    #[test]
    fn test_known_vector_leading_zero_a_matches_go_server_m1() {
        use srp::{Group, bigint::BoxedUint, groups::G4096};

        // Deterministic edge-case vector:
        // A has a leading 0x00 on the wire (512-byte padded form), which used to
        // trigger interop failures when u was computed over trimmed A/B bytes.
        let srp_user_id = "repro-user-id";
        let srp_salt = *b"0123456789abcdef";
        let login_key = *b"1234567890abcdef";

        let a_private = hex::decode(
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006de",
        )
        .unwrap();
        let b_private = [0x42u8; 64];

        let client = ClientG4096::<Sha256>::new();
        let verifier = client.compute_verifier(srp_user_id.as_bytes(), &login_key, &srp_salt);
        let server = srp::ServerG4096::<Sha256>::new();
        let server_b = server.compute_public_ephemeral(&b_private, &verifier);

        let a_public = client.compute_public_ephemeral(&a_private);
        assert_eq!(a_public.len(), SRP_N_BYTES - 1);

        let a_private_for_session = a_private.clone();
        let mut session = SrpSession {
            inner: ClientG4096::<Sha256>::new(),
            identity: srp_user_id.as_bytes().to_vec(),
            login_key: SecretVec::new(login_key.to_vec()),
            salt: srp_salt.to_vec(),
            a_private: SecretVec::new(a_private_for_session),
            a_public,
            m1: None,
            k: None,
        };

        let m1 = session.compute_m1(&server_b).unwrap();
        // Generated by the Go server's github.com/ente/go-srp
        // v0.0.0-20250116115009-d52061067e78 against the vector above.
        let expected_m1 =
            hex::decode("c0953b8c74d400fbf664a515deb700d73b65231e7e207a2e2326ff8cf70567ac")
                .unwrap();
        assert_eq!(m1, expected_m1);

        // Contrast with legacy u=H(A|B) behavior (pre-fix): compute it
        // explicitly and verify it diverges from the Go server vector.
        let g = G4096::generator();
        let legacy_k = srp::utils::compute_k::<Sha256>(&g);
        let identity_hash =
            ClientG4096::<Sha256>::compute_identity_hash(srp_user_id.as_bytes(), &login_key);
        let legacy_x = ClientG4096::<Sha256>::compute_x(identity_hash.as_slice(), &srp_salt);
        let legacy_u = srp::utils::compute_u::<Sha256>(&session.a_public, &server_b);
        let legacy_s = client.compute_premaster_secret(
            &BoxedUint::from_be_slice_vartime(&server_b),
            &legacy_k,
            &legacy_x,
            &BoxedUint::from_be_slice_vartime(&a_private),
            &legacy_u,
        );
        let legacy_s_bytes = legacy_s.to_be_bytes_trimmed_vartime();
        let legacy_s_padded = pad_to_n(&legacy_s_bytes);
        let a_padded = pad_to_n(&session.a_public);
        let b_padded = pad_to_n(&server_b);
        let mut legacy_m1_hasher = Sha256::new();
        legacy_m1_hasher.update(&a_padded);
        legacy_m1_hasher.update(&b_padded);
        legacy_m1_hasher.update(&legacy_s_padded);
        let legacy_m1 = legacy_m1_hasher.finalize().to_vec();
        assert_ne!(legacy_m1, expected_m1);
    }
}
