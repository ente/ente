package discountcoupon

import (
	"context"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/discountcoupon"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestLaunchClaimProcessSnapshotsRequestIDAndDetachesContext(t *testing.T) {
	gin.SetMode(gin.TestMode)
	ginContext, _ := gin.CreateTestContext(httptest.NewRecorder())
	ginContext.Writer.Header().Set("X-Request-ID", "request-id-before-reuse")

	req := ClaimCouponRequest{ProviderName: "Test", Email: "user@example.com"}
	processStarted := make(chan struct{})
	continueProcess := make(chan struct{})
	type processResult struct {
		ctx       context.Context
		requestID string
		request   ClaimCouponRequest
	}
	result := make(chan processResult, 1)
	launchClaimProcess(ginContext, req, func(ctx context.Context, requestID string, gotReq ClaimCouponRequest) {
		close(processStarted)
		<-continueProcess
		result <- processResult{ctx: ctx, requestID: requestID, request: gotReq}
	})
	<-processStarted
	ginContext.Writer.Header().Set("X-Request-ID", "request-id-after-reuse")
	close(continueProcess)

	got := <-result
	require.Equal(t, "request-id-before-reuse", got.requestID)
	require.Equal(t, req, got.request)
	require.Equal(t, context.Background(), got.ctx)
}

func TestAddCouponsStoresTrimmedCodes(t *testing.T) {
	db := testutil.RequireTestDB(t)
	deleteTestCoupons := func() {
		_, err := db.Exec(`DELETE FROM discount_coupons WHERE provider_name = 'Test'`)
		require.NoError(t, err)
	}
	deleteTestCoupons()
	t.Cleanup(deleteTestCoupons)

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	controller := &Controller{Repo: &discountcoupon.Repository{DB: db}}
	require.NoError(t, controller.AddCoupons(ctx, AddCouponsRequest{
		ProviderName: "Test",
		Codes:        []string{"AAA ", "BBB\r", "", "   ", "AAA"},
	}))

	rows, err := db.Query(`SELECT code FROM discount_coupons WHERE provider_name = 'Test' ORDER BY code`)
	require.NoError(t, err)
	defer rows.Close()
	var codes []string
	for rows.Next() {
		var code string
		require.NoError(t, rows.Scan(&code))
		codes = append(codes, code)
	}
	require.NoError(t, rows.Err())
	require.Equal(t, []string{"AAA", "BBB"}, codes)
}
