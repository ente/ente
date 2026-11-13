package api

import (
	"context"
	"fmt"
	"net/http"
	"strconv"

	"github.com/ente/cli/utils/constants"
	"github.com/spf13/viper"
)

const downloadHost = "https://files.ente.com/?fileID="

type fileURLResponse struct {
	URL string `json:"url"`
}

func useDownloadProxy() bool {
	apiEndpoint := viper.GetString("endpoint.api")
	return apiEndpoint == "" || apiEndpoint == constants.EnteApiUrl
}

func (c *Client) getFileURL(ctx context.Context, fileID int64) (string, error) {
	result := fileURLResponse{}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&result).
		Get(fmt.Sprintf("/files/download/v3/%d", fileID))
	if err != nil {
		return "", err
	}
	if r.IsError() {
		message := r.String()
		if r.StatusCode() == http.StatusNotFound {
			message = "file URL endpoint not found; please upgrade your Ente server and try again"
		}
		return "", &ApiError{
			StatusCode: r.StatusCode(),
			Message:    message,
		}
	}
	return result.URL, nil
}

func (c *Client) DownloadFile(ctx context.Context, fileID int64, absolutePath string) error {
	req := c.downloadClient.R().
		SetContext(ctx).
		SetOutput(absolutePath)

	var downloadURL string
	if useDownloadProxy() {
		downloadURL = downloadHost + strconv.FormatInt(fileID, 10)
		attachToken(req)
	} else {
		var err error
		downloadURL, err = c.getFileURL(ctx, fileID)
		if err != nil {
			return err
		}
	}

	r, err := req.Get(downloadURL)
	if err != nil {
		return err
	}
	if r.IsError() {
		return &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return nil
}
