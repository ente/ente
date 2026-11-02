use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub struct AccountDeletionSummary {
    pub photos_and_videos_count: i64,
    pub authenticator_codes_count: i64,
    pub locker_records_count: i64,
}
