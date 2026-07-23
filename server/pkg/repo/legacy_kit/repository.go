package legacy_kit

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"

	"github.com/ente/museum/ente"
	timeutil "github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
)

type Repository struct {
	DB *sql.DB
}

type KitRow struct {
	ID                uuid.UUID
	UserID            int64
	Variant           ente.LegacyKitVariant
	NoticePeriodInHrs int32
	// Base64(secretbox nonce || MAC || ciphertext) of the user's recovery key.
	EncryptedRecoveryBlob string
	// Base64(X25519 public key) derived deterministically from the kit secret.
	AuthPublicKey string
	// Base64(secretbox nonce || MAC || ciphertext) of owner-only part names and
	// stored share payloads used for listing and downloading cards again.
	EncryptedOwnerBlob string
	IsDeleted          bool
	CreatedAt          int64
	UpdatedAt          int64
	DeletedAt          sql.NullInt64
}

type RecoverySessionRow struct {
	ID                       uuid.UUID
	KitID                    uuid.UUID
	UserID                   int64
	Status                   ente.LegacyKitRecoveryStatus
	EffectiveNoticePeriodHrs int32
	WaitTill                 int64
	NextReminderAt           sql.NullInt64
	Initiators               []ente.LegacyKitRecoveryInitiator
	CreatedAt                int64
	UpdatedAt                int64
}

func (r *Repository) CreateKitWithLimit(
	ctx context.Context,
	userID int64,
	req ente.CreateLegacyKitRequest,
	maxActiveKits int,
) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "failed to start legacy kit create transaction")
	}
	defer tx.Rollback()

	if err := lockUserRow(ctx, tx, userID); err != nil {
		return err
	}
	count, err := countActiveKits(ctx, tx, userID)
	if err != nil {
		return err
	}
	if count >= maxActiveKits {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit limit reached"), "")
	}
	if err := insertKit(ctx, tx, userID, req); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return stacktrace.Propagate(err, "failed to commit legacy kit create")
	}
	return nil
}

func (r *Repository) ListKits(ctx context.Context, userID int64) ([]KitRow, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
		       encrypted_owner_blob,
		       is_deleted, created_at, updated_at, deleted_at
		FROM legacy_kit
		WHERE user_id = $1 AND is_deleted = FALSE
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to list legacy kits")
	}
	defer rows.Close()

	var kits []KitRow
	for rows.Next() {
		row, err := scanKit(rows)
		if err != nil {
			return nil, err
		}
		kits = append(kits, row)
	}
	return kits, nil
}

func (r *Repository) GetKitForOwner(ctx context.Context, userID int64, kitID uuid.UUID) (*KitRow, error) {
	row := r.DB.QueryRowContext(ctx, `
		SELECT id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
		       encrypted_owner_blob,
		       is_deleted, created_at, updated_at, deleted_at
		FROM legacy_kit
		WHERE id = $1 AND user_id = $2 AND is_deleted = FALSE`, kitID, userID)
	return scanKitRow(row)
}

func (r *Repository) GetKitByID(ctx context.Context, kitID uuid.UUID) (*KitRow, error) {
	row := r.DB.QueryRowContext(ctx, `
		SELECT id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
		       encrypted_owner_blob,
		       is_deleted, created_at, updated_at, deleted_at
		FROM legacy_kit
		WHERE id = $1`, kitID)
	return scanKitRow(row)
}

func (r *Repository) DeleteKit(ctx context.Context, userID int64, kitID uuid.UUID) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to start legacy kit delete transaction")
	}
	defer tx.Rollback()

	if err := lockUserRow(ctx, tx, userID); err != nil {
		return false, err
	}
	if _, err := getKitForOwnerByIDForUpdate(ctx, tx, userID, kitID); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	if _, err := blockActiveSessionForKitTx(ctx, tx, kitID, userID); err != nil {
		return false, err
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE legacy_kit
		SET is_deleted = TRUE, deleted_at = $1
		WHERE id = $2 AND user_id = $3 AND is_deleted = FALSE`,
		timeutil.Microseconds(), kitID, userID,
	); err != nil {
		return false, stacktrace.Propagate(err, "failed to delete legacy kit")
	}
	if err := tx.Commit(); err != nil {
		return false, stacktrace.Propagate(err, "failed to commit legacy kit delete")
	}
	return true, nil
}

func (r *Repository) CreateChallenge(ctx context.Context, kitID uuid.UUID, challenge string, expiresAt int64) error {
	_, err := r.DB.ExecContext(ctx, `
		INSERT INTO legacy_kit_challenge(id, kit_id, challenge_hash, expires_at)
		VALUES($1, $2, $3, $4)`,
		uuid.New(), kitID, hashChallenge(challenge), expiresAt,
	)
	if err != nil {
		return stacktrace.Propagate(err, "failed to create legacy kit challenge")
	}
	return nil
}

func (r *Repository) GetActiveSessionByKit(ctx context.Context, kitID uuid.UUID) (*RecoverySessionRow, error) {
	row := r.DB.QueryRowContext(ctx, `
		SELECT id, kit_id, user_id, status, effective_notice_period_in_hrs,
		       wait_till, next_reminder_at, initiators, created_at, updated_at
		FROM legacy_kit_recovery_session
		WHERE kit_id = $1 AND status IN ($2, $3)`,
		kitID, ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady,
	)
	session, err := scanRecoverySessionRow(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return session, nil
}

func (r *Repository) ListActiveSessionsForUser(ctx context.Context, userID int64) ([]RecoverySessionRow, error) {
	rows, err := r.DB.QueryContext(ctx, `
		SELECT id, kit_id, user_id, status, effective_notice_period_in_hrs,
		       wait_till, next_reminder_at, initiators, created_at, updated_at
		FROM legacy_kit_recovery_session
		WHERE user_id = $1 AND status IN ($2, $3)`,
		userID, ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady,
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to list legacy kit sessions")
	}
	defer rows.Close()

	var sessions []RecoverySessionRow
	for rows.Next() {
		session, err := scanRecoverySession(rows)
		if err != nil {
			return nil, err
		}
		sessions = append(sessions, session)
	}
	return sessions, nil
}

func (r *Repository) OpenOrResumeRecovery(
	ctx context.Context,
	kitID uuid.UUID,
	challenge string,
	now int64,
	initiator *ente.LegacyKitRecoveryInitiator,
) (*KitRow, *RecoverySessionRow, string, bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, "", false, stacktrace.Propagate(err, "failed to start legacy kit recovery transaction")
	}
	defer tx.Rollback()

	kit, err := getKitByIDForUpdate(ctx, tx, kitID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, "", false, stacktrace.Propagate(ente.ErrNotFound, "legacy kit not found")
		}
		return nil, nil, "", false, err
	}
	if kit.IsDeleted {
		return nil, nil, "", false, stacktrace.Propagate(ente.ErrNotFound, "legacy kit not found")
	}

	consumed, err := consumeChallengeTx(ctx, tx, kitID, challenge, now)
	if err != nil {
		return nil, nil, "", false, err
	}
	if !consumed {
		return nil, nil, "", false, stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit challenge is invalid or expired"), "")
	}

	session, err := getActiveSessionByKitForUpdate(ctx, tx, kitID)
	if err != nil {
		return nil, nil, "", false, err
	}
	createdSession := false
	var rawSessionToken string
	if session == nil {
		session, rawSessionToken, err = createRecoverySessionTx(ctx, tx, kitID, kit.UserID, kit.NoticePeriodInHrs, initiator)
		if err != nil {
			return nil, nil, "", false, err
		}
		createdSession = true
	} else {
		session, err = ensureSessionReadyForUseTx(ctx, tx, session, now)
		if err != nil {
			return nil, nil, "", false, err
		}
		rawSessionToken, err = resumeRecoverySessionTx(ctx, tx, session.ID, initiator)
		if err != nil {
			return nil, nil, "", false, err
		}
		if initiator != nil {
			session.Initiators = append(session.Initiators, *initiator)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, nil, "", false, stacktrace.Propagate(err, "failed to commit legacy kit recovery transaction")
	}
	return kit, session, rawSessionToken, createdSession, nil
}

func (r *Repository) GetSessionByIDAndTokenForUse(
	ctx context.Context,
	sessionID uuid.UUID,
	sessionToken string,
	now int64,
) (*RecoverySessionRow, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, stacktrace.Propagate(err, "failed to start legacy kit session transaction")
	}
	defer tx.Rollback()

	session, err := getSessionByIDAndTokenForUpdate(ctx, tx, sessionID, sessionToken)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	session, err = ensureSessionReadyForUseTx(ctx, tx, session, now)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, stacktrace.Propagate(err, "failed to commit legacy kit session transaction")
	}
	return session, nil
}

func createRecoverySessionTx(
	ctx context.Context,
	tx *sql.Tx,
	kitID uuid.UUID,
	userID int64,
	noticePeriodHrs int32,
	initiator *ente.LegacyKitRecoveryInitiator,
) (*RecoverySessionRow, string, error) {
	session := &RecoverySessionRow{
		ID:                       uuid.New(),
		KitID:                    kitID,
		UserID:                   userID,
		Status:                   ente.LegacyKitRecoveryStatusWaiting,
		EffectiveNoticePeriodHrs: noticePeriodHrs,
		WaitTill:                 timeutil.MicrosecondsAfterHours(noticePeriodHrs),
		CreatedAt:                timeutil.Microseconds(),
	}
	nextReminder := sql.NullInt64{}
	if noticePeriodHrs == 0 {
		session.Status = ente.LegacyKitRecoveryStatusReady
		session.WaitTill = timeutil.Microseconds()
	} else {
		nextReminder = sql.NullInt64{Int64: session.CreatedAt, Valid: true}
	}
	session.NextReminderAt = nextReminder
	if initiator != nil {
		session.Initiators = append(session.Initiators, *initiator)
	}
	initiatorsJSON, err := marshalInitiators(session.Initiators)
	if err != nil {
		return nil, "", err
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO legacy_kit_recovery_session(
			id, kit_id, user_id, status, effective_notice_period_in_hrs, wait_till, next_reminder_at, initiators
		) VALUES($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
		session.ID, session.KitID, session.UserID, session.Status,
		session.EffectiveNoticePeriodHrs, session.WaitTill, nullableInt64(session.NextReminderAt),
		initiatorsJSON,
	)
	if err != nil {
		return nil, "", stacktrace.Propagate(err, "failed to create legacy kit recovery session")
	}
	rawSessionToken, err := issueSessionToken(ctx, tx, session.ID)
	if err != nil {
		return nil, "", err
	}
	return session, rawSessionToken, nil
}

func resumeRecoverySessionTx(
	ctx context.Context,
	tx *sql.Tx,
	sessionID uuid.UUID,
	initiator *ente.LegacyKitRecoveryInitiator,
) (string, error) {
	if initiator != nil {
		initiatorJSON, err := marshalInitiators([]ente.LegacyKitRecoveryInitiator{*initiator})
		if err != nil {
			return "", err
		}
		_, err = tx.ExecContext(ctx, `
			UPDATE legacy_kit_recovery_session
			SET initiators = initiators || $1::jsonb
			WHERE id = $2`,
			initiatorJSON, sessionID,
		)
		if err != nil {
			return "", stacktrace.Propagate(err, "failed to append legacy kit recovery initiator")
		}
	}

	rawSessionToken, err := issueSessionToken(ctx, tx, sessionID)
	if err != nil {
		return "", err
	}
	return rawSessionToken, nil
}

func hashSessionToken(sessionToken string) string {
	sum := sha256.Sum256([]byte(sessionToken))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func hashChallenge(challenge string) string {
	sum := sha256.Sum256([]byte(challenge))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func (r *Repository) UpdateSessionStatus(ctx context.Context, sessionID uuid.UUID, status ente.LegacyKitRecoveryStatus) (bool, error) {
	result, err := r.DB.ExecContext(ctx, `
		UPDATE legacy_kit_recovery_session SET status = $1
		WHERE id = $2 AND status IN ($3, $4)`,
		status, sessionID, ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady,
	)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to update legacy kit session status")
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to inspect legacy kit session update")
	}
	return rows > 0, nil
}

func (r *Repository) UpdateRecoveryNotice(ctx context.Context, userID int64, kitID uuid.UUID, noticePeriodHrs int32) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to start legacy kit notice update transaction")
	}
	defer tx.Rollback()

	if err := lockUserRow(ctx, tx, userID); err != nil {
		return false, err
	}
	if _, err := getKitForOwnerByIDForUpdate(ctx, tx, userID, kitID); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	session, err := getActiveSessionByKitForUpdate(ctx, tx, kitID)
	if err != nil {
		return false, err
	}
	if session != nil {
		return false, stacktrace.Propagate(ente.NewBadRequestWithMessage("cannot update recovery notice while there is an active recovery session"), "")
	}
	result, err := tx.ExecContext(ctx, `
		UPDATE legacy_kit
		SET notice_period_in_hrs = $1
		WHERE id = $2 AND user_id = $3 AND is_deleted = FALSE`,
		noticePeriodHrs, kitID, userID,
	)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to update legacy kit notice period")
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to inspect legacy kit notice update")
	}
	if err := tx.Commit(); err != nil {
		return false, stacktrace.Propagate(err, "failed to commit legacy kit notice update")
	}
	return rows > 0, nil
}

func (r *Repository) BlockActiveSessionForKit(ctx context.Context, kitID uuid.UUID, userID int64) (bool, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to start legacy kit block transaction")
	}
	defer tx.Rollback()

	if _, err := getKitForOwnerByIDForUpdate(ctx, tx, userID, kitID); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	updated, err := blockActiveSessionForKitTx(ctx, tx, kitID, userID)
	if err != nil {
		return false, err
	}
	if err := tx.Commit(); err != nil {
		return false, stacktrace.Propagate(err, "failed to commit legacy kit block")
	}
	return updated, nil
}

func nullableInt64(value sql.NullInt64) any {
	if value.Valid {
		return value.Int64
	}
	return nil
}

type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

func issueSessionToken(ctx context.Context, exec execer, sessionID uuid.UUID) (string, error) {
	rawSessionToken := randomToken()
	_, err := exec.ExecContext(ctx, `
		INSERT INTO legacy_kit_recovery_session_token(id, session_id, token_hash)
		VALUES($1, $2, $3)`,
		uuid.New(), sessionID, hashSessionToken(rawSessionToken),
	)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to issue legacy kit recovery session token")
	}
	return rawSessionToken, nil
}

type queryRower interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func countActiveKits(ctx context.Context, queryer queryRower, userID int64) (int, error) {
	var count int
	err := queryer.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM legacy_kit WHERE user_id = $1 AND is_deleted = FALSE`,
		userID,
	).Scan(&count)
	if err != nil {
		return 0, stacktrace.Propagate(err, "failed to count legacy kits")
	}
	return count, nil
}

func insertKit(ctx context.Context, exec execer, userID int64, req ente.CreateLegacyKitRequest) error {
	if req.NoticePeriodInHours == nil {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("legacy kit notice period is required"), "")
	}
	_, err := exec.ExecContext(ctx, `
			INSERT INTO legacy_kit(
				id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
				encrypted_owner_blob
			) VALUES($1, $2, $3, $4, $5, $6, $7)`,
		req.ID, userID, req.Variant, *req.NoticePeriodInHours, req.EncryptedRecoveryBlob,
		req.AuthPublicKey, req.EncryptedOwnerBlob,
	)
	if err != nil {
		return stacktrace.Propagate(err, "failed to create legacy kit")
	}
	return nil
}

func lockUserRow(ctx context.Context, tx *sql.Tx, userID int64) error {
	var lockedUserID int64
	err := tx.QueryRowContext(ctx, `SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE`, userID).Scan(&lockedUserID)
	if err != nil {
		if err == sql.ErrNoRows {
			return stacktrace.Propagate(ente.ErrNotFound, "legacy kit owner not found")
		}
		return stacktrace.Propagate(err, "failed to lock legacy kit owner")
	}
	return nil
}

func getKitByIDForUpdate(ctx context.Context, tx *sql.Tx, kitID uuid.UUID) (*KitRow, error) {
	row := tx.QueryRowContext(ctx, `
		SELECT id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
		       encrypted_owner_blob,
		       is_deleted, created_at, updated_at, deleted_at
		FROM legacy_kit
		WHERE id = $1
		FOR UPDATE`, kitID)
	return scanKitRow(row)
}

func getKitForOwnerByIDForUpdate(ctx context.Context, tx *sql.Tx, userID int64, kitID uuid.UUID) (*KitRow, error) {
	row := tx.QueryRowContext(ctx, `
		SELECT id, user_id, variant, notice_period_in_hrs, encrypted_recovery_blob, auth_public_key,
		       encrypted_owner_blob,
		       is_deleted, created_at, updated_at, deleted_at
		FROM legacy_kit
		WHERE id = $1 AND user_id = $2 AND is_deleted = FALSE
		FOR UPDATE`, kitID, userID)
	return scanKitRow(row)
}

func consumeChallengeTx(ctx context.Context, tx *sql.Tx, kitID uuid.UUID, challenge string, now int64) (bool, error) {
	result, err := tx.ExecContext(ctx, `
		DELETE FROM legacy_kit_challenge
		WHERE kit_id = $1 AND challenge_hash = $2 AND expires_at >= $3`,
		kitID, hashChallenge(challenge), now,
	)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to consume legacy kit challenge")
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to inspect legacy kit challenge delete")
	}
	return rows > 0, nil
}

func getActiveSessionByKitForUpdate(ctx context.Context, tx *sql.Tx, kitID uuid.UUID) (*RecoverySessionRow, error) {
	row := tx.QueryRowContext(ctx, `
		SELECT id, kit_id, user_id, status, effective_notice_period_in_hrs,
		       wait_till, next_reminder_at, initiators, created_at, updated_at
		FROM legacy_kit_recovery_session
		WHERE kit_id = $1 AND status IN ($2, $3)
		FOR UPDATE`,
		kitID, ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady,
	)
	session, err := scanRecoverySessionRow(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return session, nil
}

func getSessionByIDAndTokenForUpdate(ctx context.Context, tx *sql.Tx, sessionID uuid.UUID, sessionToken string) (*RecoverySessionRow, error) {
	row := tx.QueryRowContext(ctx, `
		SELECT s.id, s.kit_id, s.user_id, s.status, s.effective_notice_period_in_hrs,
		       s.wait_till, s.next_reminder_at, s.initiators, s.created_at, s.updated_at
		FROM legacy_kit_recovery_session s
		JOIN legacy_kit_recovery_session_token t ON t.session_id = s.id
		WHERE s.id = $1 AND t.token_hash = $2
		FOR UPDATE OF s`,
		sessionID, hashSessionToken(sessionToken))
	return scanRecoverySessionRow(row)
}

func ensureSessionReadyForUseTx(
	ctx context.Context,
	tx *sql.Tx,
	session *RecoverySessionRow,
	now int64,
) (*RecoverySessionRow, error) {
	if session.Status != ente.LegacyKitRecoveryStatusWaiting || session.WaitTill > now {
		return session, nil
	}

	row := tx.QueryRowContext(ctx, `
		UPDATE legacy_kit_recovery_session
		SET status = $1, wait_till = $2
		WHERE id = $3 AND status = $4
		RETURNING id, kit_id, user_id, status, effective_notice_period_in_hrs,
		          wait_till, next_reminder_at, initiators, created_at, updated_at`,
		ente.LegacyKitRecoveryStatusReady, now, session.ID, ente.LegacyKitRecoveryStatusWaiting,
	)
	updatedSession, err := scanRecoverySessionRow(row)
	if err == nil {
		return updatedSession, nil
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	return getSessionByIDForUpdate(ctx, tx, session.ID)
}

func getSessionByIDForUpdate(ctx context.Context, tx *sql.Tx, sessionID uuid.UUID) (*RecoverySessionRow, error) {
	row := tx.QueryRowContext(ctx, `
		SELECT id, kit_id, user_id, status, effective_notice_period_in_hrs,
		       wait_till, next_reminder_at, initiators, created_at, updated_at
		FROM legacy_kit_recovery_session
		WHERE id = $1
		FOR UPDATE`, sessionID)
	return scanRecoverySessionRow(row)
}

func blockActiveSessionForKitTx(ctx context.Context, exec execer, kitID uuid.UUID, userID int64) (bool, error) {
	result, err := exec.ExecContext(ctx, `
		UPDATE legacy_kit_recovery_session s
		SET status = $1
		FROM legacy_kit k
		WHERE s.kit_id = $2
		  AND k.id = s.kit_id
		  AND k.user_id = $3
		  AND s.status IN ($4, $5)`,
		ente.LegacyKitRecoveryStatusBlocked, kitID, userID,
		ente.LegacyKitRecoveryStatusWaiting, ente.LegacyKitRecoveryStatusReady,
	)
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to block legacy kit session")
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return false, stacktrace.Propagate(err, "failed to inspect legacy kit block")
	}
	return rows > 0, nil
}

func scanKit(scanner interface {
	Scan(dest ...any) error
}) (KitRow, error) {
	var row KitRow
	err := scanner.Scan(
		&row.ID,
		&row.UserID,
		&row.Variant,
		&row.NoticePeriodInHrs,
		&row.EncryptedRecoveryBlob,
		&row.AuthPublicKey,
		&row.EncryptedOwnerBlob,
		&row.IsDeleted,
		&row.CreatedAt,
		&row.UpdatedAt,
		&row.DeletedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return KitRow{}, err
		}
		return KitRow{}, stacktrace.Propagate(err, "failed to scan legacy kit")
	}
	return row, nil
}

func scanKitRow(row *sql.Row) (*KitRow, error) {
	kit, err := scanKit(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	return &kit, nil
}

func scanRecoverySession(scanner interface {
	Scan(dest ...any) error
}) (RecoverySessionRow, error) {
	var row RecoverySessionRow
	var initiatorsRaw []byte
	err := scanner.Scan(
		&row.ID,
		&row.KitID,
		&row.UserID,
		&row.Status,
		&row.EffectiveNoticePeriodHrs,
		&row.WaitTill,
		&row.NextReminderAt,
		&initiatorsRaw,
		&row.CreatedAt,
		&row.UpdatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return RecoverySessionRow{}, err
		}
		return RecoverySessionRow{}, stacktrace.Propagate(err, "failed to scan legacy kit session")
	}
	if len(initiatorsRaw) > 0 {
		if err := json.Unmarshal(initiatorsRaw, &row.Initiators); err != nil {
			return RecoverySessionRow{}, stacktrace.Propagate(err, "failed to decode legacy kit recovery initiators")
		}
	}
	return row, nil
}

func marshalInitiators(initiators []ente.LegacyKitRecoveryInitiator) (string, error) {
	payload, err := json.Marshal(initiators)
	if err != nil {
		return "", stacktrace.Propagate(err, "failed to encode legacy kit recovery initiators")
	}
	return string(payload), nil
}

func scanRecoverySessionRow(row *sql.Row) (*RecoverySessionRow, error) {
	session, err := scanRecoverySession(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	return &session, nil
}

func randomToken() string {
	buf := make([]byte, 32)
	rand.Read(buf)
	return base64.RawURLEncoding.EncodeToString(buf)
}
