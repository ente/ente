package email

import (
	"context"
	"slices"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/external/postmark"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/email"
	log "github.com/sirupsen/logrus"
)

type SubscriptionSender struct {
	Subscriptions       *repo.EmailSubscriptionRepository
	Users               *repo.UserRepository
	NotificationHistory *repo.NotificationHistoryRepository
	Links               *email.UnsubscribeLinks
	Postmark            postmark.Client
	Streams             map[ente.EmailType]string
}

func (s *SubscriptionSender) Configured(emailType ente.EmailType) bool {
	return s != nil && s.Links != nil && s.Postmark.ServerToken != "" &&
		s.Postmark.From != "" && s.Streams[emailType] != ""
}

func (s *SubscriptionSender) Send(ctx context.Context, userIDs []int64, emailType ente.EmailType, notificationID, subject, templateName string) {
	logger := log.WithField("notification", notificationID)
	for batch := range slices.Chunk(userIDs, postmark.MaxBatchSize) {
		messages := make([]postmark.Message, 0, len(batch))
		recipientIDs := make([]int64, 0, len(batch))
		for _, userID := range batch {
			recipientLogger := logger.WithField("user_id", userID)
			user, err := s.Users.Get(userID)
			if err != nil {
				recipientLogger.WithError(err).Error("Could not fetch email recipient")
				continue
			}
			unsubscribeURL := s.Links.URL(userID, emailType)
			body, err := email.RenderMailBodyWithBase("base_v2.html", templateName, map[string]interface{}{
				"UnsubscribeURL": unsubscribeURL,
			})
			if err != nil {
				logger.WithError(err).Error("Could not render subscription email")
				return
			}
			messages = append(messages, postmark.Message{
				To:            user.Email,
				Subject:       subject,
				HTMLBody:      body,
				MessageStream: s.Streams[emailType],
				TrackLinks:    "None",
				Headers: []postmark.Header{
					{Name: "List-Unsubscribe", Value: "<" + unsubscribeURL + ">"},
					{Name: "List-Unsubscribe-Post", Value: "List-Unsubscribe=One-Click"},
				},
			})
			recipientIDs = append(recipientIDs, userID)
		}
		if len(messages) == 0 {
			continue
		}
		subscribed, err := s.Subscriptions.SubscribedUserIDs(ctx, recipientIDs, emailType)
		if err != nil {
			logger.WithError(err).Error("Could not check email subscriptions")
			continue
		}
		filteredMessages := messages[:0]
		filteredIDs := recipientIDs[:0]
		for i, userID := range recipientIDs {
			if !subscribed[userID] {
				continue
			}
			if err := s.NotificationHistory.SetLastNotificationTimeToNow(userID, notificationID); err != nil {
				logger.WithField("user_id", userID).WithError(err).Error("Could not record email attempt")
				continue
			}
			filteredMessages = append(filteredMessages, messages[i])
			filteredIDs = append(filteredIDs, userID)
		}
		if len(filteredMessages) == 0 {
			continue
		}
		results, err := s.Postmark.SendBatch(ctx, filteredMessages)
		if err != nil {
			logger.WithError(err).WithField("recipient_count", len(filteredMessages)).Error("Postmark email handoff failed")
			continue
		}
		for i, code := range results {
			if code != 0 {
				logger.WithFields(log.Fields{"user_id": filteredIDs[i], "postmark_error_code": code}).Warn("Postmark rejected email")
			}
		}
	}
}
