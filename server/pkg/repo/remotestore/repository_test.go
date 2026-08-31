package remotestore

import (
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestCustomDomainCanonicalUniqueness(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "owner@example.com", CreationTime: 1})
	otherID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 2, Email: "other@example.com", CreationTime: 1})
	collisionID1 := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 3, Email: "collision1@example.com", CreationTime: 1})
	collisionID2 := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 4, Email: "collision2@example.com", CreationTime: 1})
	invalidID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 5, Email: "invalid@example.com", CreationTime: 1})
	repository := &Repository{DB: db}

	require.NoError(t, repository.InsertOrUpdateCustomDomain(t.Context(), ownerID, "BÜCHER.example"))
	domain, err := repository.GetDomain(t.Context(), ownerID)
	require.NoError(t, err)
	require.Equal(t, "BÜCHER.example", *domain)
	resolvedOwnerID, err := repository.DomainOwner(t.Context(), "XN--BCHER-KVA.EXAMPLE")
	require.NoError(t, err)
	require.Equal(t, ownerID, *resolvedOwnerID)

	err = repository.InsertOrUpdateCustomDomain(t.Context(), otherID, "bu\u0308cher.example")
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.CONFLICT, apiErr.Code)

	pointer := ente.BuildFamilyCustomDomainPointer(ownerID, "family.example")
	require.NoError(t, repository.InsertOrUpdate(t.Context(), ownerID, string(ente.CustomDomain), pointer))
	require.NoError(t, repository.InsertOrUpdateCustomDomain(t.Context(), otherID, "BÜCHER.example"))
	_, err = db.ExecContext(t.Context(), `UPDATE remote_store SET canonical_value = 'released.example'
		WHERE user_id = $1 AND key_name = 'customDomain'`, ownerID)
	require.NoError(t, err)

	_, err = db.ExecContext(t.Context(), `UPDATE remote_store SET key_value = 'LEGACY.example'
		WHERE user_id = $1 AND key_name = 'customDomain'`, otherID)
	require.NoError(t, err)
	_, err = db.ExecContext(t.Context(), `INSERT INTO remote_store (user_id, key_name, key_value) VALUES
		($1, 'customDomain', 'BÜCHER.example'),
		($2, 'customDomain', 'xn--bcher-kva.example'),
		($3, 'customDomain', 'invalid')`, collisionID1, collisionID2, invalidID)
	require.NoError(t, err)
	require.NoError(t, repository.MigrateCustomDomainCanonicalValues(t.Context()))

	var value string
	var canonicalValue *string
	require.NoError(t, db.QueryRowContext(t.Context(), `SELECT key_value, canonical_value FROM remote_store
		WHERE user_id = $1 AND key_name = 'customDomain'`, otherID).Scan(&value, &canonicalValue))
	require.Equal(t, "LEGACY.example", value)
	require.Equal(t, "legacy.example", *canonicalValue)
	require.NoError(t, db.QueryRowContext(t.Context(), `SELECT canonical_value FROM remote_store
		WHERE user_id = $1 AND key_name = 'customDomain'`, ownerID).Scan(&canonicalValue))
	require.Nil(t, canonicalValue)
	var canonicalCount int
	require.NoError(t, db.QueryRowContext(t.Context(), `SELECT count(canonical_value) FROM remote_store
		WHERE user_id IN ($1, $2, $3)`, collisionID1, collisionID2, invalidID).Scan(&canonicalCount))
	require.Zero(t, canonicalCount)
}
