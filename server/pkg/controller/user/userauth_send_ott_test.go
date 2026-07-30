package user

import (
	"database/sql"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	discordCtrl "github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	util "github.com/ente/museum/pkg/utils"
	"github.com/ente/museum/pkg/utils/crypto"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
)

func TestShouldSwallowSendOTTDisclosureErrorAfterLimiter(t *testing.T) {
	controller := &UserController{
		OTTLimiter: util.NewRateLimiter("1-H"),
	}

	if controller.shouldSwallowSendOTTDisclosureError(newSendOTTTestContext()) {
		t.Fatal("first disclosure error should not be swallowed")
	}
	if !controller.shouldSwallowSendOTTDisclosureError(newSendOTTTestContext()) {
		t.Fatal("second disclosure error should be swallowed")
	}
}

func TestValidateSendOTTSwallowsDisclosureErrorsAfterLimiter(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userRepo := &repo.UserRepository{
		DB:                  db,
		SecretEncryptionKey: testutil.SecretEncryptionKey(),
		HashingKey:          testutil.HashingKey(),
	}

	tests := []struct {
		name    string
		email   string
		purpose string
		setup   func(t *testing.T)
		wantErr error
	}{
		{
			name:    "signup existing complete account",
			email:   "complete-signup@example.com",
			purpose: ente.SignUpOTTPurpose,
			setup: func(t *testing.T) {
				insertCompleteSendOTTTestUser(t, db, userRepo, 101, "complete-signup@example.com")
			},
			wantErr: ente.ErrUserAlreadyRegistered,
		},
		{
			name:    "login missing account",
			email:   "missing-login@example.com",
			purpose: ente.LoginOTTPurpose,
			wantErr: ente.ErrUserNotRegistered,
		},
		{
			name:    "login incomplete account",
			email:   "incomplete-login@example.com",
			purpose: ente.LoginOTTPurpose,
			setup: func(t *testing.T) {
				testutil.InsertUser(t, db, testutil.UserFixture{
					UserID:       102,
					Email:        "incomplete-login@example.com",
					CreationTime: 1,
				})
			},
			wantErr: ente.ErrUserSignupIncomplete,
		},
		{
			name:    "change email existing account",
			email:   "existing-change-target@example.com",
			purpose: ente.ChangeEmailOTTPurpose,
			setup: func(t *testing.T) {
				testutil.InsertUser(t, db, testutil.UserFixture{
					UserID:       103,
					Email:        "existing-change-target@example.com",
					CreationTime: 1,
				})
			},
			wantErr: ente.ErrPermissionDenied,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testutil.ResetTables(t, db)
			controller := &UserController{
				UserRepo:   userRepo,
				OTTLimiter: util.NewRateLimiter("1-H"),
			}
			if tt.setup != nil {
				tt.setup(t)
			}

			shouldSend, err := controller.validateSendOTT(newSendOTTTestContext(), tt.email, tt.purpose)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("first validateSendOTT error = %v, want %v", err, tt.wantErr)
			}
			if shouldSend {
				t.Fatal("first validateSendOTT should not allow sending for disclosure error")
			}

			shouldSend, err = controller.validateSendOTT(newSendOTTTestContext(), tt.email, tt.purpose)
			if err != nil {
				t.Fatalf("second validateSendOTT should swallow disclosure error, got %v", err)
			}
			if shouldSend {
				t.Fatal("second validateSendOTT should swallow disclosure error without sending")
			}
		})
	}
}

func TestValidateSendOTTAllowsUnusedChangeEmailWithoutLimiter(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
	}

	shouldSend, err := controller.validateSendOTT(newSendOTTTestContext(), "unused-change-target@example.com", ente.ChangeEmailOTTPurpose)
	if err != nil {
		t.Fatalf("unused change email should be allowed, got %v", err)
	}
	if !shouldSend {
		t.Fatal("unused change email should allow sending")
	}
}

func TestSendEmailOTTDoesNotStoreOTTWhenDisclosureErrorSwallowed(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const email = "missing-send-ott@example.com"
	limiter := NewOTTSendLimiter()
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		UserAuthRepo:   userAuthRepo,
		HashingKey:     testutil.HashingKey(),
		OTTLimiter:     util.NewRateLimiter("1-H"),
		OTTSendLimiter: limiter,
		HardCodedOTT: HardCodedOTT{
			Emails: []HardCodedOTTEmail{
				{
					Email: email,
					Value: "123456",
				},
			},
		},
	}

	err := controller.SendEmailOTT(newSendOTTTestContext(), email, ente.LoginOTTPurpose, false)
	if !errors.Is(err, ente.ErrUserNotRegistered) {
		t.Fatalf("first SendEmailOTT error = %v, want %v", err, ente.ErrUserNotRegistered)
	}

	err = controller.SendEmailOTT(newSendOTTTestContext(), email, ente.LoginOTTPurpose, false)
	if err != nil {
		t.Fatalf("second SendEmailOTT should swallow disclosure error, got %v", err)
	}

	emailHash, err := crypto.GetHash(email, testutil.HashingKey())
	if err != nil {
		t.Fatalf("failed to hash email: %v", err)
	}
	otts, err := userAuthRepo.GetValidOTTs(emailHash, ente.Photos)
	if err != nil {
		t.Fatalf("failed to get valid otts: %v", err)
	}
	if len(otts) != 0 {
		t.Fatalf("swallowed disclosure error should not store ott, got %v", otts)
	}

	if got := len(limiter.attempts); got != 0 {
		t.Fatalf("disclosure-swallowed requests should not affect limiter attempts, got %d", got)
	}
	if got := len(limiter.ipNextAllowed); got != 0 {
		t.Fatalf("disclosure-swallowed requests should not affect IP cooldowns, got %d", got)
	}
}

func TestSendEmailOTTBlockedBySendLimiterDoesNotStoreOTT(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	now := timeUtil.Microseconds()
	limiter := newOTTSendLimiter(func() time.Time {
		return time.UnixMicro(now)
	})
	const ip = "198.51.100.10"
	for i := 0; i < ottSendElevatedThreshold-1; i++ {
		decision := limiter.Allow(fmt.Sprintf("203.0.113.%d", i))
		if !decision.allowed || decision.alert == ottSendSevereAlert {
			t.Fatalf("seed request %d decision=%+v, want allowed without severe activation", i, decision)
		}
	}
	decision := limiter.Allow(ip)
	if !decision.allowed || decision.alert != ottSendElevatedAlert {
		t.Fatalf("first elevated request decision=%+v, want allowed with elevated activation", decision)
	}

	const email = "limited-send-ott@example.com"
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		UserAuthRepo:   userAuthRepo,
		HashingKey:     testutil.HashingKey(),
		OTTSendLimiter: limiter,
		HardCodedOTT: HardCodedOTT{
			Emails: []HardCodedOTTEmail{
				{
					Email: email,
					Value: "123456",
				},
			},
		},
	}

	err := controller.SendEmailOTT(newSendOTTTestContextWithIP(ip), email, ente.SignUpOTTPurpose, false)
	if !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("SendEmailOTT error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}

	emailHash, err := crypto.GetHash(email, testutil.HashingKey())
	if err != nil {
		t.Fatalf("failed to hash email: %v", err)
	}
	otts, err := userAuthRepo.GetValidOTTs(emailHash, ente.Photos)
	if err != nil {
		t.Fatalf("failed to get valid otts: %v", err)
	}
	if len(otts) != 0 {
		t.Fatalf("blocked send should not store ott, got %v", otts)
	}
}

func TestSendEmailOTTActiveCapDoesNotTouchSendLimiter(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	const email = "active-cap-send-ott@example.com"
	emailHash, err := crypto.GetHash(email, testutil.HashingKey())
	if err != nil {
		t.Fatalf("failed to hash email: %v", err)
	}
	userAuthRepo := &repo.UserAuthRepository{DB: db}
	for i := 0; i < OTTActiveCodeLimit; i++ {
		err := userAuthRepo.AddOTT(
			emailHash,
			ente.Photos,
			fmt.Sprintf("%06d", i),
			timeUtil.Microseconds()+OTTValidityDurationInMicroSeconds,
		)
		if err != nil {
			t.Fatalf("failed to seed active OTT %d: %v", i, err)
		}
	}

	limiter := NewOTTSendLimiter()
	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		UserAuthRepo:      userAuthRepo,
		HashingKey:        testutil.HashingKey(),
		DiscordController: newSendOTTTestDiscordController(),
		OTTSendLimiter:    limiter,
	}

	err = controller.SendEmailOTT(newSendOTTTestContext(), email, ente.SignUpOTTPurpose, false)
	if !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("SendEmailOTT error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}
	if got := len(limiter.attempts); got != 0 {
		t.Fatalf("active-code-cap failure should not affect limiter attempts, got %d", got)
	}
	if got := len(limiter.ipNextAllowed); got != 0 {
		t.Fatalf("active-code-cap failure should not affect IP cooldowns, got %d", got)
	}
}

func TestSendEmailOTTReturnsValidOTTLookupError(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	closedDB, err := sql.Open("postgres", "sslmode=disable")
	if err != nil {
		t.Fatalf("failed to open closed test DB handle: %v", err)
	}
	if err := closedDB.Close(); err != nil {
		t.Fatalf("failed to close test DB handle: %v", err)
	}

	limiter := NewOTTSendLimiter()
	controller := &UserController{
		UserRepo: &repo.UserRepository{
			DB:                  db,
			SecretEncryptionKey: testutil.SecretEncryptionKey(),
			HashingKey:          testutil.HashingKey(),
		},
		UserAuthRepo:   &repo.UserAuthRepository{DB: closedDB},
		HashingKey:     testutil.HashingKey(),
		OTTSendLimiter: limiter,
	}

	err = controller.SendEmailOTT(newSendOTTTestContext(), "lookup-error-send-ott@example.com", ente.SignUpOTTPurpose, false)
	if err == nil || !strings.Contains(err.Error(), "database is closed") {
		t.Fatalf("SendEmailOTT error = %v, want database is closed", err)
	}
	if got := len(limiter.attempts); got != 0 {
		t.Fatalf("GetValidOTTs failure should not affect limiter attempts, got %d", got)
	}
}

func TestSendEmailOTTGlobalBlockShortCircuits(t *testing.T) {
	now := time.Unix(1000, 0)
	limiter := newOTTSendLimiter(func() time.Time { return now })
	limiter.blockedUntil = now.Add(time.Minute)
	controller := &UserController{
		OTTSendLimiter: limiter,
	}

	err := controller.SendEmailOTT(newSendOTTTestContext(), "global-block@example.com", ente.SignUpOTTPurpose, false)
	if !errors.Is(err, ente.ErrTooManyBadRequest) {
		t.Fatalf("SendEmailOTT error = %v, want %v", err, ente.ErrTooManyBadRequest)
	}
}

func newSendOTTTestContext() *gin.Context {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodPost, "/users/ott", nil)
	return ctx
}

func newSendOTTTestContextWithIP(ip string) *gin.Context {
	ctx := newSendOTTTestContext()
	ctx.Request.RemoteAddr = net.JoinHostPort(ip, "1234")
	return ctx
}

func newSendOTTTestDiscordController() *discordCtrl.DiscordController {
	return discordCtrl.NewDiscordController(nil, "test", "test")
}

func insertCompleteSendOTTTestUser(t *testing.T, db *sql.DB, userRepo *repo.UserRepository, userID int64, email string) {
	t.Helper()
	insertedUserID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       userID,
		Email:        email,
		CreationTime: 1,
	})
	if err := userRepo.SetKeyAttributes(insertedUserID, sendOTTTestKeyAttributes()); err != nil {
		t.Fatalf("failed to set key attributes: %v", err)
	}
}

func sendOTTTestKeyAttributes() ente.KeyAttributes {
	return ente.KeyAttributes{
		KEKSalt:                  "kek-salt",
		KEKHash:                  "kek-hash",
		EncryptedKey:             "encrypted-key",
		KeyDecryptionNonce:       "key-decryption-nonce",
		PublicKey:                "public-key",
		EncryptedSecretKey:       "encrypted-secret-key",
		SecretKeyDecryptionNonce: "secret-key-decryption-nonce",
		MemLimit:                 128 * 1024 * 1024,
		OpsLimit:                 32,
	}
}
