package storagebonus

import (
	"database/sql"
	"errors"
	"testing"

	entity "github.com/ente/museum/ente/storagebonus"
	"github.com/ente/museum/internal/testutil"
	_ "github.com/golang-migrate/migrate/v4/source/file"

	"github.com/stretchr/testify/assert"
)

func newStorageBonusTestRepository(t *testing.T) *Repository {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	return NewRepository(db)
}

func TestGetReferralCode(t *testing.T) {
	ctx := t.Context()
	repo := newStorageBonusTestRepository(t)
	userID := int64(1)
	code, err := repo.GetCode(ctx, userID)
	assert.Nil(t, code)
	assert.ErrorIs(t, err, sql.ErrNoRows)

	newCode := "AABBCC"
	err = repo.InsertCode(ctx, userID, newCode)
	assert.Nil(t, err)

	err = repo.InsertCode(ctx, userID, newCode)
	assert.Error(t, err)
	err = errors.Unwrap(err)
	assert.Equal(t, entity.CodeAlreadyExistsErr, err)

	code, err = repo.GetCode(ctx, userID)
	assert.Nil(t, err)
	assert.NotNil(t, code)
	assert.Equal(t, newCode, *code)
}

func TestAddNewReferralCode(t *testing.T) {
	ctx := t.Context()
	repo := newStorageBonusTestRepository(t)
	userID := int64(3)
	code := "B22222"
	err := repo.InsertCode(ctx, userID, code)
	assert.Nil(t, err)

	newCode := "C22222"
	err = repo.AddNewCode(ctx, userID, newCode, false)
	assert.Nil(t, err)

	referralCode, err := repo.GetCode(ctx, userID)
	assert.Nil(t, err)
	assert.Equal(t, newCode, *referralCode)

}
