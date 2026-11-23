package api

import (
	"testing"

	"github.com/ente/museum/pkg/external/listmonk"
)

func TestProductMailPreference(t *testing.T) {
	const newsletterListID = 18
	newsletter := func(status, optIn string) []listmonk.SubscriberList {
		return []listmonk.SubscriberList{{ID: newsletterListID, Status: status, OptIn: optIn}}
	}
	for _, tt := range []struct {
		name, status          string
		lists                 []listmonk.SubscriberList
		wantSubscribed, known bool
	}{
		{
			name: "confirmed double opt-in", status: "enabled",
			lists: newsletter("confirmed", "double"), wantSubscribed: true, known: true,
		},
		{
			name: "single opt-in needs no confirmation", status: "enabled",
			lists: newsletter("unconfirmed", "single"), wantSubscribed: true, known: true,
		},
		{
			name: "unconfirmed double opt-in", status: "enabled",
			lists: newsletter("unconfirmed", "double"),
		},
		{
			name: "unsubscribed from newsletter", status: "enabled",
			lists: newsletter("unsubscribed", ""), known: true,
		},
		{
			name: "blocklist overrides confirmation", status: "blocklisted",
			lists: newsletter("confirmed", ""), known: true,
		},
		{name: "blocklisted without a list", status: "blocklisted", known: true},
		{
			name: "subscribed to another list", status: "enabled",
			lists: []listmonk.SubscriberList{{ID: newsletterListID + 1, Status: "confirmed"}},
		},
		{name: "no list membership", status: "enabled"},
		{
			name: "unknown subscriber status", status: "unknown",
			lists: newsletter("confirmed", ""),
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			subscriber := listmonk.Subscriber{Status: tt.status, Lists: tt.lists}
			subscribed, known := productMailPreference(subscriber, newsletterListID)
			if subscribed != tt.wantSubscribed || known != tt.known {
				t.Fatalf("preference = (%t, %t), want (%t, %t)", subscribed, known, tt.wantSubscribed, tt.known)
			}
		})
	}
}
