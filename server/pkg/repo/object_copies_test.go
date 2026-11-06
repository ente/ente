package repo

import (
	"database/sql"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestObjectCopiesReplicationQueue(t *testing.T) {
	for _, tc := range []struct {
		name        string
		b2          *int64
		wasabi      *int64
		scw         *int64
		wantB2      bool
		lastAttempt int64
		selected    bool
	}{
		{name: "missing only b2", wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, selected: true},
		{name: "missing wasabi", b2: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, selected: true},
		{name: "missing scaleway", b2: replicationTimestamp(), wasabi: replicationTimestamp(), wantB2: true, selected: true},
		{name: "complete", b2: replicationTimestamp(), wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true},
		{name: "unwanted b2", wasabi: replicationTimestamp(), scw: replicationTimestamp()},
		{name: "recent b2 attempt", wasabi: replicationTimestamp(), scw: replicationTimestamp(), wantB2: true, lastAttempt: time.Now().UnixMicro()},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := setupFileUsageTest(t)
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "replication-queue@example.com", CreationTime: 1})
			fileID := insertObjectTestFile(t, db, ownerID)
			insertObjectTestKey(t, db, fileID, ente.FILE, "replication-queue", 100, []string{"wasabi-eu-central-2-v3"})
			_, err := db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw, last_attempt)
				VALUES ('replication-queue', $1, $2, $3, $4, true, true, $5)`, tc.b2, tc.wasabi, tc.scw, tc.wantB2, tc.lastAttempt)
			require.NoError(t, err)
			repository := &ObjectCopiesRepository{DB: db}
			copies, err := repository.GetAndLockUnreplicatedObject(t.Context())
			if !tc.selected {
				require.ErrorIs(t, err, sql.ErrNoRows)
				return
			}
			require.NoError(t, err)
			require.Equal(t, &ente.ObjectCopies{ObjectKey: "replication-queue", B2: tc.b2, Wasabi: tc.wasabi, SCW: tc.scw,
				WantB2: tc.wantB2, WantWasabi: true, WantSCW: true}, copies)
			_, err = repository.GetAndLockUnreplicatedObject(t.Context())
			require.ErrorIs(t, err, sql.ErrNoRows)
		})
	}
}

func replicationTimestamp() *int64 {
	timestamp := int64(1)
	return &timestamp
}
