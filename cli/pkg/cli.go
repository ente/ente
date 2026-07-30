package pkg

import (
	"fmt"
	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg/secrets"
	bolt "go.etcd.io/bbolt"
	"os"
	"path/filepath"
)

type ClICtrl struct {
	Client     *api.Client
	DB         *bolt.DB
	KeyHolder  *secrets.KeyHolder
	tempFolder string
}

func (c *ClICtrl) Init() error {
	tempPath := filepath.Join(GetCLITempPath(), "ente-download")
	// create temp folder if not exists
	if _, err := os.Stat(tempPath); os.IsNotExist(err) {
		err = os.Mkdir(tempPath, 0755)
		if err != nil {
			return err
		}
	}
	c.tempFolder = tempPath
	return c.DB.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte(AccBucket))
		if err != nil {
			return fmt.Errorf("create bucket: %s", err)
		}
		return nil
	})
}

func GetCLITempPath() (string) {
	if os.Getenv("ENTE_CLI_TMP_PATH") != "" {
		return os.Getenv("ENTE_CLI_TMP_PATH")
	}
	return os.TempDir()
}
