package controller

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"database/sql"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/awa/go-iap/playstore"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/commonbilling"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/stretchr/testify/require"
)

const playTestProduct = "test.android.subscription"
const playTestPredecessor = "test-predecessor"
const playTestSuccessor = "test-successor"
const playTestExpiry int64 = 2000000000000

// Exercise the real SDK, including its OAuth and acknowledgement requests, while
// refusing all requests outside this test's synthetic purchase.
type playTestTransport struct {
	t                      *testing.T
	linked, token          string
	expiry                 int64
	reject                 bool
	verified, acknowledged int
}

func (p *playTestTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	path := "/androidpublisher/v3/applications/" + PlayStorePackageName + "/purchases/subscriptions/" + playTestProduct + "/tokens/" + p.token
	status, body := http.StatusOK, ""
	switch {
	case req.URL.Scheme == "https" && req.URL.Host == "oauth.example.invalid" && req.URL.Path == "/token" && req.Method == http.MethodPost:
		body = `{"access_token":"synthetic-token","token_type":"Bearer","expires_in":3600}`
	case req.URL.Scheme == "https" && req.URL.Host == "androidpublisher.googleapis.com" && req.URL.Path == path && req.Method == http.MethodGet:
		p.verified++
		if p.reject {
			status, body = http.StatusBadRequest, `{"error":{"code":400,"message":"synthetic rejection"}}`
		} else {
			data, err := json.Marshal(map[string]any{"expiryTimeMillis": fmt.Sprint(p.expiry), "linkedPurchaseToken": p.linked})
			require.NoError(p.t, err)
			body = string(data)
		}
	case req.URL.Scheme == "https" && req.URL.Host == "androidpublisher.googleapis.com" && req.URL.Path == path+":acknowledge" && req.Method == http.MethodPost:
		p.acknowledged++
		body = `{}`
	default:
		p.t.Errorf("unexpected provider request: %s %s", req.Method, req.URL)
		return nil, fmt.Errorf("unexpected provider request blocked")
	}
	return &http.Response{StatusCode: status, Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
}

type playTestDenyTransport struct{ t *testing.T }

func (d playTestDenyTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	d.t.Errorf("unexpected outbound request: %s %s", req.Method, req.URL)
	return nil, fmt.Errorf("outbound request blocked")
}

func newPlayTestClient(t *testing.T, transport *playTestTransport) *playstore.Client {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	credentials, err := json.Marshal(map[string]string{
		"type": "service_account", "client_email": "test@example.invalid",
		"private_key": string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		"token_uri":   "https://oauth.example.invalid/token",
	})
	require.NoError(t, err)
	client, err := playstore.NewWithClient(credentials, &http.Client{Transport: transport, Timeout: time.Second})
	require.NoError(t, err)
	return client
}

func TestPlayStoreNotificationProvider(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	// These subtests intentionally run serially: the shared database and default
	// transports must not overlap with another test's fixtures.
	oldTransport, oldClient := http.DefaultTransport, http.DefaultClient
	http.DefaultTransport = playTestDenyTransport{t}
	http.DefaultClient = &http.Client{Transport: playTestDenyTransport{t}}
	t.Cleanup(func() { http.DefaultTransport, http.DefaultClient = oldTransport, oldClient })
	cases := []struct {
		name                              string
		oldStorage, newStorage, usage     int64
		provider                          ente.PaymentProvider
		ordinary, reject, unknown, direct bool
	}{
		{name: "linked_upgrade", oldStorage: 100, newStorage: 200},
		{name: "linked_downgrade", oldStorage: 200, newStorage: 100},
		{name: "linked_resubscription", oldStorage: 100, newStorage: 100},
		{name: "ordinary_renewal", oldStorage: 100, newStorage: 100, ordinary: true},
		{name: "verification_rejected", oldStorage: 100, newStorage: 200, reject: true},
		{name: "downgrade_rejected", oldStorage: 200, newStorage: 100, usage: 150},
		{name: "appstore_isolation", oldStorage: 100, newStorage: 200, provider: ente.AppStore},
		{name: "unknown_transaction", oldStorage: 100, newStorage: 200, unknown: true},
		{name: "direct_play_verification", newStorage: 200, direct: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			uid := testutil.InsertUser(t, db, testutil.UserFixture{Email: "play-test@example.invalid", CreationTime: 1})
			testutil.InsertUsage(t, db, uid, tc.usage)
			provider := tc.provider
			if provider == "" {
				provider = ente.PlayStore
			}
			if !tc.unknown && !tc.direct {
				testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{UserID: uid, Storage: tc.oldStorage, OriginalTransactionID: playTestPredecessor, ExpiryTime: playTestExpiry*1000 - 1000, ProductID: "test.android.old", PaymentProvider: provider})
			}
			transport := &playTestTransport{t: t, linked: playTestPredecessor, token: playTestSuccessor, expiry: playTestExpiry, reject: tc.reject}
			if tc.ordinary || tc.direct {
				transport.linked, transport.token = "", playTestPredecessor
			}
			users := &repo.UserRepository{DB: db}
			billing := &repo.BillingRepository{DB: db}
			bonus := storagebonus.NewRepository(db)
			c := &PlayStoreController{
				PlayStoreClient: newPlayTestClient(t, transport), BillingRepo: billing, UserRepo: users, StorageBonusRepo: bonus,
				BillingPlansPerCountry: ente.BillingPlansPerCountry{"EU": {{AndroidID: playTestProduct, Storage: tc.newStorage}}},
				CommonBillCtrl:         &commonbilling.Controller{UserRepo: users, UsageRepo: &repo.UsageRepository{DB: db}, BillingRepo: billing, StorageBonusRepo: bonus},
			}
			if tc.direct {
				s, err := c.GetVerifiedSubscription(uid, playTestProduct, transport.token)
				require.NoError(t, err)
				require.Equal(t, ente.PlayStore, s.PaymentProvider)
				require.Equal(t, transport.token, s.OriginalTransactionID)
				require.Equal(t, transport.expiry*1000, s.ExpiryTime)
				require.Equal(t, tc.newStorage, s.Storage)
				require.Equal(t, 1, transport.verified)
				require.Zero(t, transport.acknowledged)
				return
			}
			notification := playstore.DeveloperNotification{PackageName: PlayStorePackageName, SubscriptionNotification: playstore.SubscriptionNotification{NotificationType: playstore.SubscriptionNotificationTypeRenewed, PurchaseToken: transport.token, SubscriptionID: playTestProduct}}
			before := ""
			if !tc.unknown {
				before = playTestSnapshot(t, db, uid)
			}
			err := c.HandleNotification(notification)
			switch {
			case tc.reject:
				require.Error(t, err)
			case tc.usage > tc.newStorage:
				require.ErrorIs(t, err, ente.ErrCannotDowngrade)
			default:
				require.NoError(t, err)
			}
			if tc.reject || tc.usage > tc.newStorage || provider == ente.AppStore || tc.unknown {
				if tc.unknown {
					_, err := billing.GetUserSubscription(uid)
					require.ErrorIs(t, err, sql.ErrNoRows)
				} else {
					require.Equal(t, before, playTestSnapshot(t, db, uid))
				}
				require.Zero(t, playTestLogs(t, db, uid))
				require.Equal(t, 1, transport.verified)
				require.Zero(t, transport.acknowledged)
				return
			}
			first, err := billing.GetUserSubscription(uid)
			require.NoError(t, err)
			// Use nonfatal checks so the baseline also demonstrates the missed callback.
			if first.PaymentProvider != ente.PlayStore {
				t.Errorf("stored provider = %s; want playstore", first.PaymentProvider)
			}
			_, lookupErr := billing.GetSubscriptionForTransaction(playTestPredecessor, ente.PlayStore)
			if lookupErr != nil {
				t.Errorf("Play lookup failed: %v", lookupErr)
			}
			require.Equal(t, playTestPredecessor, first.OriginalTransactionID)
			require.Equal(t, tc.newStorage, first.Storage)
			if !tc.ordinary {
				require.Equal(t, playTestProduct, first.ProductID)
				require.Equal(t, playTestSuccessor, first.Attributes.LatestVerificationData)
			}
			require.Equal(t, playTestExpiry*1000, first.ExpiryTime)
			transport.expiry += 1000
			require.NoError(t, c.HandleNotification(notification))
			second, err := billing.GetUserSubscription(uid)
			require.NoError(t, err)
			if second.ExpiryTime != transport.expiry*1000 {
				t.Errorf("following expiry = %d; want %d", second.ExpiryTime, transport.expiry*1000)
			}
			if count := playTestLogs(t, db, uid); count != 2 {
				t.Errorf("callback logs = %d; want 2", count)
			}
			require.Equal(t, 2, transport.verified)
			expectedAcks := 2
			if tc.ordinary {
				expectedAcks = 0
			}
			require.Equal(t, expectedAcks, transport.acknowledged)
		})
	}
}

func playTestSnapshot(t *testing.T, db *sql.DB, uid int64) string {
	t.Helper()
	var snapshot string
	require.NoError(t, db.QueryRow("SELECT row_to_json(s)::text FROM subscriptions s WHERE user_id=$1", uid).Scan(&snapshot))
	return snapshot
}

func playTestLogs(t *testing.T, db *sql.DB, uid int64) int {
	t.Helper()
	var count int
	require.NoError(t, db.QueryRow("SELECT count(*) FROM subscription_logs WHERE user_id=$1", uid).Scan(&count))
	return count
}
