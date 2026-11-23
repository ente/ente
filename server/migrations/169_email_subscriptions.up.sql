CREATE TABLE email_subscriptions (
    user_id BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    email_type TEXT NOT NULL CHECK (email_type IN ('product_mails')),
    subscribed BOOLEAN NOT NULL,
    PRIMARY KEY (user_id, email_type)
);
