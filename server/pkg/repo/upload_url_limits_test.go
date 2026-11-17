package repo

import (
	"testing"
	"time"

	"github.com/ente/museum/internal/testutil"
	"github.com/stretchr/testify/require"
)

func TestCountPendingUploadURLs(t *testing.T) {
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	r := &UploadURLRepository{DB: db}
	now := time.Now()
	_, err := db.Exec(`INSERT INTO temp_objects(object_key,bucket_id,expiration_time,user_id,created_at,cleanup_state)
 VALUES ('pending-a','b2-eu-cen',$1,10,$2,NULL),('pending-b','b2-eu-cen',$1,10,$2,NULL),
 ('other-user','b2-eu-cen',$1,20,$2,NULL),('old','b2-eu-cen',$1,10,$3,NULL),
 ('cleanup-only','b2-eu-cen',$1,10,$2,'retired'),('no-owner','b2-eu-cen',$1,NULL,$2,NULL),
 ('legacy-no-time','b2-eu-cen',$1,10,NULL,NULL)`, now.Add(time.Hour).UnixMicro(), now.UnixMicro(), now.Add(-2*time.Hour).UnixMicro())
	require.NoError(t, err)
	count, err := r.CountPending(t.Context(), 10, now.Add(-time.Hour), 1000)
	require.NoError(t, err)
	require.Equal(t, 2, count)
	count, err = r.CountPending(t.Context(), 20, now.Add(-time.Hour), 1000)
	require.NoError(t, err)
	require.Equal(t, 1, count)
	_, err = db.Exec(`INSERT INTO temp_objects(object_key,bucket_id,expiration_time,user_id,created_at)
 SELECT 'pending-'||n,'b2-eu-cen',$1,10,$2 FROM generate_series(1,1500) n`, now.Add(time.Hour).UnixMicro(), now.UnixMicro())
	require.NoError(t, err)
	count, err = r.CountPending(t.Context(), 10, now.Add(-time.Hour), 1000)
	require.NoError(t, err)
	require.Equal(t, 1000, count)
	_, err = db.Exec(`DELETE FROM temp_objects WHERE user_id=10 AND cleanup_state IS NULL AND created_at>$1`, now.Add(-time.Hour).UnixMicro())
	require.NoError(t, err)
	count, err = r.CountPending(t.Context(), 10, now.Add(-time.Hour), 1000)
	require.NoError(t, err)
	require.Zero(t, count)
}
