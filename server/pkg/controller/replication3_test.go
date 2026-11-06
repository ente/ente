package controller

import (
	"database/sql"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/aws/aws-sdk-go/aws/client"
	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/controller/discord"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

var replicationTestDCs = map[string]string{
	"b2": "b2-eu-cen", "wasabi": "wasabi-eu-central-2-v3", "scw": "scw-eu-fr-v3",
}

func TestReplicationHotCopies(t *testing.T) {
	for _, tc := range []struct {
		name         string
		primary      string
		copies       []string
		thumbnail    bool
		failure      string
		badDownload  bool
		badUpload    bool
		compliance   bool
		interrupted  bool
		deleted      bool
		deletedUser  bool
		wantError    bool
		wantCopies   []string
		wantRequests []string
	}{
		{name: "wasabi file", primary: "wasabi", copies: []string{"wasabi"}, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2", "PUT scw", "HEAD scw"}},
		{name: "wasabi thumbnail", primary: "wasabi", copies: []string{"wasabi"}, thumbnail: true, wantCopies: []string{"b2", "wasabi"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2"}},
		{name: "b2 file", primary: "b2", copies: []string{"b2"}, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET b2", "PUT wasabi", "HEAD wasabi", "PUT scw", "HEAD scw"}},
		{name: "primary missing", primary: "wasabi", copies: []string{"b2"}, thumbnail: true, wantCopies: []string{"b2", "wasabi"},
			wantRequests: []string{"GET b2", "PUT wasabi", "HEAD wasabi"}},
		{name: "backfill after switching to b2", primary: "b2", copies: []string{"wasabi", "scw"}, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2"}},
		{name: "prefer wasabi", primary: "wasabi", copies: []string{"b2", "wasabi"}, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT scw", "HEAD scw"}},
		{name: "prefer b2", primary: "b2", copies: []string{"b2", "wasabi"}, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET b2", "PUT scw", "HEAD scw"}},
		{name: "b2 destination unavailable", primary: "wasabi", copies: []string{"wasabi"}, failure: "PUT b2", wantError: true, wantCopies: []string{"wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT b2", "PUT scw", "HEAD scw"}},
		{name: "scaleway destination unavailable", primary: "wasabi", copies: []string{"wasabi"}, failure: "PUT scw", wantError: true, wantCopies: []string{"b2", "wasabi"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2", "PUT scw"}},
		{name: "wasabi destination unavailable", primary: "b2", copies: []string{"b2"}, failure: "PUT wasabi", wantError: true, wantCopies: []string{"b2", "scw"},
			wantRequests: []string{"GET b2", "PUT wasabi", "PUT scw", "HEAD scw"}},
		{name: "preferred source unavailable", primary: "b2", copies: []string{"b2", "wasabi"}, failure: "GET b2", wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET b2", "GET wasabi", "PUT scw", "HEAD scw"}},
		{name: "sole source unavailable", primary: "wasabi", copies: []string{"wasabi"}, failure: "GET wasabi", wantError: true, wantCopies: []string{"wasabi"},
			wantRequests: []string{"GET wasabi"}},
		{name: "cold copy is not a source", primary: "wasabi", copies: []string{"scw"}, wantError: true, wantCopies: []string{"scw"}},
		{name: "download size mismatch", primary: "wasabi", copies: []string{"wasabi"}, badDownload: true, wantError: true, wantCopies: []string{"wasabi"},
			wantRequests: []string{"GET wasabi"}},
		{name: "discard invalid download before retry", primary: "wasabi", copies: []string{"b2", "wasabi"}, badDownload: true, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "GET b2", "PUT scw", "HEAD scw"}},
		{name: "b2 upload size mismatch", primary: "wasabi", copies: []string{"wasabi"}, badUpload: true, wantError: true, wantCopies: []string{"wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2", "PUT scw", "HEAD scw"}},
		{name: "interrupted compliance upload", primary: "b2", copies: []string{"b2"}, compliance: true, interrupted: true, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET b2", "PUT wasabi", "HEAD wasabi", "PUT scw", "HEAD scw"}},
		{name: "interrupted b2 upload", primary: "wasabi", copies: []string{"wasabi"}, interrupted: true, wantCopies: []string{"b2", "wasabi", "scw"},
			wantRequests: []string{"GET wasabi", "PUT b2", "HEAD b2", "PUT scw", "HEAD scw"}},
		{name: "deleted file", primary: "wasabi", copies: []string{"wasabi"}, deleted: true, wantCopies: []string{"wasabi"}},
		{name: "deleted user", primary: "wasabi", copies: []string{"wasabi"}, deletedUser: true, wantCopies: []string{"wasabi"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			const content = "encrypted object"
			var mu sync.Mutex
			var requests []string
			failure := tc.failure
			storage := make(map[string]string)
			for _, provider := range tc.copies {
				storage[provider] = content
			}
			if tc.compliance {
				storage["wasabi"] = content
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				provider := strings.Split(strings.TrimPrefix(r.URL.Path, "/"), "/")[0]
				request := r.Method + " " + provider
				requests = append(requests, request)
				if request == failure || tc.compliance && request == "PUT wasabi" {
					w.WriteHeader(http.StatusForbidden)
					_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code></Error>`)
					return
				}
				switch r.Method {
				case http.MethodGet:
					body, ok := storage[provider]
					if !ok {
						w.WriteHeader(http.StatusNotFound)
						return
					}
					if tc.badDownload && provider == tc.primary {
						body += "invalid trailing bytes"
					}
					_, _ = io.WriteString(w, body)
				case http.MethodPut:
					body, err := io.ReadAll(r.Body)
					if err != nil {
						t.Error(err)
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					if string(body) != content {
						t.Errorf("%s received %q, expected %q", provider, body, content)
					}
					wantClass := ""
					if provider == "scw" {
						wantClass = "GLACIER"
					}
					if got := r.Header.Get("X-Amz-Storage-Class"); got != wantClass {
						t.Errorf("%s storage class = %q, expected %q", provider, got, wantClass)
					}
					storage[provider] = string(body)
				case http.MethodHead:
					size := len(storage[provider])
					if tc.badUpload && provider == "b2" {
						size++
					}
					w.Header().Set("Content-Length", strconv.Itoa(size))
				default:
					t.Errorf("unexpected storage request %s", request)
					w.WriteHeader(http.StatusBadRequest)
				}
			}))
			t.Cleanup(server.Close)
			c := newReplicationTestController(t, server.URL, tc.primary, false, tc.compliance)
			db := testutil.RequireTestDB(t)
			testutil.ResetTables(t, db)
			t.Cleanup(func() { testutil.ResetTables(t, db) })
			c.ObjectRepo = &repo.ObjectRepository{DB: db}
			c.ObjectCopiesRepo = &repo.ObjectCopiesRepository{DB: db}
			ownerID := testutil.InsertUser(t, db, testutil.UserFixture{UserID: 1, Email: "replication@example.com", CreationTime: 1})
			var fileID int64
			require.NoError(t, db.QueryRow(`INSERT INTO files (owner_id, file_decryption_header,
				thumbnail_decryption_header, metadata_decryption_header, encrypted_metadata, updation_time)
				VALUES ($1, 'file', 'thumbnail', 'metadata', 'encrypted', 1) RETURNING file_id`, ownerID).Scan(&fileID))
			objectType := "file"
			if tc.thumbnail {
				objectType = "thumbnail"
			}
			objectKey := "1/replication-" + objectType
			locations := make([]string, 0, 3)
			for _, provider := range tc.copies {
				locations = append(locations, replicationTestDCs[provider])
			}
			if tc.interrupted {
				provider := "b2"
				if tc.compliance {
					provider = "wasabi"
				}
				locations = append(locations, replicationTestDCs[provider])
			}
			_, err := db.Exec(`INSERT INTO object_keys (file_id, o_type, object_key, size, datacenters, is_deleted)
				VALUES ($1, $2, $3, $4, $5, $6)`, fileID, objectType, objectKey, len(content), pq.Array(locations), tc.deleted)
			require.NoError(t, err)
			_, err = db.Exec(`INSERT INTO object_copies (object_key, b2, wasabi, scw, want_b2, want_wasabi, want_scw)
				VALUES ($1, CASE WHEN $2 THEN 1 END, CASE WHEN $3 THEN 1 END, CASE WHEN $4 THEN 1 END, true, true, $5)`,
				objectKey, slices.Contains(tc.copies, "b2"), slices.Contains(tc.copies, "wasabi"), slices.Contains(tc.copies, "scw"), !tc.thumbnail)
			require.NoError(t, err)
			if tc.deletedUser {
				_, err = db.Exec(`UPDATE users SET encrypted_email = NULL WHERE user_id = $1`, ownerID)
				require.NoError(t, err)
			}

			err = c.tryReplicate()
			if tc.wantError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
			var b2, wasabi, scw sql.NullInt64
			var wantB2, wantWasabi, wantSCW bool
			require.NoError(t, db.QueryRow(`SELECT b2, wasabi, scw, want_b2, want_wasabi, want_scw
				FROM object_copies WHERE object_key = $1`, objectKey).Scan(&b2, &wasabi, &scw, &wantB2, &wantWasabi, &wantSCW))
			for provider, timestamp := range map[string]sql.NullInt64{"b2": b2, "wasabi": wasabi, "scw": scw} {
				require.Equal(t, slices.Contains(tc.wantCopies, provider), timestamp.Valid, provider)
			}
			if tc.deleted || tc.deletedUser {
				require.False(t, wantB2 || wantWasabi || wantSCW)
			}
			locations, err = c.ObjectRepo.GetDataCentersForObject(objectKey)
			require.NoError(t, err)
			expectedLocations := make([]string, 0, len(tc.wantCopies))
			for _, provider := range tc.wantCopies {
				expectedLocations = append(expectedLocations, replicationTestDCs[provider])
			}
			require.ElementsMatch(t, expectedLocations, locations)
			if !tc.wantError {
				_, err = db.Exec(`UPDATE object_copies SET last_attempt = 0 WHERE object_key = $1`, objectKey)
				require.NoError(t, err)
			}
			require.ErrorIs(t, c.tryReplicate(), sql.ErrNoRows)
			mu.Lock()
			actualRequests := slices.Clone(requests)
			mu.Unlock()
			require.Equal(t, tc.wantRequests, actualRequests)
			if tc.failure == "PUT b2" {
				mu.Lock()
				failure = ""
				requests = nil
				mu.Unlock()
				_, err = db.Exec(`UPDATE object_copies SET last_attempt = 0 WHERE object_key = $1`, objectKey)
				require.NoError(t, err)
				require.NoError(t, c.tryReplicate())
				require.NoError(t, db.QueryRow(`SELECT b2 FROM object_copies WHERE object_key = $1`, objectKey).Scan(&b2))
				require.True(t, b2.Valid)
				locations, err = c.ObjectRepo.GetDataCentersForObject(objectKey)
				require.NoError(t, err)
				require.ElementsMatch(t, []string{replicationTestDCs["b2"], replicationTestDCs["wasabi"], replicationTestDCs["scw"]}, locations)
				mu.Lock()
				actualRequests = slices.Clone(requests)
				mu.Unlock()
				require.Equal(t, []string{"GET wasabi", "PUT b2", "HEAD b2"}, actualRequests)
			}
			files, err := os.ReadDir(c.tempStorage)
			require.NoError(t, err)
			require.Empty(t, files)
		})
	}
}

func TestReplicationWorkerRouting(t *testing.T) {
	for _, tc := range []struct {
		provider string
		local    bool
	}{
		{provider: "b2"}, {provider: "wasabi"}, {provider: "b2", local: true},
	} {
		t.Run(fmt.Sprintf("%s/local=%v", tc.provider, tc.local), func(t *testing.T) {
			var directCalls, workerCalls atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				directCalls.Add(1)
				_, _ = io.WriteString(w, "encrypted")
			}))
			t.Cleanup(server.Close)
			worker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				workerCalls.Add(1)
				decoded, err := base64.StdEncoding.DecodeString(r.URL.Query().Get("src"))
				if err != nil {
					t.Error(err)
				}
				source, err := url.Parse(string(decoded))
				if err != nil || source.Path != "/b2/1/object" {
					t.Errorf("unexpected worker source %q: %v", decoded, err)
				}
				_, _ = io.WriteString(w, "encrypted")
			}))
			t.Cleanup(worker.Close)
			c := newReplicationTestController(t, server.URL, "wasabi", tc.local, false)
			c.workerURL = worker.URL
			source := c.b2Dest
			if tc.provider == "wasabi" {
				source = c.wasabiDest
			}
			file, err := os.CreateTemp(c.tempStorage, "download")
			require.NoError(t, err)
			t.Cleanup(func() { _ = file.Close() })
			n, err := c.downloadFromSource("1/object", file, source)
			require.NoError(t, err)
			require.EqualValues(t, len("encrypted"), n)
			if tc.provider == "b2" && !tc.local {
				require.EqualValues(t, 1, workerCalls.Load())
				require.Zero(t, directCalls.Load())
			} else {
				require.Zero(t, workerCalls.Load())
				require.EqualValues(t, 1, directCalls.Load())
			}
			require.Equal(t, !tc.local, c.scwDest.IsGlacier)
		})
	}
}

func newReplicationTestController(t *testing.T, endpoint, primary string, local, compliance bool) *ReplicationController3 {
	t.Helper()
	viper.Reset()
	t.Cleanup(viper.Reset)
	viper.Set("s3.hot_storage.primary", replicationTestDCs[primary])
	secondary := "wasabi"
	if primary == "wasabi" {
		secondary = "b2"
	}
	viper.Set("s3.hot_storage.secondary", replicationTestDCs[secondary])
	viper.Set("s3.use_path_style_urls", true)
	viper.Set("s3.are_local_buckets", local)
	viper.Set("s3.wasabi-eu-central-2-v3.compliance", compliance)
	for provider, dc := range replicationTestDCs {
		prefix := "s3." + dc + "."
		viper.Set(prefix+"key", "test-key")
		viper.Set(prefix+"secret", "test-secret")
		viper.Set(prefix+"endpoint", endpoint)
		viper.Set(prefix+"region", "us-east-1")
		viper.Set(prefix+"bucket", provider)
	}
	c := &ReplicationController3{
		S3Config: s3config.NewS3Config(), DiscordController: &discord.DiscordController{}, tempStorage: t.TempDir(),
		mUploadSuccess: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "replication_test_success"}, []string{"destination"}),
		mUploadFailure: prometheus.NewCounterVec(prometheus.CounterOpts{Name: "replication_test_failure"}, []string{"destination"}),
	}
	c.createDestinations()
	for _, dest := range []*UploadDestination{c.b2Dest, c.wasabiDest, c.scwDest} {
		dest.Client.Retryer = client.DefaultRetryer{NumMaxRetries: 0}
	}
	return c
}
