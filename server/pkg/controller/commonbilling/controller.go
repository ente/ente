package commonbilling

import (
	"context"

	"github.com/ente/museum/pkg/controller/email"
	"github.com/ente/museum/pkg/repo"
	"github.com/ente/museum/pkg/repo/storagebonus"
	"github.com/ente/stacktrace"
	"github.com/sirupsen/logrus"
)

type Controller struct {
	EmailNotificationController *email.EmailNotificationController
	StorageBonusRepo            *storagebonus.Repository
	UserRepo                    *repo.UserRepository
	UsageRepo                   *repo.UsageRepository
	BillingRepo                 *repo.BillingRepository
}

func NewController(
	emailNotificationController *email.EmailNotificationController,
	storageBonusRepo *storagebonus.Repository,
	userRepo *repo.UserRepository,
	usageRepo *repo.UsageRepository,
	billingRepo *repo.BillingRepository,
) *Controller {
	return &Controller{
		EmailNotificationController: emailNotificationController,
		StorageBonusRepo:            storageBonusRepo,
		UserRepo:                    userRepo,
		UsageRepo:                   usageRepo,
		BillingRepo:                 billingRepo,
	}
}

func (c *Controller) CanDowngradeToGivenStorage(newStorage int64, userID int64) (bool, error) {
	adminID, adminErr := c.UserRepo.GetFamilyAdminID(userID)
	if adminErr != nil {
		return false, stacktrace.Propagate(adminErr, "")
	}

	if adminID == nil {
		bonusStorage, bonErr := c.StorageBonusRepo.GetActiveStorageBonuses(context.Background(), userID)
		if bonErr != nil {
			return false, stacktrace.Propagate(bonErr, "")
		}
		usage, err := c.UsageRepo.GetUsage(userID)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		// newStore + addOnStorage + referralStorage should not be greater than usage.

		if usage > (newStorage + bonusStorage.GetUsableBonus(newStorage)) {
			logrus.Infof("user with %d usage and %d bonus, can not downgrade to %d", usage, bonusStorage.GetUsableBonus(newStorage), newStorage)
			return false, nil
		}
	} else {
		bonusStorage, bonErr := c.StorageBonusRepo.GetActiveStorageBonuses(context.Background(), *adminID)
		if bonErr != nil {
			return false, stacktrace.Propagate(bonErr, "")
		}
		usage, err := c.UsageRepo.StorageForFamilyAdmin(*adminID)
		if err != nil {
			return false, stacktrace.Propagate(err, "")
		}
		if usage > (newStorage + bonusStorage.GetUsableBonus(newStorage)) {
			logrus.Infof("user with %d usage and %d bonus, can not downgrade to %d", usage, bonusStorage.GetUsableBonus(newStorage), newStorage)
			return false, nil
		}
	}
	return true, nil
}

func (c *Controller) OnSubscriptionCancelled(userID int64) error {
	err := c.BillingRepo.UpdateSubscriptionCancellationStatus(userID, true)
	if err != nil {
		return stacktrace.Propagate(err, "")
	}
	go c.EmailNotificationController.OnSubscriptionCancelled(userID)
	return nil
}
