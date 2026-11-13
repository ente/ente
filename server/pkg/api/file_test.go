package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ente/stacktrace"
	"github.com/gin-gonic/gin"

	"github.com/ente/museum/ente"
)

func TestWriteFileURLV3ReturnsJSONWithoutRedirect(t *testing.T) {
	recorder, ctx := newFileURLV3TestContext("/files/download/v3/1")

	writeFileURLV3(ctx, "https://objects.example/file", nil)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if location := recorder.Header().Get("Location"); location != "" {
		t.Fatalf("Location = %q, want empty", location)
	}
	var response struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.URL != "https://objects.example/file" {
		t.Fatalf("url = %q, want %q", response.URL, "https://objects.example/file")
	}
}

func TestWriteFileURLV3MapsNotFoundErrorsToBadRequest(t *testing.T) {
	tests := []struct {
		name string
		err  error
	}{
		{name: "sql no rows", err: stacktrace.Propagate(sql.ErrNoRows, "lookup object")},
		{name: "not found sentinel", err: stacktrace.Propagate(ente.ErrNotFound, "lookup memory file")},
		{name: "not found API error", err: stacktrace.Propagate(ente.ErrNotFoundError.NewErr("missing object"), "lookup file")},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			recorder, ctx := newFileURLV3TestContext("/files/download/v3/1")

			writeFileURLV3(ctx, "", test.err)

			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want %d", recorder.Code, http.StatusBadRequest)
			}
			var response ente.ApiError
			if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if response.Code != ente.NotFoundError {
				t.Fatalf("code = %q, want %q", response.Code, ente.NotFoundError)
			}
		})
	}
}

func TestWriteFileURLV3PreservesNonNotFoundErrors(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		wantStatus int
	}{
		{name: "bad request", err: ente.ErrBadRequest, wantStatus: http.StatusBadRequest},
		{name: "permission denied", err: ente.ErrPermissionDenied, wantStatus: http.StatusForbidden},
		{name: "internal error", err: errors.New("storage unavailable"), wantStatus: http.StatusInternalServerError},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			recorder, ctx := newFileURLV3TestContext("/files/download/v3/1")

			writeFileURLV3(ctx, "", test.err)

			if recorder.Code != test.wantStatus {
				t.Fatalf("status = %d, want %d", recorder.Code, test.wantStatus)
			}
			if recorder.Code == http.StatusNotFound {
				t.Fatal("HTTP 404 is reserved for an unavailable v3 route")
			}
		})
	}
}

func TestPublicCollectionFileURLV3InvalidFileIDReturnsBadRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/public-collection/files/download/v3/:fileID", (&PublicCollectionHandler{}).GetFileURLV3)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/public-collection/files/download/v3/invalid", nil))

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusBadRequest)
	}
}

func newFileURLV3TestContext(path string) (*httptest.ResponseRecorder, *gin.Context) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodGet, path, nil)
	return recorder, ctx
}
