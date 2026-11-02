package legacy_kit

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"testing"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/internal/testutil"
	userrepo "github.com/ente/museum/pkg/repo"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestRecoveryTokenExpiry(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "legacy-kit-owner@ente.io", CreationTime: 1})
	kitID := insertLegacyKitForTest(t, db, userID, false)
	sessionID := uuid.New()
	insertLegacyKitSessionForTest(t, db, sessionID, kitID, userID, ente.LegacyKitRecoveryStatusReady, 1)
	insertLegacyKitSessionTokenForTest(t, db, sessionID, "token")
	createdAt := timeutil.Microseconds()
	_, err := db.Exec(`UPDATE legacy_kit_recovery_session_token SET created_at = $1`, createdAt)
	require.NoError(t, err)
	repository := &Repository{DB: db}
	deadline := createdAt + 24*timeutil.MicroSecondsInOneHour
	for _, tc := range []struct {
		name    string
		now     int64
		expired bool
	}{
		{"before", deadline - 1, false},
		{"at", deadline, true},
		{"after", deadline + 1, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			session, err := repository.GetSessionByIDAndTokenForUse(t.Context(), sessionID, "token", tc.now)
			if tc.expired {
				var apiErr *ente.ApiError
				require.ErrorAs(t, err, &apiErr)
				require.Equal(t, ente.SessionExpired, apiErr.Code)
				require.Equal(t, http.StatusGone, apiErr.HttpStatusCode)
				require.Nil(t, session)
			} else {
				require.NoError(t, err)
				require.Equal(t, sessionID, session.ID)
			}
		})
	}
	for _, tc := range []struct {
		id    uuid.UUID
		token string
	}{{sessionID, "wrong"}, {uuid.New(), "token"}} {
		session, err := repository.GetSessionByIDAndTokenForUse(t.Context(), tc.id, tc.token, deadline)
		require.NoError(t, err)
		require.Nil(t, session)
	}

	_, err = db.Exec(`UPDATE users SET is_two_factor_enabled = true WHERE user_id = $1`, userID)
	require.NoError(t, err)
	_, err = db.Exec(`UPDATE legacy_kit_recovery_session_token SET created_at = $1`, timeutil.MicrosecondsAfterHours(-25))
	require.NoError(t, err)
	authRepo := &userrepo.UserAuthRepository{DB: db}
	_, err = authRepo.InsertOrUpdateSRPAuthAndKeyAttr(t.Context(), userID,
		ente.UpdateKeysRequest{}, &ente.SRPSetupEntity{SRPUserID: uuid.New()}, true, nil, true,
		func(ctx context.Context, tx *sql.Tx) error {
			return repository.CompleteRecovery(ctx, tx, sessionID, kitID, userID, "token")
		})
	var apiErr *ente.ApiError
	require.ErrorAs(t, err, &apiErr)
	require.Equal(t, ente.SessionExpired, apiErr.Code)
	var status ente.LegacyKitRecoveryStatus
	require.NoError(t, db.QueryRow(`SELECT status FROM legacy_kit_recovery_session WHERE id = $1`, sessionID).Scan(&status))
	require.Equal(t, ente.LegacyKitRecoveryStatusReady, status)
	var twoFactorEnabled bool
	require.NoError(t, db.QueryRow(`SELECT is_two_factor_enabled FROM users WHERE user_id = $1`, userID).Scan(&twoFactorEnabled))
	require.True(t, twoFactorEnabled)
	var authCount int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM srp_auth WHERE user_id = $1`, userID).Scan(&authCount))
	require.Zero(t, authCount)
}

func TestResumeRecoveryAfterTokenExpiry(t *testing.T) {
	testutil.WithServerRoot(t)
	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() { testutil.ResetTables(t, db) })
	userID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "legacy-kit-owner@ente.io", CreationTime: 1})
	repository := &Repository{DB: db}
	for _, status := range []ente.LegacyKitRecoveryStatus{ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady} {
		t.Run(string(status), func(t *testing.T) {
			kitID := insertLegacyKitForTest(t, db, userID, false)
			sessionID := uuid.New()
			waitTill := timeutil.MicrosecondsAfterHours(24)
			if status == ente.LegacyKitRecoveryStatusReady {
				waitTill = 1
			}
			insertLegacyKitSessionForTest(t, db, sessionID, kitID, userID, status, waitTill)
			expiredToken, liveToken := "expired-"+kitID.String(), "live-"+kitID.String()
			insertLegacyKitSessionTokenForTest(t, db, sessionID, expiredToken)
			insertLegacyKitSessionTokenForTest(t, db, sessionID, liveToken)
			_, err := db.Exec(`UPDATE legacy_kit_recovery_session_token SET created_at = $1 WHERE token_hash = $2`, timeutil.MicrosecondsAfterHours(-25), hashSessionToken(expiredToken))
			require.NoError(t, err)
			challenge := "challenge-" + kitID.String()
			require.NoError(t, repository.CreateChallenge(t.Context(), kitID, challenge, timeutil.MicrosecondsAfterHours(1)))
			_, session, token, created, err := repository.OpenOrResumeRecovery(t.Context(), kitID, challenge, timeutil.Microseconds(), nil)
			require.NoError(t, err)
			require.False(t, created)
			require.Equal(t, sessionID, session.ID)
			require.Equal(t, status, session.Status)
			require.Equal(t, waitTill, session.WaitTill)
			for _, validToken := range []string{token, liveToken} {
				resumed, err := repository.GetSessionByIDAndTokenForUse(t.Context(), sessionID, validToken, timeutil.Microseconds())
				require.NoError(t, err)
				require.Equal(t, sessionID, resumed.ID)
			}
			_, err = repository.GetSessionByIDAndTokenForUse(t.Context(), sessionID, expiredToken, timeutil.Microseconds())
			var apiErr *ente.ApiError
			require.ErrorAs(t, err, &apiErr)
			require.Equal(t, ente.SessionExpired, apiErr.Code)
		})
	}
}

func TestGetSessionByIDAndTokenForUseReturnsBlockedSessionAfterConcurrentBlock(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-kit-owner@ente.io",
		CreationTime: 1,
	})
	kitID := insertLegacyKitForTest(t, db, userID, false)
	sessionID := uuid.New()
	insertLegacyKitSessionForTest(t, db, sessionID, kitID, userID, ente.LegacyKitRecoveryStatusWaiting, 1)

	rawToken := "session-token"
	insertLegacyKitSessionTokenForTest(t, db, sessionID, rawToken)

	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	_, err = tx.ExecContext(t.Context(),
		`SELECT id FROM legacy_kit_recovery_session WHERE id = $1 FOR UPDATE`, sessionID)
	require.NoError(t, err)

	repo := &Repository{DB: db}
	type sessionResult struct {
		session *RecoverySessionRow
		err     error
	}
	resultCh := make(chan sessionResult, 1)
	go func() {
		session, err := repo.GetSessionByIDAndTokenForUse(
			t.Context(),
			sessionID,
			rawToken,
			timeutil.Microseconds(),
		)
		resultCh <- sessionResult{session: session, err: err}
	}()

	_, err = tx.ExecContext(t.Context(),
		`UPDATE legacy_kit_recovery_session SET status = $1 WHERE id = $2`,
		ente.LegacyKitRecoveryStatusBlocked,
		sessionID,
	)
	require.NoError(t, err)
	require.NoError(t, tx.Commit())

	result := <-resultCh
	require.NoError(t, result.err)
	require.NotNil(t, result.session)
	require.Equal(t, ente.LegacyKitRecoveryStatusBlocked, result.session.Status)
}

func TestOpenOrResumeRecoveryFailsIfKitWasDeletedBeforeLockReleases(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-kit-owner@ente.io",
		CreationTime: 1,
	})
	kitID := insertLegacyKitForTest(t, db, userID, false)
	repo := &Repository{DB: db}

	challenge := "legacy-kit-open:v1\n" + kitID.String() + "\nchallenge\n"
	require.NoError(t, repo.CreateChallenge(t.Context(), kitID, challenge, timeutil.MicrosecondsAfterHours(1)))

	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	_, err = tx.ExecContext(t.Context(),
		`SELECT id FROM legacy_kit WHERE id = $1 FOR UPDATE`, kitID)
	require.NoError(t, err)

	type openResult struct {
		kit     *KitRow
		session *RecoverySessionRow
		token   string
		created bool
		err     error
	}
	resultCh := make(chan openResult, 1)
	go func() {
		kit, session, token, created, err := repo.OpenOrResumeRecovery(
			t.Context(),
			kitID,
			challenge,
			timeutil.Microseconds(),
			&ente.LegacyKitRecoveryInitiator{UsedPartIndexes: []int{1, 2}},
		)
		resultCh <- openResult{kit: kit, session: session, token: token, created: created, err: err}
	}()

	_, err = tx.ExecContext(t.Context(),
		`UPDATE legacy_kit SET is_deleted = TRUE, deleted_at = $1 WHERE id = $2`,
		timeutil.Microseconds(),
		kitID,
	)
	require.NoError(t, err)
	require.NoError(t, tx.Commit())

	result := <-resultCh
	require.Error(t, result.err)
	require.True(t, errors.Is(result.err, ente.ErrNotFound))
	require.Nil(t, result.kit)
	require.Nil(t, result.session)
	require.Empty(t, result.token)
	require.False(t, result.created)

	var sessionCount int
	require.NoError(t, db.QueryRow(`SELECT COUNT(*) FROM legacy_kit_recovery_session WHERE kit_id = $1`, kitID).Scan(&sessionCount))
	require.Equal(t, 0, sessionCount)
}

func TestCreateKitWithLimitRejectsWhenConcurrentChangeConsumesFinalSlot(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-kit-owner@ente.io",
		CreationTime: 1,
	})
	for range 4 {
		insertLegacyKitForTest(t, db, userID, false)
	}

	tx, err := db.BeginTx(t.Context(), nil)
	require.NoError(t, err)
	_, err = tx.ExecContext(t.Context(),
		`SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE`, userID)
	require.NoError(t, err)

	repo := &Repository{DB: db}
	noticePeriod := 24
	createReq := ente.CreateLegacyKitRequest{
		ID:                    uuid.New(),
		Variant:               ente.LegacyKitVariantTwoOfThree,
		NoticePeriodInHours:   &noticePeriod,
		EncryptedRecoveryBlob: "recovery-blob",
		AuthPublicKey:         "auth-public-key",
		EncryptedOwnerBlob:    "owner-blob",
	}
	errCh := make(chan error, 1)
	go func() {
		errCh <- repo.CreateKitWithLimit(t.Context(), userID, createReq, 5)
	}()

	secondNoticePeriod := 24
	require.NoError(t, insertKit(t.Context(), tx, userID, ente.CreateLegacyKitRequest{
		ID:                    uuid.New(),
		Variant:               ente.LegacyKitVariantTwoOfThree,
		NoticePeriodInHours:   &secondNoticePeriod,
		EncryptedRecoveryBlob: "recovery-blob-5",
		AuthPublicKey:         "auth-public-key-5",
		EncryptedOwnerBlob:    "owner-blob-5",
	}))
	require.NoError(t, tx.Commit())

	createErr := <-errCh
	require.Error(t, createErr)
	var apiErr *ente.ApiError
	require.True(t, errors.As(createErr, &apiErr))
	require.Equal(t, "legacy kit limit reached", apiErr.Message)

	var activeKitCount int
	require.NoError(t, db.QueryRow(
		`SELECT COUNT(*) FROM legacy_kit WHERE user_id = $1 AND is_deleted = FALSE`,
		userID,
	).Scan(&activeKitCount))
	require.Equal(t, 5, activeKitCount)
}

func TestUpdateRecoveryNoticeRejectsActiveSession(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-kit-owner@ente.io",
		CreationTime: 1,
	})
	kitID := insertLegacyKitForTest(t, db, userID, false)
	insertLegacyKitSessionForTest(t, db, uuid.New(), kitID, userID, ente.LegacyKitRecoveryStatusWaiting, 1)

	repo := &Repository{DB: db}
	updated, err := repo.UpdateRecoveryNotice(t.Context(), userID, kitID, 168)
	require.Error(t, err)
	require.False(t, updated)

	var apiErr *ente.ApiError
	require.True(t, errors.As(err, &apiErr))
	require.Equal(t, ente.ActiveRecoverySession, apiErr.Code)
	require.Equal(t, http.StatusBadRequest, apiErr.HttpStatusCode)
	require.Equal(t, "cannot update recovery notice while there is an active recovery session", apiErr.Message)

	var noticePeriod int32
	require.NoError(t, db.QueryRow(
		`SELECT notice_period_in_hrs FROM legacy_kit WHERE id = $1`,
		kitID,
	).Scan(&noticePeriod))
	require.Equal(t, int32(24), noticePeriod)
}

func TestOpenRecoveryUsesUpdatedNoticePeriod(t *testing.T) {
	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	userID := testutil.InsertUser(t, db, testutil.UserFixture{
		UserID:       1,
		Email:        "legacy-kit-owner@ente.io",
		CreationTime: 1,
	})
	kitID := insertLegacyKitForTest(t, db, userID, false)
	repo := &Repository{DB: db}

	updated, err := repo.UpdateRecoveryNotice(t.Context(), userID, kitID, 360)
	require.NoError(t, err)
	require.True(t, updated)

	challenge := "legacy-kit-open:v1\n" + kitID.String() + "\nchallenge\n"
	require.NoError(t, repo.CreateChallenge(t.Context(), kitID, challenge, timeutil.MicrosecondsAfterHours(1)))

	_, session, _, created, err := repo.OpenOrResumeRecovery(
		t.Context(),
		kitID,
		challenge,
		timeutil.Microseconds(),
		&ente.LegacyKitRecoveryInitiator{UsedPartIndexes: []int{1, 2}},
	)
	require.NoError(t, err)
	require.True(t, created)
	require.NotNil(t, session)
	require.Equal(t, int32(360), session.EffectiveNoticePeriodHrs)
}

func insertLegacyKitForTest(t *testing.T, db *sql.DB, userID int64, isDeleted bool) uuid.UUID {
	t.Helper()

	kitID := uuid.New()
	var deletedAt any
	if isDeleted {
		deletedAt = int64(1)
	}
	_, err := db.Exec(
		`INSERT INTO legacy_kit(
			id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
			encrypted_owner_blob, is_deleted, deleted_at
		) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		kitID,
		userID,
		ente.LegacyKitVariantTwoOfThree,
		24,
		"encrypted-recovery-blob",
		"auth-public-key",
		"encrypted-owner-blob",
		isDeleted,
		deletedAt,
	)
	require.NoError(t, err)
	return kitID
}

func insertLegacyKitSessionForTest(
	t *testing.T,
	db *sql.DB,
	sessionID uuid.UUID,
	kitID uuid.UUID,
	userID int64,
	status ente.LegacyKitRecoveryStatus,
	waitTill int64,
) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO legacy_kit_recovery_session(
			id, kit_id, user_id, status, effective_notice_period_in_hrs, wait_till, initiators
		) VALUES($1, $2, $3, $4, $5, $6, '[]'::jsonb)`,
		sessionID,
		kitID,
		userID,
		status,
		24,
		waitTill,
	)
	require.NoError(t, err)
}

func insertLegacyKitSessionTokenForTest(t *testing.T, db *sql.DB, sessionID uuid.UUID, rawToken string) {
	t.Helper()

	_, err := db.Exec(
		`INSERT INTO legacy_kit_recovery_session_token(id, session_id, token_hash)
		 VALUES($1, $2, $3)`,
		uuid.New(),
		sessionID,
		hashSessionToken(rawToken),
	)
	require.NoError(t, err)
}
