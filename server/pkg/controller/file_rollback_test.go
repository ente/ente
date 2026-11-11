package controller

import (
	"database/sql"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/ente"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestObjectRecoverySkipsFailedRollback(t *testing.T) {
	for _, failedType := range []ente.ObjectType{ente.FILE, ente.THUMBNAIL} {
		for _, state := range []string{"retained", "pruned"} {
			for _, failure := range []struct {
				name   string
				method string
			}{
				{name: "listing versions", method: http.MethodGet},
				{name: "deleting version", method: http.MethodDelete},
				{name: "verifying deletion", method: http.MethodHead},
			} {
				t.Run(string(failedType)+"/"+state+"/"+failure.name, func(t *testing.T) {
					test := newFileBucketTest(t)
					file := test.newFile(t, fileBucketB2, fileBucketWasabi)
					_, err := test.controller.Create(fileBucketContext(http.MethodPost), file.OwnerID, file, "test", ente.Photos)
					require.NoError(t, err)
					_, err = test.db.Exec(`UPDATE object_copies SET b2 = 1, wasabi = 1,
						scw = CASE WHEN want_scw THEN 1 END, last_attempt = now_utc_micro_seconds()`)
					require.NoError(t, err)
					if state == "pruned" {
						_, err = test.db.Exec(`DELETE FROM object_copies`)
						require.NoError(t, err)
					}
					failedKey, recoveredKey := file.File.ObjectKey, file.Thumbnail.ObjectKey
					if failedType == ente.THUMBNAIL {
						failedKey, recoveredKey = recoveredKey, failedKey
					}
					var before, after sql.NullString
					require.NoError(t, test.db.QueryRow(`SELECT (SELECT to_jsonb(object_copies)::text
						FROM object_copies WHERE object_key = $1)`, failedKey).Scan(&before))
					require.Equal(t, state == "retained", before.Valid, "initial replication row state")

					requests := make(map[string][]string)
					for _, bucket := range []string{fileBucketB2, fileBucketWasabi} {
						client := test.controller.S3Config.GetS3Client(bucket)
						client.Config.SleepDelay = func(time.Duration) {}
						client.Config.HTTPClient = &http.Client{
							Transport: rollbackTestTransport(func(r *http.Request) (*http.Response, error) {
								objectKey := strings.TrimPrefix(r.URL.Path, "/"+bucket+"/")
								status, body := http.StatusOK, ""
								switch r.Method {
								case http.MethodGet:
									require.True(t, r.URL.Query().Has("versions"))
									objectKey = r.URL.Query().Get("prefix")
									body = `<ListVersionsResult><Version><VersionId>new-version</VersionId></Version><Version><VersionId>old-version</VersionId></Version></ListVersionsResult>`
								case http.MethodDelete:
									require.Equal(t, "new-version", r.URL.Query().Get("versionId"))
									status = http.StatusNoContent
								case http.MethodHead:
									require.Equal(t, "new-version", r.URL.Query().Get("versionId"))
									status = http.StatusNotFound
								default:
									t.Fatalf("unexpected storage request: %s %s", r.Method, r.URL)
								}
								require.Contains(t, []string{failedKey, recoveredKey}, objectKey)
								requests[objectKey] = append(requests[objectKey], r.Method)
								if objectKey == failedKey && r.Method == failure.method {
									status = http.StatusForbidden
									body = `<Error><Code>AccessDenied</Code></Error>`
								}
								return &http.Response{
									StatusCode: status,
									Header:     make(http.Header),
									Body:       io.NopCloser(strings.NewReader(body)),
									Request:    r,
								}, nil
							}),
						}
					}

					test.controller.onExistingObjectsReplaced(fileBucketContext(http.MethodPost), file)
					require.Contains(t, requests[failedKey], failure.method)
					require.Equal(t, []string{http.MethodGet, http.MethodDelete, http.MethodHead}, requests[recoveredKey])
					require.NoError(t, test.db.QueryRow(`SELECT (SELECT to_jsonb(object_copies)::text
						FROM object_copies WHERE object_key = $1)`, failedKey).Scan(&after))
					require.Equal(t, before, after, "failed rollback must leave the replication job unchanged")
					copies, err := test.controller.FileRepo.ObjectCopiesRepo.GetAndLockUnreplicatedObject(t.Context())
					require.NoError(t, err)
					require.Equal(t, recoveredKey, copies.ObjectKey)
					require.True(t, copies.WantB2)
					require.True(t, copies.WantWasabi)
					require.Equal(t, failedType == ente.THUMBNAIL, copies.WantSCW)
					require.Nil(t, copies.SCW)
					source, destination := copies.Wasabi, copies.B2
					if failedType == ente.THUMBNAIL {
						source, destination = copies.B2, copies.Wasabi
					}
					require.NotNil(t, source)
					require.Nil(t, destination)
				})
			}
		}
	}
}

func TestDeleteObjectVersionUsesUploadBucket(t *testing.T) {
	const objectKey = "1/file"
	const versionID = "new-version"

	for _, tt := range []struct {
		name         string
		deleteStatus int
		headStatus   int
		wantError    bool
	}{
		{name: "deleted version is gone but older version remains", deleteStatus: 204, headStatus: 404},
		{name: "deleted version still exists", deleteStatus: 204, headStatus: 200, wantError: true},
		{name: "verification is forbidden", deleteStatus: 204, headStatus: 403, wantError: true},
		{name: "deletion is forbidden", deleteStatus: 403, headStatus: 404, wantError: true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			viper.Reset()
			t.Cleanup(viper.Reset)
			viper.Set("s3.b2-eu-cen.key", "test-key")
			viper.Set("s3.b2-eu-cen.secret", "test-secret")
			viper.Set("s3.b2-eu-cen.endpoint", "https://s3.example.test")
			viper.Set("s3.b2-eu-cen.region", "us-east-1")
			viper.Set("s3.b2-eu-cen.bucket", "test-bucket")
			viper.Set("s3.use_path_style_urls", true)
			viper.Set("s3.hot_storage.primary", "wasabi-eu-central-2-v3")
			viper.Set("s3.hot_storage.secondary", "b2-eu-cen")

			var deletedVersions, checkedVersions []string
			s3Config := s3config.NewS3Config()
			client := s3Config.GetS3Client("b2-eu-cen")
			client.Config.SleepDelay = func(time.Duration) {}
			client.Config.HTTPClient = &http.Client{
				Transport: rollbackTestTransport(func(r *http.Request) (*http.Response, error) {
					require.Equal(t, "/test-bucket/"+objectKey, r.URL.Path)
					version := r.URL.Query().Get("versionId")
					status := http.StatusMethodNotAllowed
					headers := make(http.Header)
					switch r.Method {
					case http.MethodDelete:
						deletedVersions = append(deletedVersions, version)
						status = tt.deleteStatus
					case http.MethodHead:
						checkedVersions = append(checkedVersions, version)
						if version == versionID {
							status = tt.headStatus
						} else {
							status = http.StatusOK
							headers.Set("X-Amz-Version-Id", "old-version")
						}
					}
					return &http.Response{
						StatusCode: status,
						Header:     headers,
						Body:       io.NopCloser(strings.NewReader("")),
						Request:    r,
					}, nil
				}),
			}

			controller := &FileController{S3Config: s3Config}
			err := controller.deleteObjectVersion(objectKey, versionID, "b2-eu-cen")
			if tt.wantError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
			require.Equal(t, []string{versionID}, deletedVersions)
			if tt.deleteStatus != http.StatusNoContent {
				require.Empty(t, checkedVersions)
				return
			}
			require.NotEmpty(t, checkedVersions)
			for _, version := range checkedVersions {
				require.Equal(t, versionID, version)
			}
			if !tt.wantError {
				require.Len(t, checkedVersions, 1)
				head, err := client.HeadObject(&s3.HeadObjectInput{
					Bucket: s3Config.GetBucket("b2-eu-cen"),
					Key:    aws.String(objectKey),
				})
				require.NoError(t, err)
				require.Equal(t, "old-version", aws.StringValue(head.VersionId))
			}
		})
	}
}

type rollbackTestTransport func(*http.Request) (*http.Response, error)

func (transport rollbackTestTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return transport(r)
}
