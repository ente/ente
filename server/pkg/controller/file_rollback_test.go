package controller

import (
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/ente/museum/pkg/utils/s3config"
	"github.com/spf13/viper"
	"github.com/stretchr/testify/require"
)

func TestDeleteObjectVersionFromHotStorage(t *testing.T) {
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

			var deletedVersions, checkedVersions []string
			s3Config := s3config.NewS3Config()
			client := s3Config.GetHotS3Client()
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
			err := controller.deleteObjectVersionFromHotStorage(objectKey, versionID)
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
					Bucket: s3Config.GetHotBucket(),
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
