package repo

import (
	"context"
	"database/sql"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestSetSourceIfEmptyKeepsExistingSource(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})
	repo := &UserRepository{DB: db}
	ctx := context.Background()
	source := func(userID int64) sql.NullString {
		var value sql.NullString
		require.NoError(t, db.QueryRow(`SELECT source FROM users WHERE user_id = $1`, userID).Scan(&value))
		return value
	}

	unset := testutil.InsertUser(t, db, testutil.UserFixture{Email: "unset@example.com", CreationTime: 1})
	blank := testutil.InsertUser(t, db, testutil.UserFixture{Email: "blank@example.com", CreationTime: 1})
	_, err := db.Exec(`UPDATE users SET source = '' WHERE user_id = $1`, blank)
	require.NoError(t, err)

	require.NoError(t, repo.SetSourceIfEmpty(ctx, unset, "Friend or family"))
	require.NoError(t, repo.SetSourceIfEmpty(ctx, blank, "Social media"))
	require.Equal(t, "Friend or family", source(unset).String)
	require.Equal(t, "Social media", source(blank).String)

	require.NoError(t, repo.SetSourceIfEmpty(ctx, unset, "Other"))
	require.Equal(t, "Friend or family", source(unset).String)
}
