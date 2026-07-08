package emergency

import (
	"database/sql"
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	emergencyRepo "github.com/ente/museum/pkg/repo/emergency"
	timeUtil "github.com/ente/museum/pkg/utils/time"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func TestApproveRecoveryRejectsSpoofedSessionPartiesBeforeUpdate(t *testing.T) {
	ctx, db, ctrl := setupEmergencyRecoveryControllerTest(t)

	ownerID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-owner@ente.com",
		CreationTime: 1,
	})
	contactID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       2,
		Email:        "trusted-contact@ente.com",
		CreationTime: 1,
	})
	sessionID := mustInsertEmergencyRecoverySession(t, db, ownerID, contactID, ente.RecoveryStatusWaiting)

	err := ctrl.ApproveRecovery(ctx, contactID, ente.RecoveryIdentifier{
		ID:                 sessionID,
		UserID:             contactID,
		EmergencyContactID: ownerID,
	})
	if !errors.Is(err, ente.ErrPermissionDenied) {
		t.Fatalf("ApproveRecovery() error = %v, want permission denied", err)
	}

	status := mustGetEmergencyRecoveryStatus(t, db, sessionID)
	if status != ente.RecoveryStatusWaiting {
		t.Fatalf("recovery status = %s, want %s", status, ente.RecoveryStatusWaiting)
	}
}

func setupEmergencyRecoveryControllerTest(t *testing.T) (*gin.Context, *sql.DB, *Controller) {
	t.Helper()

	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	gin.SetMode(gin.TestMode)
	ctx, _ := gin.CreateTestContext(httptest.NewRecorder())
	ctx.Request = httptest.NewRequest("POST", "/", nil)

	ctrl := &Controller{
		Repo: &emergencyRepo.Repository{DB: db},
	}
	return ctx, db, ctrl
}

func mustInsertEmergencyRecoverySession(
	t *testing.T,
	db *sql.DB,
	userID int64,
	emergencyContactID int64,
	status ente.RecoveryStatus,
) uuid.UUID {
	t.Helper()

	sessionID := uuid.New()
	_, err := db.Exec(
		`INSERT INTO emergency_recovery(id, user_id, emergency_contact_id, status, wait_till, next_reminder_at)
		 VALUES($1, $2, $3, $4, $5, $6)`,
		sessionID,
		userID,
		emergencyContactID,
		status,
		timeUtil.MicrosecondsAfterHours(48),
		timeUtil.MicrosecondsAfterHours(24),
	)
	if err != nil {
		t.Fatalf("failed to insert emergency recovery session: %v", err)
	}
	return sessionID
}

func mustGetEmergencyRecoveryStatus(t *testing.T, db *sql.DB, sessionID uuid.UUID) ente.RecoveryStatus {
	t.Helper()

	var status ente.RecoveryStatus
	err := db.QueryRow(`SELECT status FROM emergency_recovery WHERE id = $1`, sessionID).Scan(&status)
	if err != nil {
		t.Fatalf("failed to fetch emergency recovery status: %v", err)
	}
	return status
}
