package remotestore

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	remotestorerepo "github.com/ente/museum/pkg/repo/remotestore"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestReservedCustomDomainCanonicalization(t *testing.T) {
	if !isReservedCustomDomain("ｍｙ．ｅｎｔｅ．ｃｏｍ", "") {
		t.Error("width-mapped Ente domain was not reserved")
	}
}

func TestPreviewUploadV2Rollout(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	for _, user := range []testutil.UserFixture{
		{UserID: 1, Email: "preview-rollout-in@ente.com", CreationTime: 1},
		{UserID: 2, Email: "preview-rollout-out@ente.com", CreationTime: 1},
	} {
		testutil.InsertUser(t, db, user)
	}
	repository := &remotestorerepo.Repository{DB: db}
	controller := &Controller{Repo: repository}
	flagsFor := func(userID int64) int64 {
		ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
		ctx.Request = httptest.NewRequest(http.MethodGet, "/", nil)
		ctx.Request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
		response, err := controller.GetFeatureFlags(ctx)
		require.NoError(t, err)
		return response.ServerApiFlag
	}

	require.NotZero(t, flagsFor(1)&ente.PreviewUploadV2)
	require.Zero(t, flagsFor(2)&ente.PreviewUploadV2)
	require.NoError(t, repository.InsertOrUpdate(context.Background(), 2, string(ente.IsInternalUser), "true"))
	require.NotZero(t, flagsFor(2)&ente.PreviewUploadV2)
}
