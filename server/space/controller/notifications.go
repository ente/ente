package controller

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"
	util "github.com/ente/museum/pkg/utils"
	"github.com/ente/museum/space/repo"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
	"github.com/ulule/limiter/v3"
)

const (
	spaceActivityPostCreated     = "post_created"
	spaceActivityPostLiked       = "post_liked"
	spaceActivityPostReplied     = "post_replied"
	spaceActivityMessageSent     = "message_sent"
	spaceActivityMessageLiked    = "message_liked"
	spaceActivityFriendAdded     = "friend_added"
	spaceActivityFriendRequested = "friend_requested"
	spaceWebPushSendRate         = "50-H"
	spaceWebPushTTLSeconds       = 24 * 60 * 60
	// Firefox Android's FCM bridge rejects encrypted records larger than 2744 bytes.
	spaceWebPushRecordSize  = 2744
	spaceWebPushSendTimeout = 30 * time.Second
	spaceWebPushConcurrency = 10
)

var sendSpaceWebPush = webpush.SendNotificationWithContext

type SpaceActivityActor struct {
	UserID  int64
	SpaceID string
	Slug    string
}

func spaceActivityActor(space *repo.SpaceRecord) SpaceActivityActor {
	return SpaceActivityActor{
		UserID:  space.OwnerID,
		SpaceID: space.SpaceID,
		Slug:    space.SpaceSlug,
	}
}

type SpaceActivityNotifier interface {
	OnSpacePostCreated(actor SpaceActivityActor)
	OnSpacePostLiked(actor SpaceActivityActor, recipientUserID int64)
	OnSpacePostReplied(actor SpaceActivityActor, recipientUserID int64)
	OnSpaceMessageSent(actor SpaceActivityActor, recipientUserID int64)
	OnSpaceMessageLiked(actor SpaceActivityActor, recipientUserID int64)
	OnSpaceFriendAdded(actor SpaceActivityActor, recipientUserID int64)
	OnSpaceFriendRequested(actor SpaceActivityActor, recipientUserID int64)
}

type SpaceWebPushSender struct {
	webPushRepo *repo.WebPushRepository
	options     *webpush.Options
	sendLimiter *limiter.Limiter
	sendSlots   chan struct{}
}

type spaceWebPushPayload struct {
	Title    string `json:"title"`
	Body     string `json:"body"`
	Action   string `json:"action,omitempty"`
	URL      string `json:"url,omitempty"`
	TargetID string `json:"targetId,omitempty"`
}

func NewSpaceWebPushSender(
	webPushRepo *repo.WebPushRepository,
	config *SpaceWebPushConfig,
) *SpaceWebPushSender {
	sender := &SpaceWebPushSender{
		webPushRepo: webPushRepo,
		sendLimiter: util.NewRateLimiter(spaceWebPushSendRate),
		sendSlots:   make(chan struct{}, spaceWebPushConcurrency),
	}
	if config != nil {
		sender.options = &webpush.Options{
			HTTPClient:      newSpaceWebPushHTTPClient(),
			RecordSize:      spaceWebPushRecordSize,
			Subscriber:      config.subscriber,
			TTL:             spaceWebPushTTLSeconds,
			Urgency:         webpush.UrgencyNormal,
			VAPIDPublicKey:  config.publicKey,
			VAPIDPrivateKey: config.privateKey,
		}
	}
	return sender
}

func (n *SpaceWebPushSender) OnSpacePostCreated(actor SpaceActivityActor) {
	if !n.available() {
		return
	}
	subscriptions, err := n.webPushRepo.ListPostSubscriptions(
		context.Background(),
		actor.SpaceID,
	)
	if err != nil {
		log.WithField("event", spaceActivityPostCreated).WithError(err).
			Error("Failed to list Space web push subscriptions")
		return
	}
	n.send(
		actor,
		"posted a new photo",
		"Check it out",
		spaceActivityPostCreated,
		"/app",
		subscriptions,
	)
}

func (n *SpaceWebPushSender) OnSpacePostLiked(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(actor, "liked your post", "", spaceActivityPostLiked, conversationURL(actor.SpaceID), recipientUserID)
}

func (n *SpaceWebPushSender) OnSpacePostReplied(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(actor, "replied to your post", "Check it out", spaceActivityPostReplied, conversationURL(actor.SpaceID), recipientUserID)
}

func (n *SpaceWebPushSender) OnSpaceMessageSent(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(actor, "sent you a message", "Check it out", spaceActivityMessageSent, conversationURL(actor.SpaceID), recipientUserID)
}

func (n *SpaceWebPushSender) OnSpaceMessageLiked(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(actor, "liked a message", "View conversation", spaceActivityMessageLiked, conversationURL(actor.SpaceID), recipientUserID)
}

func (n *SpaceWebPushSender) OnSpaceFriendAdded(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(
		actor,
		"is now your friend",
		"Say hi to "+spaceActivityActorLabel(actor.Slug),
		spaceActivityFriendAdded,
		conversationURL(actor.SpaceID),
		recipientUserID,
	)
}

func (n *SpaceWebPushSender) OnSpaceFriendRequested(actor SpaceActivityActor, recipientUserID int64) {
	n.sendAccountActivity(actor, "sent you a friend request", "Review request", spaceActivityFriendRequested, "/app/messages", recipientUserID)
}

func (n *SpaceWebPushSender) sendAccountActivity(
	actor SpaceActivityActor,
	activity, action, event, destination string,
	recipientUserID int64,
) {
	if !n.available() || recipientUserID <= 0 {
		return
	}
	subscriptions, err := n.webPushRepo.ListActiveAccountSubscriptions(
		context.Background(),
		recipientUserID,
	)
	if err != nil {
		log.WithField("event", event).WithError(err).
			Error("Failed to list Space web push subscriptions")
		return
	}
	n.send(actor, activity, action, event, destination, subscriptions)
}

func (n *SpaceWebPushSender) available() bool {
	return n.webPushRepo != nil &&
		n.options != nil &&
		!viper.GetBool("internal.silent")
}

func (n *SpaceWebPushSender) send(
	actor SpaceActivityActor,
	activity, action, event, destination string,
	subscriptions []repo.SpaceWebPushSubscriptionRecord,
) {
	subscriptions = deduplicateSpaceWebPushSubscriptions(subscriptions)
	if len(subscriptions) == 0 {
		return
	}
	limitContext, err := n.sendLimiter.Get(
		context.Background(),
		strconv.FormatInt(actor.UserID, 10),
	)
	if err != nil {
		log.WithField("actor_user_id", actor.UserID).WithError(err).
			Error("Failed to check Space web push rate limit")
		return
	}
	if limitContext.Reached {
		return
	}
	if limitContext.Remaining == 0 {
		log.WithFields(log.Fields{
			"actor_user_id": actor.UserID,
			"reset_at":      limitContext.Reset,
		}).Warn("Space web push rate limit reached")
	}

	var waitGroup sync.WaitGroup
	for _, subscription := range subscriptions {
		payload := spaceWebPushPayload{
			Title:  "Ente Space",
			Body:   fmt.Sprintf("%s %s", spaceActivityActorLabel(actor.Slug), activity),
			Action: action,
		}
		if subscription.Public {
			payload.TargetID = subscription.TargetID
		} else {
			payload.URL = destination
		}
		encoded, err := json.Marshal(payload)
		if err != nil {
			log.WithField("event", event).WithError(err).
				Error("Failed to encode Space web push payload")
			continue
		}

		waitGroup.Add(1)
		n.sendSlots <- struct{}{}
		go func(subscription repo.SpaceWebPushSubscriptionRecord, payload []byte) {
			defer waitGroup.Done()
			defer func() { <-n.sendSlots }()
			n.sendSubscription(event, payload, subscription)
		}(subscription, encoded)
	}
	waitGroup.Wait()
}

func (n *SpaceWebPushSender) sendSubscription(
	event string,
	payload []byte,
	subscription repo.SpaceWebPushSubscriptionRecord,
) {
	ctx, cancel := context.WithTimeout(context.Background(), spaceWebPushSendTimeout)
	defer cancel()
	response, err := sendSpaceWebPush(ctx, payload, &webpush.Subscription{
		Endpoint: subscription.Endpoint,
		Keys: webpush.Keys{
			P256dh: subscription.P256dh,
			Auth:   subscription.Auth,
		},
	}, n.options)
	if err != nil {
		log.WithFields(log.Fields{
			"event":     event,
			"target_id": subscription.TargetID,
		}).WithError(err).Error("Failed to send Space web push")
		return
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotFound || response.StatusCode == http.StatusGone {
		if err := n.webPushRepo.DeleteEndpoint(context.Background(), subscription.Endpoint); err != nil {
			log.WithField("event", event).WithError(err).
				Error("Failed to delete expired Space web push subscription")
		}
		return
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		log.WithFields(log.Fields{
			"event":     event,
			"status":    response.StatusCode,
			"target_id": subscription.TargetID,
		}).Warn("Space web push provider rejected notification")
	}
}

func deduplicateSpaceWebPushSubscriptions(
	subscriptions []repo.SpaceWebPushSubscriptionRecord,
) []repo.SpaceWebPushSubscriptionRecord {
	byEndpoint := make(map[string]repo.SpaceWebPushSubscriptionRecord, len(subscriptions))
	order := make([]string, 0, len(subscriptions))
	for _, subscription := range subscriptions {
		existing, found := byEndpoint[subscription.Endpoint]
		if !found {
			order = append(order, subscription.Endpoint)
			byEndpoint[subscription.Endpoint] = subscription
			continue
		}
		if existing.Public && !subscription.Public {
			byEndpoint[subscription.Endpoint] = subscription
		}
	}
	result := make([]repo.SpaceWebPushSubscriptionRecord, 0, len(order))
	for _, endpoint := range order {
		result = append(result, byEndpoint[endpoint])
	}
	return result
}

func spaceActivityActorLabel(actorSlug string) string {
	actorSlug = strings.TrimSpace(actorSlug)
	if actorSlug == "" {
		return "A friend"
	}
	return "@" + actorSlug
}

func conversationURL(spaceID string) string {
	return "/app/messages/" + url.PathEscape(spaceID)
}

func spaceAppURL() string {
	origin := strings.TrimRight(strings.TrimSpace(viper.GetString("apps.space")), "/")
	if origin == "" {
		origin = "https://ente.space"
	}
	return origin + "/app"
}

func newSpaceWebPushHTTPClient() *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = func(
		ctx context.Context,
		network, address string,
	) (net.Conn, error) {
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return nil, err
		}
		addresses, err := net.DefaultResolver.LookupIP(ctx, "ip", host)
		if err != nil {
			return nil, err
		}
		for _, address := range addresses {
			if !isPublicWebPushAddress(address) {
				return nil, errors.New("web push endpoint resolved to a non-public address")
			}
		}
		for _, address := range addresses {
			connection, err := dialer.DialContext(
				ctx,
				network,
				net.JoinHostPort(address.String(), port),
			)
			if err == nil {
				return connection, nil
			}
		}
		return nil, errors.New("failed to connect to web push endpoint")
	}
	return &http.Client{
		Transport: transport,
		Timeout:   spaceWebPushSendTimeout,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return errors.New("web push endpoint redirects are not allowed")
		},
	}
}

var reservedWebPushNetworks = mustParseNetworks(
	"0.0.0.0/8",
	"100.64.0.0/10",
	"192.0.0.0/24",
	"192.0.2.0/24",
	"192.88.99.0/24",
	"198.18.0.0/15",
	"198.51.100.0/24",
	"203.0.113.0/24",
	"240.0.0.0/4",
	"64:ff9b::/96",
	"64:ff9b:1::/48",
	"100::/64",
	"2001::/23",
	"2001:db8::/32",
	"2002::/16",
)

func mustParseNetworks(values ...string) []*net.IPNet {
	networks := make([]*net.IPNet, 0, len(values))
	for _, value := range values {
		_, network, err := net.ParseCIDR(value)
		if err != nil {
			panic(err)
		}
		networks = append(networks, network)
	}
	return networks
}

func isPublicWebPushAddress(address net.IP) bool {
	if !address.IsGlobalUnicast() ||
		address.IsPrivate() ||
		address.IsLoopback() ||
		address.IsLinkLocalUnicast() {
		return false
	}
	for _, network := range reservedWebPushNetworks {
		if network.Contains(address) {
			return false
		}
	}
	return true
}
