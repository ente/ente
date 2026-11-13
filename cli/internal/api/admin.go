package api

import (
	"context"
	"fmt"
	"github.com/ente/cli/internal/api/models"
	"time"
)

func (c *Client) GetUserIdFromEmail(ctx context.Context, email string) (*models.UserDetails, error) {
	var res models.UserDetails
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&res).
		SetQueryParam("email", email).
		Get("/admin/user/")
	if err != nil {
		return nil, err
	}
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return &res, nil
}

func (c *Client) ListUsers(ctx context.Context) ([]models.User, error) {
	var res struct {
		Users []models.User `json:"users"`
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("sinceTime", "0").
		SetResult(&res).
		Get("/admin/users/")
	if err != nil {
		return nil, err
	}
	if r.IsError() {
		return nil, &ApiError{
			StatusCode: r.StatusCode(),
			Message:    r.String(),
		}
	}
	return res.Users, nil
}

func (c *Client) DeleteUser(ctx context.Context, email string) error {

	r, err := c.restClient.R().
		SetContext(ctx).
		SetQueryParam("email", email).
		Delete("/admin/user/delete")
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

func (c *Client) Disable2Fa(ctx context.Context, userID int64) error {
	var res interface{}

	payload := map[string]interface{}{
		"userID": userID,
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&res).
		SetBody(payload).
		Post("/admin/user/disable-2fa")
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

func (c *Client) DisablePassKeyMFA(ctx context.Context, userID int64) error {
	var res interface{}

	payload := map[string]interface{}{
		"userID": userID,
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&res).
		SetBody(payload).
		Post("/admin/user/disable-passkeys")
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

func (c *Client) UpdateFreePlanSub(ctx context.Context, userDetails *models.UserDetails, storageInBytes int64, expiryTimeInMicro int64) error {
	var res interface{}
	if userDetails.Subscription.ProductID != "free" {
		return fmt.Errorf("user is not on free plan")
	}
	payload := map[string]interface{}{
		"userID":          userDetails.User.ID,
		"expiryTime":      expiryTimeInMicro,
		"transactionID":   fmt.Sprintf("cli-on-%d", time.Now().Unix()),
		"productID":       "free",
		"paymentProvider": "",
		"storage":         storageInBytes,
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetResult(&res).
		SetBody(payload).
		Put("/admin/user/subscription")
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

func (c *Client) SendTestMail(ctx context.Context, toEmail, fromEmail, fromName string) error {
	body := map[string]interface{}{
		"to":        []string{toEmail},
		"fromName":  fromName,
		"fromEmail": fromEmail,
		"subject":   "Test mail from Ente",
		"body":      "This is a test mail from Ente",
	}
	r, err := c.restClient.R().
		SetContext(ctx).
		SetBody(body).
		Post("/admin/mail")
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
