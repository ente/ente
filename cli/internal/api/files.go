package api

import (
	"context"
	"github.com/ente/cli/utils/constants"
	"github.com/spf13/viper"
	"strconv"
	"strings"
)

var (
	downloadHost = "https://files.ente.com/?fileID="
)

func downloadUrl(fileID int64) string {
	apiEndpoint := viper.GetString("endpoint.api")
	if apiEndpoint == "" || strings.Compare(apiEndpoint, constants.EnteApiUrl) == 0 {
		return downloadHost + strconv.FormatInt(fileID, 10)
	}
	return apiEndpoint + "/files/download/" + strconv.FormatInt(fileID, 10)
}

func (c *Client) DownloadFile(ctx context.Context, fileID int64, absolutePath string) error {
	req := c.downloadClient.R().
		SetContext(ctx).
		SetOutput(absolutePath)
	attachToken(req)
	r, err := req.Get(downloadUrl(fileID))
	if r.IsError() {
		return &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return err
}
