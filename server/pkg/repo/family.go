package repo

import (
	"context"
	"database/sql"
	"errors"

	"github.com/ente/museum/ente"
	"github.com/ente/stacktrace"
	"github.com/google/uuid"
	"github.com/lib/pq"
)

// FamilyRepository is an implementation of the FamilyRepo
type FamilyRepository struct {
	DB *sql.DB
}

var (
	ActiveFamilyMemberStatus          = []ente.MemberStatus{ente.ACCEPTED, ente.SELF}
	ActiveOrInvitedFamilyMemberStatus = []ente.MemberStatus{ente.INVITED, ente.ACCEPTED, ente.SELF}
)

// CreateFamily add the current user as the admin member.
func (repo *FamilyRepository) CreateFamily(ctx context.Context, adminID int64) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO families(id, admin_id, member_id, status) 
			VALUES($1, $2, $3, $4) ON CONFLICT (admin_id,member_id) 
			    DO UPDATE SET status = $4 WHERE families.status NOT IN ($4)`, uuid.New(), adminID, adminID, ente.SELF)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}

	result, err := tx.ExecContext(ctx, `UPDATE users SET family_admin_id = $1 WHERE user_id = $2 and family_admin_id is  null`, adminID, adminID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if affected != 1 {
		tx.Rollback()
		return stacktrace.Propagate(errors.New("exactly one row should be updated"), "")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit txn creating family")
}

func (repo *FamilyRepository) CloseFamily(ctx context.Context, adminID int64) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `DELETE FROM families WHERE admin_id = $1`, adminID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affectedRows, err := tx.ExecContext(ctx, `UPDATE users SET family_admin_id = null WHERE family_admin_id = $1`, adminID)

	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affected, err := affectedRows.RowsAffected()
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if affected != 1 {
		return stacktrace.Propagate(errors.New("exactly one row should be updated"), "")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit txn closing family")
}

// AddMemberInvite inserts a family invitation entry for this given pair of admin & member and return the active inviteToken
// which can be used to accept the invite
func (repo *FamilyRepository) AddMemberInvite(ctx context.Context, adminID int64, memberID int64, inviteToken string, storageLimit *int64) (string, error) {
	if adminID == memberID {
		return "", stacktrace.Propagate(errors.New("memberID and adminID can not be same"), "")
	}
	// on conflict, we should not change the status from 'ACCEPTED' to `INVITED`.
	// Also, the token should not be updated if the user is already in `INVITED` state.
	_, err := repo.DB.ExecContext(ctx, `INSERT INTO families(id, admin_id, member_id, status, token, storage_limit) 
			VALUES($1, $2, $3, $4, $5, $6) ON CONFLICT (admin_id,member_id) 
			    DO UPDATE SET(status, token) = ($4, $5) WHERE  NOT (families.status = ANY($7))`,
		uuid.New(), adminID, memberID, ente.INVITED, inviteToken, storageLimit, pq.Array([]ente.MemberStatus{ente.INVITED, ente.ACCEPTED}))
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	// separate query for fetch current token. Returning the same token in previous query was making query complex for
	// the case when there's no DB update.
	var activeInviteToken string
	err = repo.DB.QueryRowContext(ctx, `SELECT token from families where admin_id = $1 and member_id = $2 and status = $3`,
		adminID, memberID, ente.INVITED).Scan(&activeInviteToken)
	return activeInviteToken, stacktrace.Propagate(err, "")
}

// GetInvite returns information about family invitation for given token
func (repo *FamilyRepository) GetInvite(token string) (ente.FamilyMember, error) {
	row := repo.DB.QueryRow(`SELECT id, admin_id, member_id, status, storage_limit from families WHERE token = $1`, token)
	return repo.convertRowToFamilyMember(row)
}

// GetMemberById returns information about a particular member in a family
func (repo *FamilyRepository) GetMemberById(ctx context.Context, id uuid.UUID) (ente.FamilyMember, error) {
	row := repo.DB.QueryRowContext(ctx, `SELECT id, admin_id, member_id, status, storage_limit from families WHERE id = $1`, id)
	return repo.convertRowToFamilyMember(row)
}

func (repo *FamilyRepository) convertRowToFamilyMember(row *sql.Row) (ente.FamilyMember, error) {
	var member ente.FamilyMember
	err := row.Scan(&member.ID, &member.AdminUserID, &member.MemberUserID, &member.Status, &member.StorageLimit)
	if err != nil {
		return ente.FamilyMember{}, stacktrace.Propagate(err, "")
	}
	member.IsAdmin = member.MemberUserID == member.AdminUserID
	return member, nil
}

// GetMembersWithStatus returns all the members in a family managed by given inviter
func (repo *FamilyRepository) GetMembersWithStatus(adminID int64, statuses []ente.MemberStatus) ([]ente.FamilyMember, error) {
	rows, err := repo.DB.Query(`SELECT id, admin_id, member_id, status, storage_limit from families
		WHERE admin_id = $1 and status = ANY($2)`, adminID, pq.Array(statuses))

	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return convertRowsToFamilyMember(rows)
}

// AcceptInvite change the invitation status in the family db for the given invite token
func (repo *FamilyRepository) AcceptInvite(ctx context.Context, adminID int64, memberID int64, token string) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE families SET status = $1 WHERE token = $2`, ente.ACCEPTED, token)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	result, err := tx.ExecContext(ctx, `UPDATE users SET family_admin_id = $1 WHERE user_id = $2 and family_admin_id is  null`, adminID, memberID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	if affected != 1 {
		tx.Rollback()
		return stacktrace.Propagate(errors.New("exactly one row should be updated"), "")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit txn for accepting family invite")
}

// RemoveMember removes an existing member from the family plan
func (repo *FamilyRepository) RemoveMember(ctx context.Context, adminID int64, memberID int64, removeReason ente.MemberStatus) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	result, err := tx.ExecContext(ctx, `UPDATE families set status = $1 WHERE admin_id = $2 AND member_id = $3 AND status= $4`, removeReason, adminID, memberID, ente.ACCEPTED)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	affected, _ := result.RowsAffected()
	if affected != 1 {
		tx.Rollback()
		return stacktrace.Propagate(errors.New("exactly one row should be updated"), "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE users set family_admin_id = null WHERE user_id = $1 and family_admin_id = $2`, memberID, adminID)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit")
}

// UpdateStorage is used to set Pre-existing Members Storage Limit.
func (repo *FamilyRepository) ModifyMemberStorage(ctx context.Context, adminID int64, id uuid.UUID, storageLimit *int64) error {
	_, err := repo.DB.Exec(`UPDATE families SET storage_limit=$1 where id=$2`, storageLimit, id)
	if err != nil {
		return stacktrace.Propagate(err, "Could not update Members Storage Limit")
	}

	return stacktrace.Propagate(err, "Failed to Modify Members Storage Limit")
}

// RevokeInvite revokes the invitation invite
func (repo *FamilyRepository) RevokeInvite(ctx context.Context, adminID int64, memberID int64) error {
	tx, err := repo.DB.BeginTx(ctx, nil)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	_, err = tx.ExecContext(ctx, `UPDATE families set status=$1 WHERE admin_id = $2 AND member_id = $3 AND status = $4`, ente.REVOKED, adminID, memberID, ente.INVITED)
	if err != nil {
		tx.Rollback()
		return stacktrace.Propagate(err, "")
	}
	return stacktrace.Propagate(tx.Commit(), "failed to commit")
}

// DeclineAnyPendingInvite is used for removing any pending invite for the user when their account is deleted
func (repo *FamilyRepository) DeclineAnyPendingInvite(ctx context.Context, memberID int64) error {
	_, err := repo.DB.ExecContext(ctx, `UPDATE families set status=$1 WHERE member_id = $2 AND status = $3`, ente.DECLINED, memberID, ente.INVITED)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func convertRowsToFamilyMember(rows *sql.Rows) ([]ente.FamilyMember, error) {
	defer rows.Close()
	familyMembers := make([]ente.FamilyMember, 0)
	for rows.Next() {
		var member ente.FamilyMember
		err := rows.Scan(&member.ID, &member.AdminUserID, &member.MemberUserID, &member.Status, &member.StorageLimit)
		if err != nil {
			return nil, stacktrace.Propagate(err, "")
		}
		member.IsAdmin = member.MemberUserID == member.AdminUserID
		familyMembers = append(familyMembers, member)
	}
	return familyMembers, nil
}
