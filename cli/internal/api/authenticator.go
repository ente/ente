package api

import (
	"context"
	"github.com/ente/cli/internal/api/models"
	"strconv"
)

func (c *Client) GetAuthKey(ctx context.Context) (*models.AuthKey, error) {
	var res models.AuthKey
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&res).
		Get("/authenticator/key")
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return &res, err
}

func (c *Client) GetAuthDiff(ctx context.Context, sinceTime int64, limit int64) ([]models.AuthEntity, error) {
	var res struct {
		Diff []models.AuthEntity `json:"diff"`
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("sinceTime", strconv.FormatInt(sinceTime, 10)).
		SetQueryParam("limit", strconv.FormatInt(limit, 10)).
		SetResult(&res).
		Get("/authenticator/entity/diff")
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return res.Diff, err
}
