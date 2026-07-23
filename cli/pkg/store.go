package pkg

import (
	"context"
	"fmt"
	"github.com/ente/cli/pkg/model"
	"log"
	"strconv"
	"time"

	bolt "go.etcd.io/bbolt"
)

func GetDB(path string) (*bolt.DB, error) {
	db, err := bolt.Open(path, 0600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		log.Fatal(fmt.Sprintf("Failed to open db %s ", path), err)
	}
	return db, err
}

func (c *ClICtrl) GetInt64ConfigValue(ctx context.Context, key string) (int64, error) {
	value, err := c.getConfigValue(ctx, key)
	if err != nil {
		return 0, err
	}
	var result int64
	if value != nil {
		result, err = strconv.ParseInt(string(value), 10, 64)
		if err != nil {
			return 0, err
		}
	}
	return result, nil
}

func (c *ClICtrl) getConfigValue(ctx context.Context, key string) ([]byte, error) {
	var value []byte
	err := c.DB.View(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, model.KVConfig)
		if err != nil {
			return err
		}
		value = kvBucket.Get([]byte(key))
		return nil
	})
	return value, err
}

func (c *ClICtrl) GetAllValues(ctx context.Context, store model.PhotosStore) ([][]byte, error) {
	result := make([][]byte, 0)
	err := c.DB.View(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, store)
		if err != nil {
			return err
		}
		kvBucket.ForEach(func(k, v []byte) error {
			result = append(result, v)
			return nil
		})
		return nil
	})
	return result, err
}

func (c *ClICtrl) PutConfigValue(ctx context.Context, key string, value []byte) error {
	return c.DB.Update(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, model.KVConfig)
		if err != nil {
			return err
		}
		return kvBucket.Put([]byte(key), value)
	})
}
func (c *ClICtrl) PutValue(ctx context.Context, store model.PhotosStore, key []byte, value []byte) error {
	return c.DB.Update(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, store)
		if err != nil {
			return err
		}
		return kvBucket.Put(key, value)
	})
}

func (c *ClICtrl) DeleteValue(ctx context.Context, store model.PhotosStore, key []byte) error {
	return c.DB.Update(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, store)
		if err != nil {
			return err
		}
		return kvBucket.Delete(key)
	})
}

// GetValue
func (c *ClICtrl) GetValue(ctx context.Context, store model.PhotosStore, key []byte) ([]byte, error) {
	var value []byte
	err := c.DB.View(func(tx *bolt.Tx) error {
		kvBucket, err := getAccountStore(ctx, tx, store)
		if err != nil {
			return err
		}
		value = kvBucket.Get(key)
		return nil
	})
	return value, err
}
func getAccountStore(ctx context.Context, tx *bolt.Tx, storeType model.PhotosStore) (*bolt.Bucket, error) {
	accountKey := ctx.Value("account_key").(string)
	accountBucket := tx.Bucket([]byte(accountKey))
	if accountBucket == nil {
		return nil, fmt.Errorf("account bucket not found")
	}
	store := accountBucket.Bucket([]byte(storeType))
	if store == nil {
		return nil, fmt.Errorf("store %s not found", storeType)
	}
	return store, nil
}
