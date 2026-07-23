package pkg

import (
	"context"
	"encoding/base64"
	"fmt"
	"github.com/ente/cli/internal/api/models"
	"github.com/ente/cli/pkg/mapper"
	"github.com/ente/cli/pkg/model"
	"log"
	"os"
	"time"
)

func (c *ClICtrl) SyncAuthAccount(account model.Account, filters model.Filter) error {
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
	data, err := c.fetchRemoteAuthenticatorData(ctx)
	if err != nil {
		log.Printf("Error fetching entities: %s", err)
		return err
	}
	return c.writeAuthExport(ctx, account, data)
}

func (c *ClICtrl) writeAuthExport(ctx context.Context, account model.Account, data []string) error {
	exportDir := account.ExportDir
	if exportDir == "" {
		return fmt.Errorf("export directory not set")
	}
	outputFile := fmt.Sprintf("%s/ente_auth.txt", exportDir)
	// if outout file exists, create a backup with current datetime
	if _, err := os.Stat(outputFile); err == nil {
		backupFile := fmt.Sprintf("%s/ente_auth_%s.txt", exportDir, time.Now().Format("2006-01-02_15-04-05"))
		if err := os.Rename(outputFile, backupFile); err != nil {
			return fmt.Errorf("error creating backup file: %v", err)
		}
	}
	// write the data to the output file, one line per entity
	file, err := os.Create(outputFile)
	if err != nil {
		return fmt.Errorf("error creating output file: %v", err)
	}
	defer file.Close()
	for _, line := range data {
		if _, err := file.WriteString(line + "\n"); err != nil {
			return fmt.Errorf("error writing to output file: %v", err)
		}
	}
	return nil
}

func (c *ClICtrl) fetchRemoteAuthenticatorData(ctx context.Context) ([]string, error) {
	var entities []models.AuthEntity
	hasMore := true
	sinceTime := int64(0)

	for hasMore {
		fetched, err := c.Client.GetAuthDiff(ctx, sinceTime, 500)
		if err != nil {
			return nil, fmt.Errorf("failed to get entities: %s", err)
		}
		entities = append(entities, fetched...)
		if len(fetched) < 500 {
			hasMore = false
		} else {
			for _, entity := range fetched {
				if entity.UpdatedAt > sinceTime {
					sinceTime = entity.UpdatedAt
				}
			}
		}
	}
	if len(entities) == 0 {
		log.Println("No data to export")
		return nil, nil
	}
	var key []byte
	var err error
	authKey, authKeyErr := c.Client.GetAuthKey(ctx)
	if authKeyErr != nil {
		return nil, fmt.Errorf("failed to get auth key: %s", authKeyErr)
	} else {
		key, err = c.KeyHolder.GetAuthenticatorKey(ctx, *authKey)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt auth key: %s", err)
		}
	}
	var codes []string
	for _, authEntity := range entities {
		if authEntity.IsDeleted {
			continue
		}
		code, mapErr := mapper.MapRemoteAuthEntityToString(ctx, authEntity, key)
		if mapErr != nil {
			return nil, mapErr
		}
		codes = append(codes, *code)
	}
	return codes, nil
}
