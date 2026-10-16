package discountcoupon

import (
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo/discountcoupon"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

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
