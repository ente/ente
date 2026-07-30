package pkg

import (
	"context"
	"encoding/base64"
	"fmt"
	"github.com/ente/cli/internal"
	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg/model"
	bolt "go.etcd.io/bbolt"
	"log"
	"time"
)

func (c *ClICtrl) Export(filter model.Filter) error {
	accounts, err := c.GetAccounts(context.Background())
	if err != nil {
		return err
	}
	if len(accounts) == 0 {
		fmt.Printf("No accounts to sync\n Add account using `account add` cmd\n")
		return nil
	}

	for _, account := range accounts {
		log.SetPrefix(fmt.Sprintf("[%s-%s] ", account.App, account.Email))
		if filter.SkipAccount(account.Email) {
			log.Printf("Skip account %s: account is excluded by filter", account.Email)
			continue
		}
		if account.ExportDir == "" {
			log.Printf("Skip account %s: no export directory configured", account.Email)
			continue
		}
		_, err = internal.ValidateDirForWrite(account.ExportDir)
		if err != nil {
			log.Printf("Skip export, error: %v while validing exportDir %s\n", err, account.ExportDir)
			continue
		}
		if account.App == api.AppAuth {
			err := c.SyncAuthAccount(account, filter)
			if err != nil {
				return err
			}
			continue
		}
		log.Println("start sync")
		retryCount := 0
		for {
			err = c.SyncAccount(account, filter)
			if err != nil {
				if model.ShouldRetrySync(err) && retryCount < 20 {
					retryCount = retryCount + 1
					timeInSecond := time.Duration(retryCount*10) * time.Second
					log.Printf("Connection err, waiting for %s before trying again", timeInSecond.String())
					time.Sleep(timeInSecond)
					continue
				}
				fmt.Printf("Error syncing account %s: %s\n", account.Email, err)
				return err
			} else {
				log.Println("sync done")
				break
			}
		}

	}
	return nil
}

func (c *ClICtrl) SyncAccount(account model.Account, filters model.Filter) error {
	secretInfo, err := c.KeyHolder.LoadSecrets(account)
	if err != nil {
		return err
	}
	ctx := c.buildRequestContext(context.Background(), account, filters)
	err = createDataBuckets(c.DB, account)
	if err != nil {
		return err
	}
	c.Client.AddToken(account.AccountKey(), base64.URLEncoding.EncodeToString(secretInfo.Token))
	err = c.fetchRemoteCollections(ctx)
	if err != nil {
		log.Printf("Error fetching collections: %s", err)
		return err
	}
	err = c.fetchRemoteFiles(ctx)
	if err != nil {
		log.Printf("Error fetching files: %s", err)
		return err
	}
	err = c.createLocalFolderForRemoteAlbums(ctx, account)
	if err != nil {
		log.Printf("Error creating local folders: %s", err)
		return err
	}
	err = c.syncFiles(ctx, account)
	if err != nil {
		log.Printf("Error syncing files: %s", err)
		return err
	}
	return nil
}

func (c *ClICtrl) buildRequestContext(ctx context.Context,
	account model.Account,
	filter model.Filter) context.Context {
	ctx = context.WithValue(ctx, "app", string(account.App))
	ctx = context.WithValue(ctx, "account_key", account.AccountKey())
	ctx = context.WithValue(ctx, "user_id", account.UserID)
	ctx = context.WithValue(ctx, model.FilterKey, filter)
	return ctx
}

func createDataBuckets(db *bolt.DB, account model.Account) error {
	return db.Update(func(tx *bolt.Tx) error {
		dataBucket, err := tx.CreateBucketIfNotExists([]byte(account.AccountKey()))
		if err != nil {
			return fmt.Errorf("create bucket: %s", err)
		}
		for _, subBucket := range []model.PhotosStore{model.KVConfig, model.RemoteAlbums, model.RemoteFiles, model.RemoteAlbumEntries} {
			_, err := dataBucket.CreateBucketIfNotExists([]byte(subBucket))
			if err != nil {
				return err
			}
		}
		return nil
	})
}
