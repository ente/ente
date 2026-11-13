package api

import (
	"context"
	"strconv"
)

func (c *Client) GetCollections(ctx context.Context, sinceTime int64) ([]Collection, error) {
	var res struct {
		Collections []Collection `json:"collections"`
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("sinceTime", strconv.FormatInt(sinceTime, 10)).
		SetResult(&res).
		Get("/collections/v2")
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return res.Collections, err
}

func (c *Client) GetFiles(ctx context.Context, collectionID, sinceTime int64) ([]File, bool, error) {
	var res struct {
		Files   []File `json:"diff"`
		HasMore bool   `json:"hasMore"`
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("sinceTime", strconv.FormatInt(sinceTime, 10)).
		SetQueryParam("collectionID", strconv.FormatInt(collectionID, 10)).
		SetResult(&res).
		Get("/collections/v2/diff")
	if r.IsError() {
		return nil, false, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return res.Files, res.HasMore, err
}

func (c *Client) GetFile(ctx context.Context, collectionID, fileID int64) (*File, error) {
	var res struct {
		File File `json:"file"`
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("collectionID", strconv.FormatInt(collectionID, 10)).
		SetQueryParam("fileID", strconv.FormatInt(fileID, 10)).
		SetResult(&res).
		Get("/collections/file")
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return &res.File, err
}
