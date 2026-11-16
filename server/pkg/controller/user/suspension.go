package user

import "context"

func (c *UserController) SetSuspended(ctx context.Context, userID int64, suspended bool) error {
	return c.finishTokenRevocation(c.UserAuthRepo.SetUserSuspended(ctx, userID, suspended))
}
