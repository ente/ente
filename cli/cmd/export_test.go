package cmd

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"testing"
	"time"

	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/pkg/secrets"
	"github.com/ente/cli/utils/encoding"
	bolt "go.etcd.io/bbolt"
)

func TestExportCommandExitCode(t *testing.T) {
	deviceKey := bytes.Repeat([]byte{0x2a}, 32)

	tests := []struct {
		name     string
		accounts func(t *testing.T) []model.Account
		want     int
	}{
		{
			name:     "no configured accounts",
			accounts: func(t *testing.T) []model.Account { return nil },
			want:     0,
		},
		{
			name: "account without an export directory is skipped",
			accounts: func(t *testing.T) []model.Account {
				return []model.Account{exportedAccount(t, deviceKey, "")}
			},
			want: 0,
		},
		{
			// The db is read-only, so the sync fails before it can talk to the
			// network, the same way a failing export does.
			name: "sync failure",
			accounts: func(t *testing.T) []model.Account {
				return []model.Account{exportedAccount(t, deviceKey, t.TempDir())}
			},
			want: 1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			previous := ctrl
			ctrl = &pkg.ClICtrl{
				Client:    api.NewClient(api.Params{Host: "http://127.0.0.1:1"}),
				DB:        seedCLIDB(t, test.accounts(t)),
				KeyHolder: secrets.NewKeyHolder(deviceKey),
			}
			defer func() { ctrl = previous }()

			rootCmd.SetArgs([]string{"export"})
			if got := exitCode(rootCmd.Execute()); got != test.want {
				t.Fatalf("exitCode(export) = %d, want %d", got, test.want)
			}
		})
	}
}

func exportedAccount(t *testing.T, deviceKey []byte, exportDir string) model.Account {
	t.Helper()
	return model.Account{
		Email:     "user@example.com",
		UserID:    1,
		App:       api.AppPhotos,
		MasterKey: *model.MakeEncString(bytes.Repeat([]byte{0x01}, 32), deviceKey),
		SecretKey: *model.MakeEncString(bytes.Repeat([]byte{0x02}, 32), deviceKey),
		Token:     *model.MakeEncString(bytes.Repeat([]byte{0x03}, 32), deviceKey),
		PublicKey: encoding.EncodeBase64(bytes.Repeat([]byte{0x04}, 32)),
		ExportDir: exportDir,
	}
}

func seedCLIDB(t *testing.T, accounts []model.Account) *bolt.DB {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ente-cli.db")

	db, err := bolt.Open(path, 0600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	err = db.Update(func(tx *bolt.Tx) error {
		b, err := tx.CreateBucketIfNotExists([]byte(pkg.AccBucket))
		if err != nil {
			return err
		}
		for _, account := range accounts {
			raw, err := json.Marshal(account)
			if err != nil {
				return err
			}
			if err := b.Put([]byte(account.AccountKey()), raw); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}

	db, err = bolt.Open(path, 0600, &bolt.Options{ReadOnly: true, Timeout: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}
