package storagebonus

// Unittest cases for storagebonus code repository

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

// TestGetReferralCode tests the GetCode method
func TestGetReferralCode(t *testing.T) {
	ctx := t.Context()
	repo := newStorageBonusTestRepository(t)
	// Test for a user that doesn't have a storagebonus code
	userID := int64(1)
	code, err := repo.GetCode(ctx, userID)
	assert.Nil(t, code)
	assert.ErrorIs(t, err, sql.ErrNoRows)

	// Insert a storagebonus code
	newCode := "AABBCC"
	err = repo.InsertCode(ctx, userID, newCode)
	assert.Nil(t, err)

	// Test for when storagebonus code already exists
	err = repo.InsertCode(ctx, userID, newCode)
	assert.Error(t, err)
	err = errors.Unwrap(err)
	// verify that error is of type pq.Error
	assert.Equal(t, entity.CodeAlreadyExistsErr, err)

	// Test for a user that has a storagebonus code
	code, err = repo.GetCode(ctx, userID)
	assert.Nil(t, err)
	assert.NotNil(t, code)
	assert.Equal(t, newCode, *code)
}

// TestInsertReferralCode tests the InsertCode method
func TestInsertReferralCode(t *testing.T) {
	ctx := t.Context()
	repo := newStorageBonusTestRepository(t)
	// Insert a referral code
	userID := int64(2)
	code := "AAEEDD"
	err := repo.InsertCode(ctx, userID, code)
	assert.Nil(t, err)

	codeNew, err := repo.GetCode(ctx, userID)
	assert.Nil(t, err)
	assert.Equal(t, code, *codeNew)
}

// TestAddNewReferralCode tests the AddNewCode method
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
