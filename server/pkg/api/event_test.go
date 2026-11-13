package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/repo"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func TestCreateEventStoresInstallWithServerMetadata(t *testing.T) {
	handler, db := setupEventHandlerTest(t)
	id := uuid.New().String()

	recorder := performEventRequest(t, "/events", handler.Create, nil, map[string]any{
		"id":    id,
		"event": "install",
		"data": map[string]any{
			"utm_source": "newsletter",
			"app":        "ignored",
			"platform":   "ignored",
		},
	})

	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status code: got %d want %d; body=%s", recorder.Code, http.StatusOK, recorder.Body.String())
	}
	row := fetchEvent(t, db, id, "install")
	if row.data["utm_source"] != "newsletter" ||
		row.data["app_version"] != "1.2.3" {
		t.Fatalf("unexpected data: %+v", row.data)
	}
	if row.app != "photos" || row.platform != "android" {
		t.Fatalf("unexpected app/platform: app=%s platform=%s", row.app, row.platform)
	}
	if _, ok := row.data["app"]; ok {
		t.Fatalf("app duplicated in data: %+v", row.data)
	}
	if _, ok := row.data["platform"]; ok {
		t.Fatalf("platform duplicated in data: %+v", row.data)
	}
	if row.userID.Valid {
		t.Fatalf("install user_id = %d, want null", row.userID.Int64)
	}
}

func TestCreateUserEventCopiesInstallData(t *testing.T) {
	handler, db := setupEventHandlerTest(t)
	id := uuid.New().String()

	performEventRequest(t, "/events", handler.Create, nil, map[string]any{
		"id":    id,
		"event": "install",
		"data": map[string]any{
			"utm_source": "newsletter",
		},
	})
	recorder := performEventRequest(t, "/events/user", handler.CreateForUser, int64Ptr(101), map[string]any{
		"id":    id,
		"event": "sign_up",
		"data":  map[string]any{},
	})

	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status code: got %d want %d; body=%s", recorder.Code, http.StatusOK, recorder.Body.String())
	}
	row := fetchEvent(t, db, id, "sign_up")
	if row.data["utm_source"] != "newsletter" ||
		row.data["app_version"] != "1.2.3" {
		t.Fatalf("unexpected data: %+v", row.data)
	}
	if row.app != "photos" || row.platform != "android" {
		t.Fatalf("unexpected app/platform: app=%s platform=%s", row.app, row.platform)
	}
	if !row.userID.Valid || row.userID.Int64 != 101 {
		t.Fatalf("sign_up user_id = %+v, want 101", row.userID)
	}
}

func TestCreateEventDuplicateIsNoOp(t *testing.T) {
	handler, db := setupEventHandlerTest(t)
	id := uuid.New().String()
	body := map[string]any{
		"id":    id,
		"event": "install",
		"data": map[string]any{
			"utm_source": "first",
		},
	}

	first := performEventRequest(t, "/events", handler.Create, nil, body)
	body["data"] = map[string]any{"utm_source": "second"}
	second := performEventRequest(t, "/events", handler.Create, nil, body)

	if first.Code != http.StatusOK || second.Code != http.StatusOK {
		t.Fatalf("unexpected status codes: first=%d second=%d", first.Code, second.Code)
	}
	row := fetchEvent(t, db, id, "install")
	if row.data["utm_source"] != "first" {
		t.Fatalf("duplicate mutated data: %+v", row.data)
	}
}

func setupEventHandlerTest(t *testing.T) (*EventHandler, *sql.DB) {
	t.Helper()

	testutil.WithServerRoot(t)

	db := testutil.RequireTestDB(t)
	testutil.ResetTables(t, db)
	t.Cleanup(func() {
		testutil.ResetTables(t, db)
	})

	return &EventHandler{
		Repo: &repo.EventRepository{DB: db},
	}, db
}

func performEventRequest(
	t *testing.T,
	route string,
	handler gin.HandlerFunc,
	userID *int64,
	body map[string]any,
) *httptest.ResponseRecorder {
	t.Helper()

	gin.SetMode(gin.TestMode)

	if _, ok := body["app"]; !ok {
		body["app"] = "photos"
	}
	if _, ok := body["platform"]; !ok {
		body["platform"] = "android"
	}
	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("failed to marshal request body: %v", err)
	}

	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, route, bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Client-Package", "io.ente.photos")
	req.Header.Set("X-Client-Version", "1.2.3")
	if userID != nil {
		req.Header.Set("X-Auth-User-ID", strconv.FormatInt(*userID, 10))
	}

	router := gin.New()
	router.POST(route, handler)
	router.ServeHTTP(recorder, req)

	return recorder
}

type storedEvent struct {
	data     map[string]any
	app      string
	platform string
	userID   sql.NullInt64
}

func fetchEvent(t *testing.T, db *sql.DB, id string, event string) storedEvent {
	t.Helper()

	var row storedEvent
	var raw []byte
	err := db.QueryRow(`SELECT data, app, platform, user_id FROM events WHERE id = $1 AND event = $2`, id, event).Scan(&raw, &row.app, &row.platform, &row.userID)
	if err != nil {
		t.Fatalf("failed to fetch event: %v", err)
	}
	if err := json.Unmarshal(raw, &row.data); err != nil {
		t.Fatalf("failed to unmarshal data: %v", err)
	}
	return row
}

func int64Ptr(v int64) *int64 {
	return &v
}
