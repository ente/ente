use crate::{
    Result,
    models::account::{Account, AccountSecrets, App},
};
use rusqlite::{Connection, OptionalExtension, Row, params};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct AccountStore<'a> {
    conn: &'a Connection,
}

impl<'a> AccountStore<'a> {
    pub fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }

    pub fn add(&self, account: &Account) -> Result<()> {
        let now = current_timestamp();

        self.conn.execute(
            "INSERT INTO accounts (user_id, app, email, endpoint, export_dir, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                account.user_id,
                format!("{:?}", account.app).to_lowercase(),
                account.email,
                account.endpoint,
                account.export_dir,
                now,
                now
            ],
        )?;

        Ok(())
    }

    pub fn get(&self, email: &str, app: App) -> Result<Option<Account>> {
        let mut stmt = self.conn.prepare(
            "SELECT user_id, app, email, endpoint, export_dir FROM accounts 
             WHERE email = ?1 AND app = ?2",
        )?;

        let account = stmt
            .query_row(params![email, format!("{app:?}").to_lowercase()], |row| {
                row_to_account(row)
            })
            .optional()?;

        Ok(account)
    }

    pub fn list(&self) -> Result<Vec<Account>> {
        let mut stmt = self.conn.prepare(
            "SELECT user_id, app, email, endpoint, export_dir FROM accounts 
             ORDER BY email, app",
        )?;

        let accounts = stmt
            .query_map([], row_to_account)?
            .collect::<std::result::Result<Vec<_>, _>>()?;

        Ok(accounts)
    }

    pub fn update_export_dir(&self, email: &str, app: App, export_dir: &str) -> Result<()> {
        let now = current_timestamp();

        let rows_affected = self.conn.execute(
            "UPDATE accounts SET export_dir = ?1, updated_at = ?2 
             WHERE email = ?3 AND app = ?4",
            params![export_dir, now, email, format!("{app:?}").to_lowercase()],
        )?;

        if rows_affected == 0 {
            return Err(crate::Error::NotFound(format!(
                "Account not found: {} (app: {:?})",
                email, app
            )));
        }

        Ok(())
    }

    pub fn delete(&self, user_id: i64, app: App) -> Result<()> {
        let rows_affected = self.conn.execute(
            "DELETE FROM accounts WHERE user_id = ?1 AND app = ?2",
            params![user_id, format!("{app:?}").to_lowercase()],
        )?;

        if rows_affected == 0 {
            return Err(crate::Error::NotFound(format!(
                "Account not found: user_id={} (app: {:?})",
                user_id, app
            )));
        }

        Ok(())
    }

    pub fn store_secrets(&self, user_id: i64, app: App, secrets: &AccountSecrets) -> Result<()> {
        let now = current_timestamp();

        self.conn.execute(
            "INSERT OR REPLACE INTO secrets 
             (user_id, app, token, master_key, secret_key, public_key, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                user_id,
                format!("{app:?}").to_lowercase(),
                &secrets.token,
                &secrets.master_key,
                &secrets.secret_key,
                &secrets.public_key,
                now
            ],
        )?;

        Ok(())
    }

    pub fn get_secrets(&self, user_id: i64, app: App) -> Result<Option<AccountSecrets>> {
        let mut stmt = self.conn.prepare(
            "SELECT token, master_key, secret_key, public_key FROM secrets 
             WHERE user_id = ?1 AND app = ?2",
        )?;

        let secrets = stmt
            .query_row(params![user_id, format!("{app:?}").to_lowercase()], |row| {
                Ok(AccountSecrets {
                    token: row.get(0)?,
                    master_key: row.get(1)?,
                    secret_key: row.get(2)?,
                    public_key: row.get(3)?,
                })
            })
            .optional()?;

        Ok(secrets)
    }
}

fn row_to_account(row: &Row) -> rusqlite::Result<Account> {
    let app_str: String = row.get(1)?;
    let app = match app_str.as_str() {
        "photos" => App::Photos,
        "locker" => App::Locker,
        "auth" => App::Auth,
        _ => App::Photos,
    };

    Ok(Account {
        user_id: row.get(0)?,
        app,
        email: row.get(2)?,
        endpoint: row.get(3)?,
        export_dir: row.get(4)?,
    })
}

fn current_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}
