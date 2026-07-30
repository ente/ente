package user

import (
	"context"

	"github.com/ente/museum/ente"
	"github.com/ente/museum/ente/details"
	"github.com/ente/stacktrace"
	"golang.org/x/sync/errgroup"
)

func (c *UserController) GetAccountDeletionSummary(ctx context.Context, userID int64) (details.AccountDeletionSummaryResponse, error) {
	var photosAndVideosCount int64
	var authenticatorCodesCount int64
	var lockerRecordsCount int64

	g := new(errgroup.Group)
	g.Go(func() error {
		count, err := c.FileRepo.GetFileCountForUser(userID, ente.Photos)
		if err != nil {
			return stacktrace.Propagate(err, "failed to get photos file count")
		}
		photosAndVideosCount = count
		return nil
	})
	g.Go(func() error {
		count, err := c.FileRepo.GetFileCountForUser(userID, ente.Locker)
		if err != nil {
			return stacktrace.Propagate(err, "failed to get locker file count")
		}
		lockerRecordsCount = count
		return nil
	})
	g.Go(func() error {
		count, err := c.AuthenticatorRepo.GetAuthCodeCount(ctx, userID)
		if err != nil {
			return stacktrace.Propagate(err, "failed to get authenticator code count")
		}
		authenticatorCodesCount = count
		return nil
	})

	if err := g.Wait(); err != nil {
		return details.AccountDeletionSummaryResponse{}, stacktrace.Propagate(err, "")
	}

	return details.AccountDeletionSummaryResponse{
		PhotosAndVideosCount:    photosAndVideosCount,
		AuthenticatorCodesCount: authenticatorCodesCount,
		LockerRecordsCount:      lockerRecordsCount,
	}, nil
}
