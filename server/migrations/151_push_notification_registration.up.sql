ALTER TABLE push_tokens
    ADD COLUMN platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android'));
