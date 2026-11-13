package api

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/cache"
	"github.com/ente/museum/internal/testutil"
	museumcontroller "github.com/ente/museum/pkg/controller"
	familycontroller "github.com/ente/museum/pkg/controller/family"
	"github.com/ente/museum/pkg/controller/usercache"
	"github.com/ente/museum/pkg/repo"
	storagebonusrepo "github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/gin-gonic/gin"
)

func TestInviteMemberAllowsResendWhenFamilyIsFull(t *testing.T) {
	router, adminID, pendingEmail, overflowEmail := setupFullFamilyTest(t)

	if got := performInviteMemberRequest(t, router, adminID, overflowEmail).Code; got != http.StatusPreconditionFailed {
		t.Fatalf("new invite status = %d, want %d", got, http.StatusPreconditionFailed)
	}
	if got := performInviteMemberRequest(t, router, adminID, pendingEmail).Code; got != http.StatusOK {
		t.Fatalf("resend status = %d, want %d", got, http.StatusOK)
	}
	if got := performInviteMemberRequest(t, router, adminID, "not-on-ente@ente.com").Code; got != http.StatusPreconditionFailed {
		t.Fatalf("unregistered invite status = %d, want %d", got, http.StatusPreconditionFailed)
	}
}

func TestFetchFamilyMembersReturnsUserIDOnlyForJoinedMembers(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	familyRepo := &repo.FamilyRepository{DB: db}
	adminEmail := "family-admin@ente.com"
	memberEmail := "family-member@ente.com"
	adminID := int64(1)
	memberID := int64(2)
	insertFreeFamilyTestUser(t, db, adminID, adminEmail)
	insertFreeFamilyTestUser(t, db, memberID, memberEmail)

	if err := familyRepo.CreateFamily(context.Background(), adminID); err != nil {
		t.Fatalf("create family: %v", err)
	}
	if _, err := familyRepo.AddMemberInvite(context.Background(), adminID, memberID, "initial-token", nil); err != nil {
		t.Fatalf("add family invite: %v", err)
	}

	handler := &FamilyHandler{Controller: &familycontroller.Controller{
		UserRepo:   userRepo,
		FamilyRepo: familyRepo,
		UserCacheCtrl: &usercache.Controller{
			StoreBonusRepo: &storagebonusrepo.Repository{DB: db},
			UserCache:      cache.NewUserCache(),
		},
	}}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/family/members", handler.FetchMembers)

	members := fetchFamilyMemberUserIDs(t, router, adminID)
	requireFamilyMemberUserID(t, members, adminEmail, &adminID)
	requireFamilyMemberUserID(t, members, memberEmail, nil)

	if err := familyRepo.AcceptInvite(context.Background(), adminID, memberID, "initial-token"); err != nil {
		t.Fatalf("accept family invite: %v", err)
	}
	members = fetchFamilyMemberUserIDs(t, router, adminID)
	requireFamilyMemberUserID(t, members, memberEmail, &memberID)

	if err := familyRepo.RemoveMember(context.Background(), adminID, memberID, ente.LEFT); err != nil {
		t.Fatalf("leave family: %v", err)
	}
	if _, err := familyRepo.AddMemberInvite(context.Background(), adminID, memberID, "reinvite-token", nil); err != nil {
		t.Fatalf("re-invite family member: %v", err)
	}
	members = fetchFamilyMemberUserIDs(t, router, adminID)
	requireFamilyMemberUserID(t, members, memberEmail, nil)
}

func setupFullFamilyTest(t *testing.T) (http.Handler, int64, string, string) {
	t.Helper()
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}
	familyRepo := &repo.FamilyRepository{DB: db}
	billingController := &museumcontroller.BillingController{
		BillingRepo:      &repo.BillingRepository{DB: db},
		UserRepo:         userRepo,
		StorageBonusRepo: &storagebonusrepo.Repository{DB: db},
	}

	adminID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "family-admin@ente.com",
		CreationTime: 1,
	})
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:     adminID,
		Storage:    100 * 1024 * 1024 * 1024,
		ExpiryTime: 4102444800000000,
		ProductID:  "family-test-paid",
	})
	if err := familyRepo.CreateFamily(context.Background(), adminID); err != nil {
		t.Fatalf("create family: %v", err)
	}

	var pendingEmail string
	for i := 1; i < 6; i++ {
		email := fmt.Sprintf("family-member-%d@ente.com", i)
		memberID := int64(i + 1)
		insertFreeFamilyTestUser(t, db, memberID, email)
		if _, err := familyRepo.AddMemberInvite(context.Background(), adminID, memberID, fmt.Sprintf("token-%d", i), nil); err != nil {
			t.Fatalf("add family invite: %v", err)
		}
		if i == 1 {
			pendingEmail = email
		}
	}

	overflowEmail := "family-overflow@ente.com"
	insertFreeFamilyTestUser(t, db, 7, overflowEmail)

	handler := &FamilyHandler{Controller: &familycontroller.Controller{
		BillingCtrl: billingController,
		UserLookup:  museumcontroller.NewUserLookupController(userRepo, nil),
		UserRepo:    userRepo,
		FamilyRepo:  familyRepo,
	}}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/family/add-member", handler.InviteMember)
	return router, adminID, pendingEmail, overflowEmail
}

func insertFreeFamilyTestUser(t *testing.T, db *sql.DB, userID int64, email string) {
	t.Helper()
	testutil.InsertUser(t, db, testutil.UserFixture{UserID: userID, Email: email, CreationTime: 1})
	testutil.InsertSubscription(t, db, testutil.SubscriptionFixture{
		UserID:     userID,
		Storage:    ente.FreePlanStorage,
		ExpiryTime: 4102444800000000,
		ProductID:  ente.FreePlanProductID,
	})
}

func fetchFamilyMemberUserIDs(t *testing.T, router http.Handler, userID int64) map[string]json.RawMessage {
	t.Helper()

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/family/members", nil)
	request.Header.Set("X-Auth-User-ID", strconv.FormatInt(userID, 10))
	router.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("fetch family members status = %d, body = %s", recorder.Code, recorder.Body.String())
	}

	var response struct {
		Members []struct {
			Email  string          `json:"email"`
			UserID json.RawMessage `json:"userID"`
		} `json:"members"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode family members: %v", err)
	}

	result := make(map[string]json.RawMessage, len(response.Members))
	for _, member := range response.Members {
		result[member.Email] = member.UserID
	}
	return result
}

func requireFamilyMemberUserID(t *testing.T, members map[string]json.RawMessage, email string, want *int64) {
	t.Helper()

	rawUserID, ok := members[email]
	if !ok {
		t.Fatalf("family member %q not found", email)
	}
	if len(rawUserID) == 0 {
		t.Fatalf("family member %q response omitted userID", email)
	}
	if want == nil {
		if string(rawUserID) != "null" {
			t.Fatalf("family member %q userID = %s, want null", email, rawUserID)
		}
		return
	}

	var got int64
	if err := json.Unmarshal(rawUserID, &got); err != nil {
		t.Fatalf("decode family member %q userID: %v", email, err)
	}
	if got != *want {
		t.Fatalf("family member %q userID = %d, want %d", email, got, *want)
	}
}

func performInviteMemberRequest(t *testing.T, router http.Handler, adminID int64, email string) *httptest.ResponseRecorder {
	t.Helper()

	body, err := json.Marshal(ente.InviteMemberRequest{Email: email})
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/family/add-member", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Auth-User-ID", strconv.FormatInt(adminID, 10))

	router.ServeHTTP(recorder, request)
	return recorder
}
