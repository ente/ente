package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg"
	"github.com/ente/cli/pkg/model"
	"github.com/ente/cli/utils/constants"
	"github.com/spf13/viper"
	"github.com/zalando/go-keyring"
	bolt "go.etcd.io/bbolt"
)

func TestCLIStartup(t *testing.T) {
	if os.Getenv("ENTE_CLI_TEST_STARTUP") != "" {
		keyring.MockInitWithError(errors.New("unexpected keyring access"))
		if os.Getenv("ENTE_CLI_TEST_KEYRING") != "" {
			keyring.MockInit()
			if err := keyring.Set("ente", "ente-cli-user", base64.StdEncoding.EncodeToString(make([]byte, 32))); err != nil {
				t.Fatal(err)
			}
		}
		os.Args = append([]string{"ente"}, flag.Args()...)
		main()
		os.Exit(0)
	}

	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.URL.Path != "/admin/users/" || r.Header.Get("X-Auth-Token") != base64.URLEncoding.EncodeToString([]byte("synthetic-token")) {
			t.Errorf("unexpected authenticated request: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"users":[]}`))
	}))
	defer server.Close()
	cwd, trusted := t.TempDir(), t.TempDir()
	for key, value := range map[string]string{
		"ENTE_CLI_TEST_STARTUP": "1", "ENTE_CLI_TEST_KEYRING": "",
		"ENTE_CLI_CONFIG_DIR": trusted, "ENTE_CLI_CONFIG_PATH": "",
		"ENTE_CLI_SECRETS_PATH": "", "ENTE_CLI_TMP_PATH": t.TempDir(),
	} {
		t.Setenv(key, value)
	}
	writeTestConfig(t, filepath.Join(trusted, "config.yaml"), "endpoint:\n  api: "+server.URL+"\n")
	writeTestConfig(t, filepath.Join(cwd, "config.yaml"), "not valid YAML: [secret-sentinel")
	seedTestAccount(t, filepath.Join(trusted, "ente-cli.db"))
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	run := func(wantError string, args ...string) string {
		t.Helper()
		ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
		defer cancel()
		command := exec.CommandContext(ctx, executable, append([]string{"-test.run=^TestCLIStartup$", "--"}, args...)...)
		command.Dir = cwd
		var stdout, stderr bytes.Buffer
		command.Stdout, command.Stderr = &stdout, &stderr
		err := command.Run()
		if (err != nil) != (wantError != "") || !strings.Contains(stderr.String(), wantError) || (wantError != "" && stdout.Len() != 0) {
			t.Fatalf("%v: error=%v stdout=%q stderr=%q", args, err, stdout.String(), stderr.String())
		}
		if strings.Contains(stderr.String(), "secret-sentinel") || strings.Contains(stderr.String(), "unexpected keyring access") {
			t.Fatalf("unsafe startup: %s", stderr.String())
		}
		return stdout.String()
	}
	for _, args := range [][]string{{"export"}, {"account", "add"}, {"admin", "list-users"}} {
		run("refusing network command", args...)
	}
	for _, args := range [][]string{{"version"}, {"export", "--help"}, {"completion", "bash"}} {
		run("", args...)
	}
	t.Setenv("ENTE_CLI_TEST_KEYRING", "1")
	if output := run("", "account", "list"); !strings.Contains(output, "Configured accounts: 1") {
		t.Fatalf("local account command failed: %q", output)
	}
	if requests.Load() != 0 {
		t.Fatal("working-directory config allowed a network request")
	}
	if err := os.Remove(filepath.Join(cwd, "config.yaml")); err != nil {
		t.Fatal(err)
	}
	if output := run("", "admin", "list-users", "--admin-user", "saved@example.invalid"); output != "" || requests.Load() != 1 {
		t.Fatalf("expected one authenticated request and an empty user list, got output=%q requests=%d", output, requests.Load())
	}
	t.Setenv("ENTE_CLI_TEST_KEYRING", "")
	writeTestConfig(t, filepath.Join(trusted, "config.yaml"), "endpoint: [secret-sentinel")
	run("cannot load trusted configuration", "export")
}

func seedTestAccount(t *testing.T, path string) {
	t.Helper()
	key := make([]byte, 32)
	account := model.Account{Email: "saved@example.invalid", UserID: 1, App: api.AppPhotos,
		Token: *model.MakeEncString([]byte("synthetic-token"), key), MasterKey: *model.MakeEncString(key, key), SecretKey: *model.MakeEncString(key, key)}
	data, err := json.Marshal(account)
	if err != nil {
		t.Fatal(err)
	}
	db, err := pkg.GetDB(path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err := db.Update(func(tx *bolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists([]byte(pkg.AccBucket))
		if err != nil {
			return err
		}
		return bucket.Put([]byte(account.AccountKey()), data)
	}); err != nil {
		t.Fatal(err)
	}
}

func TestTrustedConfig(t *testing.T) {
	t.Cleanup(viper.Reset)
	dir := t.TempDir()
	for _, body := range []string{
		"endpoint: [secret-sentinel", "endpoint:\n  api: []\n", "endpoint:\n  api: ''\n",
		"endpoint:\n  api: null\n", "endpoint: null\n", "endpoint:\n  api: {}\n", "[endpoint]\napi = 'secret-sentinel'\n",
	} {
		viper.Reset()
		writeTestConfig(t, filepath.Join(dir, "config.yaml"), body)
		if err := initConfig(dir); err == nil || strings.Contains(err.Error(), "secret-sentinel") {
			t.Fatalf("expected sanitized configuration error, got %v", err)
		}
	}
	viper.Reset()
	writeTestConfig(t, filepath.Join(dir, "config.yaml"), "log:\n  http: true\n")
	if err := initConfig(dir); err != nil || viper.GetString("endpoint.api") != constants.EnteApiUrl || !viper.GetBool("log.http") {
		t.Fatalf("configuration without an endpoint lost its default: %v", err)
	}
}

func TestConfigSymlinks(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	dir, target := t.TempDir(), filepath.Join(t.TempDir(), "settings.yaml")
	if err := os.Symlink(target, filepath.Join(dir, "config.yaml")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	if err := initConfig(dir); err == nil {
		t.Fatal("dangling trusted config was ignored")
	}
	writeTestConfig(t, target, "endpoint:\n  api: https://trusted.invalid\n")
	if err := initConfig(dir); err != nil || viper.GetString("endpoint.api") != "https://trusted.invalid" {
		t.Fatalf("linked configuration not loaded: %v", err)
	}
	alias := filepath.Join(t.TempDir(), "alias")
	if err := os.Symlink(dir, alias); err != nil {
		t.Fatal(err)
	}
	t.Chdir(dir)
	if err := checkWorkingDirectoryConfig(alias); err != nil {
		t.Fatal(err)
	}
}

func TestWorkingDirectoryConfig(t *testing.T) {
	cwd, trusted := t.TempDir(), t.TempDir()
	t.Chdir(cwd)
	for _, name := range []string{"config.yaml", "config.json", "config.toml", "config"} {
		writeTestConfig(t, name, "not valid YAML: [secret-sentinel")
		if err := checkWorkingDirectoryConfig(trusted); err == nil || strings.Contains(err.Error(), "secret-sentinel") {
			t.Fatalf("expected migration error, got %v", err)
		}
		for _, dir := range []string{".", "./", cwd} {
			if err := checkWorkingDirectoryConfig(dir); err != nil {
				t.Fatalf("trusted directory %q: %v", dir, err)
			}
		}
		if err := os.Remove(name); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir("config.yaml", 0700); err != nil {
		t.Fatal(err)
	}
	if err := checkWorkingDirectoryConfig(trusted); err != nil {
		t.Fatal(err)
	}
	dir := filepath.VolumeName(cwd) + string(filepath.Separator)
	t.Setenv("ENTE_CLI_CONFIG_DIR", dir)
	if got, err := GetCLIConfigDir(); err != nil || got != dir {
		t.Fatalf("config directory = %q, %v; want %q", got, err, dir)
	}
}

func writeTestConfig(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
}
