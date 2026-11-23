package listmonk

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
)

func TestListSubscribersPreservesPreferencesAndLegacyIDs(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/api/subscribers" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		query := r.URL.Query()
		if query.Get("order") != "ASC" || query.Get("page") != "2" || query.Get("per_page") != "3" {
			t.Errorf("unexpected pagination: %s", r.URL.RawQuery)
		}
		_, _ = io.WriteString(w, `{"data":{"total":7,"page":2,"per_page":3,"results":[
			{"email":"member@example.test","status":"enabled","lists":[{"id":18,"subscription_status":"unsubscribed","optin":"single"}]},
			{"email":"legacy@example.test","status":"blocklisted","list_ids":[19]},
			{"email":"ids-only@example.test","lists":[20]}
		]}}`)
	}))
	defer server.Close()

	got, err := ListSubscribers(server.URL+"/api/subscribers?order=ASC", "user", "pass", 2, 3)
	if err != nil {
		t.Fatal(err)
	}
	want := SubscribersPage{
		Total: 7, Page: 2, PerPage: 3,
		Results: []Subscriber{
			{
				Email: "member@example.test", Status: "enabled", ListIDs: []int{18},
				Lists: []SubscriberList{{ID: 18, Status: "unsubscribed", OptIn: "single"}},
			},
			{Email: "legacy@example.test", Status: "blocklisted", ListIDs: []int{19}},
			{Email: "ids-only@example.test", ListIDs: []int{20}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("subscriber page = %+v, want %+v", got, want)
	}
}

func TestGetSubscriberIDReturnsStatusError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte("auth failed"))
	}))
	defer server.Close()

	_, err := GetSubscriberID(server.URL, "user", "pass", "missing@example.com")
	if err == nil {
		t.Fatal("expected error")
	}
	if errors.Is(err, ErrSubscriberNotFound) {
		t.Fatal("status failure was reported as subscriber not found")
	}
	if !strings.Contains(err.Error(), "status 401") {
		t.Fatalf("err = %v, want status 401", err)
	}
}
