use flutter_rust_bridge::frb;

#[frb(non_opaque)]
pub struct ActiveSession {
    pub id: String,
    pub is_current: bool,
    pub created_at: i64,
    pub last_used_at: i64,
    pub ip: String,
    pub user_agent: String,
    pub pretty_user_agent: String,
}

impl From<ente_accounts::sessions::ActiveSession> for ActiveSession {
    fn from(value: ente_accounts::sessions::ActiveSession) -> Self {
        Self {
            id: value.id,
            is_current: value.is_current,
            created_at: value.created_at,
            last_used_at: value.last_used_at,
            ip: value.ip,
            user_agent: value.user_agent,
            pretty_user_agent: value.pretty_user_agent,
        }
    }
}
