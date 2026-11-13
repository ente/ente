package controller

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/museum/pkg/external/listmonk"
)

func TestListmonkUnsubscribeDoesNotNotifyWhenSubscriberIsMissing(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"data":{"results":[]}}`))
	}))
	defer server.Close()

	c := &MailingListsController{
		listmonkCredentials: listmonk.Credentials{
			BaseURL:  server.URL,
			Username: "user",
			Password: "pass",
		},
	}

	err := c.listmonkUnsubscribe("missing@example.com")
	if !errors.Is(err, listmonk.ErrSubscriberNotFound) {
		t.Fatalf("err = %v, want ErrSubscriberNotFound", err)
	}
}
