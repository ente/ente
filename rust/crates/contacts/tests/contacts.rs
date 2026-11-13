#![cfg(test)]
#![cfg(feature = "museum")]

mod support;

use ente_contacts::ContactData;
use ente_core::http;
use ente_test_support::{Museum, TestResult, account_fixture};

const CLIENT_PACKAGE: &str = "io.ente.photos";

#[test]
fn contacts() -> TestResult {
    Museum::run_async(run)
}

async fn run(endpoint: String) -> TestResult {
    let endpoint = &endpoint;
    let owner = account_fixture::create_account(endpoint, "contacts-owner").await?;
    let trusted = account_fixture::create_account(endpoint, "contacts-trusted").await?;
    let owner_session = support::open_session(endpoint, &owner);
    let trusted_session = support::open_session(endpoint, &trusted);

    // An emergency-contact invitation satisfies Museum's contact eligibility rule.
    ente_legacy::add_contact(&owner_session, &trusted.email, Some(14)).await?;

    let initial_data = ContactData {
        contact_user_id: trusted.user_id,
        name: "Trusted Contact".to_string(),
    };

    let created = ente_contacts::create_contact(&owner_session, None, &initial_data).await?;
    let wrapped_root_key = created.wrapped_root_contact_key;
    let contact = created.value;
    assert_eq!(contact.contact_user_id, trusted.user_id);
    assert_eq!(contact.email.as_deref(), Some(trusted.email.as_str()));

    let fetched =
        ente_contacts::get_contact(&owner_session, wrapped_root_key.as_ref(), &contact.id)
            .await?
            .value;
    assert_eq!(fetched.id, contact.id);
    assert_eq!(fetched.name.as_deref(), Some("Trusted Contact"));

    let updated = ente_contacts::update_contact(
        &owner_session,
        wrapped_root_key.as_ref(),
        &contact.id,
        &ContactData {
            contact_user_id: trusted.user_id,
            name: "Trusted Contact Updated".to_string(),
        },
    )
    .await?
    .value;
    assert_eq!(updated.name.as_deref(), Some("Trusted Contact Updated"));

    let diff = ente_contacts::get_diff(&owner_session, wrapped_root_key.as_ref(), 0, 5000)
        .await?
        .value;
    assert!(diff.iter().any(|entry| entry.id == contact.id));

    assert!(matches!(
        ente_contacts::get_contact(&trusted_session, None, &contact.id).await,
        Err(ente_contacts::Error::Http(http::Error::Http {
            status: 404,
            ..
        }))
    ));

    ente_contacts::delete_contact(&owner_session, &contact.id).await?;
    Ok(())
}
