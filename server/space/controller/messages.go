package controller

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/space/models"
	"github.com/ente/museum/space/repo"
	"github.com/ente/stacktrace"
)

const (
	spaceMessageKindRegular     = "regular"
	spaceMessageKindPostReply   = "post_reply"
	spaceMessageKindPostLike    = "post_like"
	spaceMessageKindFriendAdded = "friend_added"

	maxSpaceMessageCipherEncodedBytes = 8 * 1024
	maxSpaceMessageCipherDecodedBytes = 6 * 1024
	maxSpaceMessageKeyEncodedBytes    = 1024
	maxSpaceMessageKeyDecodedBytes    = 768
	spaceMessageIDPrefix              = "wmsg_"
	spaceMessageIDSuffixLength        = 22
)

type MessagesController struct {
	MessagesRepo    *repo.MessagesRepository
	PostsRepo       *repo.PostsRepository
	SpacesRepo      *repo.SpacesRepository
	FriendsRepo     *repo.FriendsRepository
	ReadMarkersRepo *repo.ReadMarkersRepository
	EmailNotifier   SpaceEmailNotifier
	auth            authDeps
}

func (c *MessagesController) Create(ctx context.Context, senderSpace *repo.SpaceRecord, targetSpaceID string, req models.CreateMessageRequest) (*models.MessageResponse, error) {
	messageCipher, senderEncryptedMessageKey, recipientEncryptedMessageKey, err := decodeCreateMessageRequest(req)
	if err != nil {
		return nil, err
	}
	messageID, err := normalizeOptionalMessageID(req.MessageID)
	if err != nil {
		return nil, err
	}
	recipientSpace, err := c.requireFriendMessageTarget(ctx, senderSpace, targetSpaceID)
	if err != nil {
		return nil, err
	}
	replyMessageID, err := c.validateReplyMessage(ctx, req.ReplyMessageID, senderSpace.SpaceID, recipientSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	message, err := c.MessagesRepo.CreateMessage(ctx, repo.CreateSpaceMessageRecord{
		MessageID:                    messageID,
		Kind:                         spaceMessageKindRegular,
		SenderSpaceID:                senderSpace.SpaceID,
		RecipientSpaceID:             recipientSpace.SpaceID,
		MessageCipher:                messageCipher,
		SenderEncryptedMessageKey:    senderEncryptedMessageKey,
		RecipientEncryptedMessageKey: recipientEncryptedMessageKey,
		ReplyMessageID:               replyMessageID,
	})
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), repo.ErrSpaceMessageLimitReached) {
			return nil, ente.NewConflictError("space message limit reached")
		}
		return nil, err
	}
	return toMessageResponse(*message), nil
}

func (c *MessagesController) ReplyToPost(ctx context.Context, senderSpace *repo.SpaceRecord, postID int64, req models.CreateMessageRequest) (*models.MessageResponse, error) {
	messageCipher, senderEncryptedMessageKey, recipientEncryptedMessageKey, err := decodeCreateMessageRequest(req)
	if err != nil {
		return nil, err
	}
	messageID, err := normalizeOptionalMessageID(req.MessageID)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(req.ReplyMessageID) != "" {
		return nil, ente.NewBadRequestWithMessage("replyMessageId is not supported for post replies")
	}
	post, err := c.PostsRepo.GetPost(ctx, postID, senderSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	space, err := c.SpacesRepo.GetSpaceByID(ctx, post.SpaceID)
	if err != nil {
		return nil, err
	}
	if err := c.auth.canViewSpace(ctx, &viewerAuth{UserID: senderSpace.OwnerID, SpaceID: senderSpace.SpaceID}, space); err != nil {
		return nil, err
	}
	if space.OwnerID == senderSpace.OwnerID {
		return nil, ente.NewBadRequestWithMessage("cannot reply to your own post")
	}
	recipientSpace, err := c.requireFriendMessageTarget(ctx, senderSpace, space.SpaceID)
	if err != nil {
		return nil, err
	}
	message, err := c.MessagesRepo.CreateMessage(ctx, repo.CreateSpaceMessageRecord{
		MessageID:                    messageID,
		Kind:                         spaceMessageKindPostReply,
		SenderSpaceID:                senderSpace.SpaceID,
		RecipientSpaceID:             recipientSpace.SpaceID,
		MessageCipher:                messageCipher,
		SenderEncryptedMessageKey:    senderEncryptedMessageKey,
		RecipientEncryptedMessageKey: recipientEncryptedMessageKey,
		ReplyPostID:                  sql.NullInt64{Int64: postID, Valid: true},
	})
	if err != nil {
		if errors.Is(stacktrace.RootCause(err), repo.ErrSpaceMessageLimitReached) {
			return nil, ente.NewConflictError("space message limit reached")
		}
		return nil, err
	}
	if c.EmailNotifier != nil {
		go c.EmailNotifier.OnSpacePostReplied(senderSpace.OwnerID, senderSpace.SpaceSlug, recipientSpace.OwnerID)
	}
	return toMessageResponse(*message), nil
}

func (c *MessagesController) ListConversations(ctx context.Context, viewerSpace *repo.SpaceRecord) (*models.ConversationsResponse, error) {
	friends, err := c.FriendsRepo.ListFriendsForSpace(ctx, viewerSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	pendingRequests, err := c.FriendsRepo.ListFriendRequestsForSpace(ctx, viewerSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	friendResponses := make([]models.SpaceFriendResponse, 0, len(friends))
	friendSpaceIDs := make([]string, 0, len(friends))
	for _, friend := range friends {
		friendResponses = append(friendResponses, models.SpaceFriendResponse{
			Friend:          toActorResponse(friend.Friend, true),
			ShareKeyVersion: friend.ShareKeyVersion,
			CreatedAt:       formatMicros(friend.CreatedAt),
		})
		friendSpaceIDs = append(friendSpaceIDs, friend.Friend.SpaceID)
	}
	summaries, err := c.MessagesRepo.ListLatestChatSummaries(ctx, viewerSpace.SpaceID, friendSpaceIDs)
	if err != nil {
		return nil, err
	}
	chatSummaries := make(map[string]models.ConversationChatSummaryResponse, len(summaries))
	for friendSpaceID, summary := range summaries {
		unreadActivities := make([]models.MessageConversationActivityResponse, 0, len(summary.UnreadActivities))
		for _, activity := range summary.UnreadActivities {
			unreadActivities = append(unreadActivities, toUnreadMessageConversationActivityResponse(activity))
		}
		chatSummaries[friendSpaceID] = models.ConversationChatSummaryResponse{
			LatestActivity:   toMessageConversationActivityResponse(summary.LatestActivity),
			UnreadActivities: unreadActivities,
		}
	}
	requestResponses := make([]models.SpaceFriendRequestResponse, 0, len(pendingRequests))
	for _, request := range pendingRequests {
		requestResponses = append(requestResponses, models.SpaceFriendRequestResponse{
			RequestID: request.RequestID,
			Requester: toActorResponse(request.Requester, true),
			CreatedAt: formatMicros(request.CreatedAt),
		})
	}
	return &models.ConversationsResponse{
		Friends:         friendResponses,
		PendingRequests: requestResponses,
		ChatSummaries:   chatSummaries,
	}, nil
}

func (c *MessagesController) ListThread(ctx context.Context, viewerSpace *repo.SpaceRecord, targetSpaceID string, req models.ListMessageThreadRequest) (*models.MessagePage, error) {
	if strings.TrimSpace(targetSpaceID) == "" {
		return nil, ente.NewBadRequestWithMessage("spaceId is required")
	}
	targetSpace, err := c.SpacesRepo.GetSpaceByID(ctx, strings.TrimSpace(targetSpaceID))
	if err != nil {
		return nil, err
	}
	if err := c.auth.requireActiveSpaceOwner(ctx, targetSpace); err != nil {
		return nil, err
	}
	messages, nextCursor, err := c.MessagesRepo.ListThread(ctx, viewerSpace.SpaceID, strings.TrimSpace(targetSpaceID), req.Cursor, req.Limit)
	if err != nil {
		return nil, err
	}
	items := make([]models.MessageResponse, 0, len(messages))
	for _, message := range messages {
		items = append(items, *toMessageResponse(message))
	}
	return &models.MessagePage{Items: items, NextCursor: nextCursor}, nil
}

func (c *MessagesController) SetLike(ctx context.Context, actorSpace *repo.SpaceRecord, messageID string, like bool) (*models.LikeMessageResponse, error) {
	messageID = strings.TrimSpace(messageID)
	if messageID == "" {
		return nil, ente.NewBadRequestWithMessage("messageId is required")
	}
	message, err := c.MessagesRepo.GetMessage(ctx, messageID, actorSpace.SpaceID)
	if err != nil {
		return nil, err
	}
	if message.IsDeleted {
		return nil, ente.NewBadRequestWithMessage("cannot like a deleted message")
	}
	if message.Kind != spaceMessageKindRegular && message.Kind != spaceMessageKindPostReply {
		return nil, ente.NewBadRequestWithMessage("cannot like this message")
	}
	if message.RecipientSpaceID != actorSpace.SpaceID {
		return nil, ente.NewBadRequestWithMessage("only the recipient can like a message")
	}
	otherSpaceID := message.SenderSpaceID
	if _, err := c.FriendsRepo.GetShareForFriendAndSpace(ctx, actorSpace.SpaceID, otherSpaceID); err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrPermissionDenied
		}
		return nil, err
	}
	if err := c.MessagesRepo.SetLike(ctx, messageID, actorSpace.SpaceID, like); err != nil {
		return nil, err
	}
	return &models.LikeMessageResponse{Liked: like}, nil
}

func (c *MessagesController) Delete(ctx context.Context, senderSpace *repo.SpaceRecord, messageID string) error {
	messageID = strings.TrimSpace(messageID)
	if messageID == "" {
		return ente.NewBadRequestWithMessage("messageId is required")
	}
	message, err := c.MessagesRepo.GetMessage(ctx, messageID, senderSpace.SpaceID)
	if err != nil {
		return err
	}
	if message.SenderSpaceID != senderSpace.SpaceID {
		return ente.ErrPermissionDenied
	}
	if message.Kind != spaceMessageKindRegular && message.Kind != spaceMessageKindPostReply {
		return ente.NewBadRequestWithMessage("cannot delete this message")
	}
	if _, err := c.FriendsRepo.GetShareForFriendAndSpace(ctx, senderSpace.SpaceID, message.RecipientSpaceID); err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return ente.ErrPermissionDenied
		}
		return err
	}
	if message.IsDeleted {
		return nil
	}
	return c.MessagesRepo.DeleteMessage(ctx, messageID, senderSpace.SpaceID)
}

func (c *MessagesController) requireFriendMessageTarget(ctx context.Context, senderSpace *repo.SpaceRecord, targetSpaceID string) (*repo.SpaceRecord, error) {
	if senderSpace == nil || strings.TrimSpace(senderSpace.SpaceID) == "" {
		return nil, ente.NewBadRequestWithMessage("spaceId is required")
	}
	targetSpaceID = strings.TrimSpace(targetSpaceID)
	if targetSpaceID == "" {
		return nil, ente.NewBadRequestWithMessage("spaceId is required")
	}
	recipientSpace, err := c.SpacesRepo.GetSpaceByID(ctx, targetSpaceID)
	if err != nil {
		return nil, err
	}
	if recipientSpace.OwnerID == senderSpace.OwnerID {
		return nil, ente.NewBadRequestWithMessage("cannot message your own space")
	}
	if _, err := c.FriendsRepo.GetShareForFriendAndSpace(ctx, senderSpace.SpaceID, recipientSpace.SpaceID); err != nil {
		if errors.Is(stacktrace.RootCause(err), sql.ErrNoRows) {
			return nil, ente.ErrPermissionDenied
		}
		return nil, err
	}
	return recipientSpace, nil
}

func (c *MessagesController) validateReplyMessage(ctx context.Context, replyMessageID, senderSpaceID, recipientSpaceID string) (sql.NullString, error) {
	replyMessageID = strings.TrimSpace(replyMessageID)
	if replyMessageID == "" {
		return sql.NullString{}, nil
	}
	parent, err := c.MessagesRepo.GetMessage(ctx, replyMessageID, senderSpaceID)
	if err != nil {
		return sql.NullString{}, err
	}
	if parent.IsDeleted {
		return sql.NullString{}, ente.NewBadRequestWithMessage("cannot reply to a deleted message")
	}
	if !sameMessageThread(parent, senderSpaceID, recipientSpaceID) {
		return sql.NullString{}, ente.ErrPermissionDenied
	}
	return sql.NullString{String: replyMessageID, Valid: true}, nil
}

func sameMessageThread(message *repo.SpaceMessageRecord, firstSpaceID, secondSpaceID string) bool {
	return (message.SenderSpaceID == firstSpaceID && message.RecipientSpaceID == secondSpaceID) ||
		(message.SenderSpaceID == secondSpaceID && message.RecipientSpaceID == firstSpaceID)
}

func normalizeOptionalMessageID(messageID string) (string, error) {
	if messageID == "" {
		return "", nil
	}
	if len(messageID) != len(spaceMessageIDPrefix)+spaceMessageIDSuffixLength || !strings.HasPrefix(messageID, spaceMessageIDPrefix) {
		return "", ente.NewBadRequestWithMessage("messageId is invalid")
	}
	for i := len(spaceMessageIDPrefix); i < len(messageID); i++ {
		c := messageID[i]
		if !((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
			return "", ente.NewBadRequestWithMessage("messageId is invalid")
		}
	}
	return messageID, nil
}

func decodeCreateMessageRequest(req models.CreateMessageRequest) ([]byte, []byte, []byte, error) {
	if strings.TrimSpace(req.MessageCipher) == "" ||
		strings.TrimSpace(req.SenderEncryptedMessageKey) == "" ||
		strings.TrimSpace(req.RecipientEncryptedMessageKey) == "" {
		return nil, nil, nil, ente.NewBadRequestWithMessage("messageCipher and encrypted message keys are required")
	}
	messageCipher, err := decodeEncodedSpaceField("messageCipher", req.MessageCipher, maxSpaceMessageCipherEncodedBytes, maxSpaceMessageCipherDecodedBytes)
	if err != nil {
		return nil, nil, nil, err
	}
	senderEncryptedMessageKey, err := decodeEncodedSpaceField("senderEncryptedMessageKey", req.SenderEncryptedMessageKey, maxSpaceMessageKeyEncodedBytes, maxSpaceMessageKeyDecodedBytes)
	if err != nil {
		return nil, nil, nil, err
	}
	recipientEncryptedMessageKey, err := decodeEncodedSpaceField("recipientEncryptedMessageKey", req.RecipientEncryptedMessageKey, maxSpaceMessageKeyEncodedBytes, maxSpaceMessageKeyDecodedBytes)
	if err != nil {
		return nil, nil, nil, err
	}
	return messageCipher, senderEncryptedMessageKey, recipientEncryptedMessageKey, nil
}

func toMessageResponse(message repo.SpaceMessageRecord) *models.MessageResponse {
	resp := &models.MessageResponse{
		MessageID:           message.MessageID,
		Kind:                message.Kind,
		SenderSpaceID:       message.SenderSpaceID,
		RecipientSpaceID:    message.RecipientSpaceID,
		MessageCipher:       encodeSpaceField(message.MessageCipher),
		EncryptedMessageKey: encodeSpaceField(message.EncryptedMessageKey),
		Text:                message.Text,
		Liked:               message.Liked,
		ViewerLiked:         message.ViewerLiked,
		IsDeleted:           message.IsDeleted,
		CreatedAt:           formatMicros(message.CreatedAt),
		UpdatedAt:           formatMicros(message.UpdatedAt),
	}
	if message.ReplyPostID.Valid {
		replyPostID := message.ReplyPostID.Int64
		resp.ReplyPostID = &replyPostID
	}
	if message.ReplyMessageID.Valid {
		replyMessageID := message.ReplyMessageID.String
		resp.ReplyMessageID = &replyMessageID
	}
	return resp
}

func toMessageConversationActivityMetadataResponse(activity repo.SpaceMessageConversationActivityRecord) models.MessageConversationActivityResponse {
	resp := models.MessageConversationActivityResponse{
		ID:        activity.ID,
		Type:      activity.Type,
		CreatedAt: formatMicros(activity.CreatedAt),
		Outgoing:  activity.Outgoing,
	}
	if activity.MessageID.Valid {
		messageID := activity.MessageID.String
		resp.MessageID = &messageID
	}
	if activity.PostID.Valid {
		postID := activity.PostID.Int64
		resp.PostID = &postID
		if activity.PostSpaceID.Valid {
			resp.PostSpaceID = activity.PostSpaceID.String
		}
	}
	return resp
}

func toMessageConversationActivityResponse(activity repo.SpaceMessageConversationActivityRecord) models.MessageConversationActivityResponse {
	resp := toMessageConversationActivityMetadataResponse(activity)
	if activity.Kind.Valid {
		resp.Kind = activity.Kind.String
	}
	if activity.SenderSpaceID.Valid {
		resp.SenderSpaceID = activity.SenderSpaceID.String
	}
	if activity.RecipientSpaceID.Valid {
		resp.RecipientSpaceID = activity.RecipientSpaceID.String
	}
	if len(activity.MessageCipher) > 0 {
		resp.MessageCipher = encodeSpaceField(activity.MessageCipher)
	}
	if len(activity.EncryptedMessageKey) > 0 {
		resp.EncryptedMessageKey = encodeSpaceField(activity.EncryptedMessageKey)
	}
	if activity.ReplyMessageID.Valid {
		replyMessageID := activity.ReplyMessageID.String
		resp.ReplyMessageID = &replyMessageID
	}
	return resp
}

func toUnreadMessageConversationActivityResponse(activity repo.SpaceMessageConversationActivityRecord) models.MessageConversationActivityResponse {
	return toMessageConversationActivityMetadataResponse(activity)
}
