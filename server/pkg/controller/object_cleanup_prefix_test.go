package controller

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/ente/museum/internal/testutil"
	"github.com/ente/museum/pkg/utils/config"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestDeleteAllObjectsWithPrefix(t *testing.T) {
	testutil.WithServerRoot(t)
	viper.Reset()
	t.Cleanup(viper.Reset)
	require.NoError(t, config.ConfigureViper("local"))
	viper.Set("s3.b2-eu-cen.key", "test-key")
	viper.Set("s3.b2-eu-cen.secret", "test-secret")
	viper.Set("s3.b2-eu-cen.region", "us-east-1")
	viper.Set("s3.b2-eu-cen.bucket", "test-bucket")
	viper.Set("s3.b2-eu-cen.disable_ssl", true)
	viper.Set("s3.use_path_style_urls", true)

	const firstPage = `<ListBucketResult><IsTruncated>true</IsTruncated><NextContinuationToken>next</NextContinuationToken><Contents><Key>prefix/a</Key></Contents><Contents><Key>prefix/a_playlist</Key></Contents></ListBucketResult>`
	const lastPage = `<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>prefix/b</Key></Contents></ListBucketResult>`
	const emptyTruncatedPage = `<ListBucketResult><IsTruncated>true</IsTruncated><NextContinuationToken>last</NextContinuationToken></ListBucketResult>`
	for _, tc := range []struct {
		name         string
		pages        []string
		failDelete   bool
		wantRequests []string
		wantError    string
	}{
		{
			name: "delete before next page", pages: []string{firstPage, emptyTruncatedPage, lastPage},
			wantRequests: []string{
				"LIST ", "DELETE prefix/a", "HEAD prefix/a", "DELETE prefix/a_playlist", "HEAD prefix/a_playlist",
				"LIST next", "LIST last", "DELETE prefix/b", "HEAD prefix/b",
			},
		},
		{
			name: "later listing failure", pages: []string{firstPage},
			wantRequests: []string{
				"LIST ", "DELETE prefix/a", "HEAD prefix/a", "DELETE prefix/a_playlist", "HEAD prefix/a_playlist", "LIST next",
			},
			wantError: "AccessDenied",
		},
		{
			name: "deletion failure", pages: []string{firstPage, lastPage}, failDelete: true,
			wantRequests: []string{"LIST ", "DELETE prefix/a"},
			wantError:    "AccessDenied",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var mu sync.Mutex
			var requests []string
			page := 0
			s3Server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				mu.Lock()
				defer mu.Unlock()
				w.Header().Set("Content-Type", "application/xml")
				switch r.Method {
				case http.MethodGet:
					requests = append(requests, "LIST "+r.URL.Query().Get("continuation-token"))
					if r.URL.Query().Get("prefix") != "prefix/" || r.URL.Query().Get("list-type") != "2" {
						t.Errorf("unexpected listing query: %s", r.URL.RawQuery)
					}
					if page < len(tc.pages) {
						_, _ = w.Write([]byte(tc.pages[page]))
						page++
						return
					}
				case http.MethodDelete, http.MethodHead:
					requests = append(requests, r.Method+" "+strings.TrimPrefix(r.URL.Path, "/test-bucket/"))
					if r.Method == http.MethodHead {
						w.WriteHeader(http.StatusNotFound)
						return
					}
					if !tc.failDelete {
						w.WriteHeader(http.StatusNoContent)
						return
					}
				default:
					t.Errorf("unexpected request: %s %s", r.Method, r.URL)
				}
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`<Error><Code>AccessDenied</Code><Message>denied</Message></Error>`))
			}))
			t.Cleanup(s3Server.Close)
			viper.Set("s3.b2-eu-cen.endpoint", s3Server.URL)
			controller := NewObjectCleanupController(nil, nil, s3config.NewS3Config())
			err := controller.DeleteAllObjectsWithPrefix("prefix/", "b2-eu-cen")
			if tc.wantError == "" {
				require.NoError(t, err)
			} else {
				require.ErrorContains(t, err, tc.wantError)
			}
			mu.Lock()
			defer mu.Unlock()
			require.Equal(t, tc.wantRequests, requests)
		})
	}
}
