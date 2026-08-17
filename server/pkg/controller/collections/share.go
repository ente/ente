package collections

import (
	"context"
	"database/sql"
	"errors"
	"slices"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/controller/access"
	"github.com/ente/museum/pkg/controller/public"
	"github.com/ente/museum/pkg/utils/auth"
	emailUtil "github.com/ente/museum/pkg/utils/email"
	"github.com/ente/museum/pkg/utils/time"
	"github.com/ente/stacktrace"
	"github.com/gin-contrib/requestid"
	"github.com/gin-gonic/gin"
	log "github.com/sirupsen/logrus"
)

func (c *CollectionController) Share(ctx *gin.Context, req ente.AlterShareRequest) ([]ente.CollectionUser, error) {
	fromUserID := auth.GetUserID(ctx.Request.Header)
	if err := validateSealedCollectionKey(req.EncryptedKey); err != nil {
		return nil, err
	}
	role := ente.VIEWER
	if req.Role != nil {
		role = *req.Role
	}

	collection, err := c.collectionForShareMutation(req.CollectionID, fromUserID)
	if err != nil {
		return nil, err
	}
	if !collection.AllowParticipantSharing(role) {
		return nil, stacktrace.Propagate(ente.ErrBadRequest, "sharing %s is not allowed", collection.Type)
	}

	toUserID, err := c.UserLookup.LookupUserID(fromUserID, req.Email)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if err := validateShareRecipient(fromUserID, collection.Owner.ID, toUserID); err != nil {
		return nil, err
	}
	err = c.CollectionRepo.Share(
		req.CollectionID,
		collection.Owner.ID,
		toUserID,
		req.EncryptedKey,
		role,
		time.Microseconds(),
	)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	sharees, err := c.GetSharees(ctx, req.CollectionID, fromUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return sharees, nil
}

func (c *CollectionController) BulkShare(
	ctx *gin.Context,
	req ente.BulkCollectionShareRequest,
) ([]ente.BulkCollectionShareResult, error) {
	if err := validateCollectionShareBatch(req.Collections, req.Source); err != nil {
		return nil, err
	}
	fromUserID := auth.GetUserID(ctx.Request.Header)
	if err := validateBulkShareRecipient(fromUserID, req.RecipientUserID); err != nil {
		return nil, err
	}
	if err := c.UserLookup.VerifyUserID(
		fromUserID,
		req.RecipientEmail,
		req.RecipientUserID,
	); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if req.Source == ente.AutomaticShare {
		sameFamily, err := c.UserRepo.AreUsersInSameFamily(
			ctx.Request.Context(),
			fromUserID,
			req.RecipientUserID,
		)
		if err != nil {
			return nil, err
		}
		if !sameFamily {
			return nil, stacktrace.Propagate(ente.ErrAutomaticShareRecipientNotEligible, "")
		}
	}

	results := make([]ente.BulkCollectionShareResult, 0, len(req.Collections))
	for _, item := range req.Collections {
		status, err := c.shareCollectionWithUserID(
			ctx,
			fromUserID,
			req.RecipientUserID,
			req.Source,
			item,
		)
		if err != nil {
			log.WithError(err).WithFields(log.Fields{
				"collection_id":     item.CollectionID,
				"from_user_id":      fromUserID,
				"recipient_user_id": req.RecipientUserID,
			}).Warn("bulk collection share failed")
			status = ente.CollectionShareOperationFailed
		}
		results = append(results, ente.BulkCollectionShareResult{
			CollectionID: item.CollectionID,
			Status:       status,
		})
	}
	return results, nil
}

func validateBulkShareRecipient(actorUserID, recipientUserID int64) error {
	if recipientUserID <= 0 {
		return stacktrace.Propagate(ente.ErrBadRequest, "invalid recipient user ID")
	}
	if actorUserID == recipientUserID {
		return stacktrace.Propagate(ente.ErrBadRequest, "Can not share collections with self")
	}
	return nil
}

func (c *CollectionController) shareCollectionWithUserID(
	ctx context.Context,
	fromUserID int64,
	toUserID int64,
	source ente.CollectionShareSource,
	item ente.BulkCollectionShareItem,
) (ente.CollectionShareStatus, error) {
	if err := validateSealedCollectionKey(item.EncryptedKey); err != nil {
		return "", err
	}
	collection, err := c.collectionForShareMutation(item.CollectionID, fromUserID)
	if err != nil {
		return "", err
	}
	if source == ente.AutomaticShare && fromUserID != collection.Owner.ID {
		return "", stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if !collection.AllowParticipantSharing(item.Role) {
		return "", stacktrace.Propagate(
			ente.ErrBadRequest,
			"sharing %s as %s is not allowed",
			collection.Type,
			item.Role,
		)
	}
	if err := validateShareRecipient(fromUserID, collection.Owner.ID, toUserID); err != nil {
		return "", err
	}
	updationTime := time.Microseconds()
	if source == ente.ManualShare {
		err := c.CollectionRepo.Share(
			item.CollectionID,
			collection.Owner.ID,
			toUserID,
			item.EncryptedKey,
			item.Role,
			updationTime,
		)
		return ente.CollectionShared, err
	}
	return c.CollectionRepo.ShareAutomatically(
		ctx,
		item.CollectionID,
		collection.Owner.ID,
		toUserID,
		item.EncryptedKey,
		item.Role,
		updationTime,
	)
}

func (c *CollectionController) collectionForShareMutation(
	collectionID int64,
	actorUserID int64,
) (ente.Collection, error) {
	collection, err := c.CollectionRepo.Get(collectionID)
	if err != nil {
		return ente.Collection{}, stacktrace.Propagate(err, "")
	}
	if actorUserID == collection.Owner.ID {
		return collection, nil
	}
	shareeRole, err := c.CollectionRepo.GetCollectionShareeRole(collectionID, actorUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ente.Collection{}, stacktrace.Propagate(ente.ErrPermissionDenied, "")
		}
		return ente.Collection{}, stacktrace.Propagate(err, "")
	}
	if shareeRole == nil || *shareeRole != ente.ADMIN {
		return ente.Collection{}, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	return collection, nil
}

func validateShareRecipient(actorUserID, ownerUserID, recipientUserID int64) error {
	if recipientUserID == actorUserID {
		return stacktrace.Propagate(ente.ErrBadRequest, "Can not share collection with self")
	}
	if recipientUserID == ownerUserID {
		return stacktrace.Propagate(ente.ErrBadRequest, "Can not share collection with owner")
	}
	return nil
}

func validateCollectionShareBatch(
	items []ente.BulkCollectionShareItem,
	source ente.CollectionShareSource,
) error {
	if !source.IsValid() || len(items) == 0 {
		return stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	if len(items) > ente.MaxCollectionShareBatchSize {
		return stacktrace.Propagate(ente.ErrBatchSizeTooLarge, "")
	}
	seen := make(map[int64]struct{}, len(items))
	for _, item := range items {
		if _, exists := seen[item.CollectionID]; exists {
			return stacktrace.Propagate(ente.ErrBadRequest, "duplicate collection ID %d", item.CollectionID)
		}
		seen[item.CollectionID] = struct{}{}
	}
	return nil
}

func (c *CollectionController) JoinViaLink(ctx *gin.Context, req ente.JoinCollectionViaLinkRequest) error {
	if err := validateSealedCollectionKey(req.EncryptedKey); err != nil {
		return err
	}
	userID := auth.GetUserID(ctx.Request.Header)
	collection, err := c.CollectionRepo.Get(req.CollectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if collection.Owner.ID == userID {
		return stacktrace.Propagate(ente.ErrBadRequest, "owner can not join via link")
	}
	if !collection.AllowSharing() {
		return stacktrace.Propagate(ente.ErrBadRequest, "joining %s is not allowed", collection.Type)
	}
	collectionLinkToken, err := c.CollectionLinkCtrl.GetActiveCollectionLinkToken(ctx, req.CollectionID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}

	if canJoin := collectionLinkToken.CanJoin(); canJoin != nil {
		return stacktrace.Propagate(ente.ErrBadRequest, "can not join collection: %s", canJoin.Error())
	}
	accessToken := auth.GetAccessToken(ctx)
	if collectionLinkToken.Token != accessToken {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "token doesn't match collection")
	}
	if collectionLinkToken.PassHash != nil && *collectionLinkToken.PassHash != "" {
		accessTokenJWT := auth.GetAccessTokenJWT(ctx)
		if passCheckErr := c.CollectionLinkCtrl.ValidateJWTToken(ctx, accessTokenJWT, *collectionLinkToken.PassHash); passCheckErr != nil {
			return stacktrace.Propagate(passCheckErr, "")
		}
	}
	err = c.BillingCtrl.HasActiveSelfOrFamilySubscription(collection.Owner.ID, true)
	if err != nil {
		if !errors.Is(err, ente.ErrSharingDisabledForFreeAccounts) {
			return stacktrace.Propagate(err, "")
		}
	}
	role := ente.VIEWER
	if collectionLinkToken.EnableCollect {
		role = ente.COLLABORATOR
	}
	joinErr := c.CollectionRepo.Share(req.CollectionID, collection.Owner.ID, userID, req.EncryptedKey, role, time.Microseconds())
	if joinErr != nil {
		return stacktrace.Propagate(joinErr, "")
	}
	go c.EmailCtrl.OnLinkJoined(collection.Owner.ID, userID, role)
	return nil
}

func (c *CollectionController) UnShare(ctx *gin.Context, cID int64, fromUserID int64, toUserEmail string) ([]ente.CollectionUser, error) {
	collection, err := c.collectionForShareMutation(cID, fromUserID)
	if err != nil {
		return nil, err
	}

	sharees, err := c.CollectionRepo.GetSharees(cID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	toUserIndex := shareeIndexForEmail(sharees, toUserEmail)
	if toUserIndex == -1 {
		return nil, stacktrace.Propagate(ente.ErrNotFound, "")
	}
	toUserID := sharees[toUserIndex].ID
	if toUserID == fromUserID || toUserID == collection.Owner.ID {
		return nil, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}

	err = c.CollectionRepo.UnShare(cID, toUserID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if err := c.cleanupRevokedShare(ctx, cID, toUserID); err != nil {
		return nil, err
	}
	return slices.Delete(sharees, toUserIndex, toUserIndex+1), nil
}

func (c *CollectionController) BulkUnShare(
	ctx *gin.Context,
	req ente.BulkCollectionUnshareRequest,
) ([]ente.BulkCollectionShareResult, error) {
	// Source is request-scoped; share provenance is not persisted.
	// Automatic callers must exclude shares that should be preserved.
	if err := validateCollectionUnshareBatch(req.CollectionIDs, req.Source); err != nil {
		return nil, err
	}
	fromUserID := auth.GetUserID(ctx.Request.Header)
	if err := validateBulkShareRecipient(fromUserID, req.RecipientUserID); err != nil {
		return nil, err
	}

	results := make([]ente.BulkCollectionShareResult, 0, len(req.CollectionIDs))
	for _, collectionID := range req.CollectionIDs {
		status, err := c.unshareCollectionWithUserID(
			ctx,
			collectionID,
			fromUserID,
			req.RecipientUserID,
			req.Source,
		)
		if err != nil {
			log.WithError(err).WithFields(log.Fields{
				"collection_id":     collectionID,
				"from_user_id":      fromUserID,
				"recipient_user_id": req.RecipientUserID,
			}).Warn("bulk collection unshare failed")
			status = ente.CollectionShareOperationFailed
		}
		results = append(results, ente.BulkCollectionShareResult{
			CollectionID: collectionID,
			Status:       status,
		})
	}
	return results, nil
}

func (c *CollectionController) unshareCollectionWithUserID(
	ctx context.Context,
	collectionID int64,
	fromUserID int64,
	toUserID int64,
	source ente.CollectionShareSource,
) (ente.CollectionShareStatus, error) {
	collection, err := c.collectionForShareMutation(collectionID, fromUserID)
	if err != nil {
		return "", err
	}
	if source == ente.AutomaticShare && fromUserID != collection.Owner.ID {
		return "", stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	if err := validateShareRecipient(fromUserID, collection.Owner.ID, toUserID); err != nil {
		return "", err
	}

	status, err := c.CollectionRepo.UnShareContext(ctx, collectionID, toUserID)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if status == ente.CollectionNotShared {
		return status, nil
	}
	if err := c.cleanupRevokedShare(ctx, collectionID, toUserID); err != nil {
		return "", err
	}
	return status, nil
}

func (c *CollectionController) cleanupRevokedShare(
	ctx context.Context,
	collectionID int64,
	userID int64,
) error {
	if err := c.removeUserSocialActivity(ctx, collectionID, userID); err != nil {
		return err
	}
	if err := c.CastRepo.RevokeForGivenUserAndCollection(ctx, collectionID, userID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	return nil
}

func validateCollectionUnshareBatch(
	collectionIDs []int64,
	source ente.CollectionShareSource,
) error {
	if !source.IsValid() || len(collectionIDs) == 0 {
		return stacktrace.Propagate(ente.ErrBadRequest, "")
	}
	if len(collectionIDs) > ente.MaxCollectionShareBatchSize {
		return stacktrace.Propagate(ente.ErrBatchSizeTooLarge, "")
	}
	seen := make(map[int64]struct{}, len(collectionIDs))
	for _, collectionID := range collectionIDs {
		if _, exists := seen[collectionID]; exists {
			return stacktrace.Propagate(ente.ErrBadRequest, "duplicate collection ID %d", collectionID)
		}
		seen[collectionID] = struct{}{}
	}
	return nil
}

func shareeIndexForEmail(sharees []ente.CollectionUser, targetEmail string) int {
	targetEmail = emailUtil.NormalizeEmail(targetEmail)
	return slices.IndexFunc(sharees, func(sharee ente.CollectionUser) bool {
		return emailUtil.NormalizeEmail(sharee.Email) == targetEmail
	})
}

func (c *CollectionController) Leave(ctx *gin.Context, cID int64) error {
	userID := auth.GetUserID(ctx.Request.Header)
	collection, err := c.CollectionRepo.Get(cID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if userID == collection.Owner.ID {
		return stacktrace.Propagate(ente.ErrPermissionDenied, "can not leave collection owned by self")
	}
	sharedCollectionIDs, err := c.CollectionRepo.GetCollectionIDsSharedWithUser(userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if !slices.Contains(sharedCollectionIDs, cID) {
		return nil
	}
	err = c.CastRepo.RevokeForGivenUserAndCollection(ctx, cID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	err = c.CollectionRepo.UnShare(cID, userID)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if err := c.removeUserSocialActivity(ctx, cID, userID); err != nil {
		return err
	}
	return nil
}

func (c *CollectionController) UpdateShareeMagicMetadata(ctx *gin.Context, req ente.UpdateCollectionMagicMetadata) error {
	actorUserId := auth.GetUserID(ctx.Request.Header)
	resp, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: req.ID,
		ActorUserID:  actorUserId,
	})
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	if resp.Collection.Owner.ID == actorUserId {
		return stacktrace.Propagate(ente.NewBadRequestWithMessage("owner can not update sharee magic metadata"), "")
	}
	err = c.CollectionRepo.UpdateShareeMetadata(req.ID, resp.Collection.Owner.ID, actorUserId, req.MagicMetadata, time.Microseconds())
	if err != nil {
		return stacktrace.Propagate(err, "failed to update sharee magic metadata")
	}
	return nil
}

func (c *CollectionController) ShareURL(ctx *gin.Context, userID int64, req ente.CreatePublicAccessTokenRequest) (
	ente.PublicURL, error) {
	collection, err := c.CollectionRepo.Get(req.CollectionID)
	if err != nil {
		return ente.PublicURL{}, stacktrace.Propagate(err, "")
	}
	if !collection.AllowSharing() {
		return ente.PublicURL{}, stacktrace.Propagate(ente.ErrBadRequest, "sharing %s is not allowed", collection.Type)
	}
	if userID != collection.Owner.ID {
		return ente.PublicURL{}, stacktrace.Propagate(ente.ErrPermissionDenied, "")
	}
	valTrue := true
	if req.EnableJoin == nil {
		req.EnableJoin = &valTrue
	}
	err = c.BillingCtrl.HasActiveSelfOrFamilySubscription(userID, true)
	if err != nil {
		if !errors.Is(err, ente.ErrSharingDisabledForFreeAccounts) {
			return ente.PublicURL{}, stacktrace.Propagate(err, "")
		}
		req.DeviceLimit = public.FreeUserDeviceLimit
	}
	response, err := c.CollectionLinkCtrl.CreateLink(ctx, req)
	if err != nil {
		return ente.PublicURL{}, stacktrace.Propagate(err, "")
	}
	return response, nil
}

func (c *CollectionController) UpdateShareURL(
	ctx *gin.Context,
	userID int64,
	req ente.UpdatePublicAccessTokenRequest,
) (*ente.PublicURL, error) {
	if err := req.Validate(); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	if err := c.verifyOwnership(req.CollectionID, userID); err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	err := c.BillingCtrl.HasActiveSelfOrFamilySubscription(userID, true)
	if err != nil {
		if errors.Is(err, ente.ErrSharingDisabledForFreeAccounts) {
			if req.DeviceLimit != nil && *req.DeviceLimit != public.FreeUserDeviceLimit {
				return nil, stacktrace.Propagate(&ente.ErrLinkEditNotAllowed, "")
			}
		} else {
			return nil, stacktrace.Propagate(err, "")
		}
	}
	response, err := c.CollectionLinkCtrl.UpdateSharedUrl(ctx, req)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return &response, nil
}

func (c *CollectionController) DisableSharedURL(ctx context.Context, userID int64, cID int64) error {
	if err := c.verifyOwnership(cID, userID); err != nil {
		return stacktrace.Propagate(err, "")
	}
	err := c.CollectionLinkCtrl.Disable(ctx, cID)
	return stacktrace.Propagate(err, "")
}

func (c *CollectionController) GetSharees(ctx *gin.Context, cID int64, userID int64) ([]ente.CollectionUser, error) {
	_, err := c.AccessCtrl.GetCollection(ctx, &access.GetCollectionParams{
		CollectionID: cID,
		ActorUserID:  userID,
	})
	if err != nil {
		return nil, stacktrace.Propagate(err, "Access check failed")
	}
	sharees, err := c.CollectionRepo.GetSharees(cID)
	if err != nil {
		return nil, stacktrace.Propagate(err, "")
	}
	return sharees, nil
}

func (c *CollectionController) GetPublicDiff(ctx *gin.Context, sinceTime int64) ([]ente.File, bool, error) {
	accessContext := auth.MustGetPublicAccessContext(ctx)
	reqContextLogger := log.WithFields(log.Fields{
		"public_id":     accessContext.ID,
		"collection_id": accessContext.CollectionID,
		"since_time":    sinceTime,
		"req_id":        requestid.Get(ctx),
	})
	diff, hasMore, err := c.getDiff(accessContext.CollectionID, sinceTime, CollectionDiffLimit, reqContextLogger)
	if err != nil {
		return nil, false, stacktrace.Propagate(err, "")
	}
	// Don't expose private metadata in a public diff.
	for idx := range diff {
		if diff[idx].MagicMetadata != nil {
			diff[idx].MagicMetadata = nil
		}
		// For public diffs, treat action markers as deleted and strip action details
		if diff[idx].Action != nil && !diff[idx].IsDeleted {
			if *diff[idx].Action == ente.ActionRemove || *diff[idx].Action == ente.ActionDeleteSuggested {
				diff[idx].IsDeleted = true
			}
		}
		diff[idx].Action = nil
		diff[idx].ActionUserID = nil
		if diff[idx].Metadata.EncryptedData == "-" && !diff[idx].IsDeleted {
			// "-" marks a deleted file whose collection entry is stale.
			reqContextLogger.WithFields(log.Fields{
				"file_id":    diff[idx].ID,
				"updated_at": diff[idx].UpdationTime,
			}).Warning("stale collection_file found")
			diff[idx].IsDeleted = true
		}
	}
	return diff, hasMore, nil
}
