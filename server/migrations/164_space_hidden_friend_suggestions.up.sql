CREATE TABLE space_hidden_friend_suggestions (
    viewer_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    suggested_space_id TEXT NOT NULL REFERENCES spaces (space_id) ON DELETE CASCADE,
    PRIMARY KEY (viewer_space_id, suggested_space_id),
    CHECK (viewer_space_id <> suggested_space_id)
);

CREATE INDEX space_hidden_friend_suggestions_suggested_idx
    ON space_hidden_friend_suggestions (suggested_space_id);
