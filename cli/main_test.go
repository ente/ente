package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/ente/cli/utils/constants"
	"github.com/spf13/viper"
)

func TestCLIConfigDiscovery(t *testing.T) {
	if want := os.Getenv("ENTE_CLI_TEST_ENDPOINT"); want != "" {
		configDir, err := GetCLIConfigDir()
		if err != nil {
			t.Fatal(err)
		}
		if err := initConfig(configDir); err != nil {
			t.Fatal(err)
		}
		if got := viper.GetString("endpoint.api"); got != want {
			t.Fatalf("endpoint.api = %q, want %q", got, want)
		}
		return
	}

	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name          string
		cwdConfig     string
		trustedConfig string
		configDir     string
		legacyDir     string
		want          string
	}{
		{name: "ignore cwd YAML", cwdConfig: "config.yaml", want: constants.EnteApiUrl},
		{name: "ignore cwd JSON", cwdConfig: "config.json", want: constants.EnteApiUrl},
		{name: "user config", cwdConfig: "config.yaml", trustedConfig: "home/.ente/config.yml", want: "https://trusted.invalid"},
		{name: "explicit directory takes precedence", cwdConfig: "config.yaml", trustedConfig: "selected/config.yaml", configDir: "selected", legacyDir: "cwd", want: "https://trusted.invalid"},
		{name: "legacy directory", cwdConfig: "config.yaml", trustedConfig: "selected/config", legacyDir: "selected", want: "https://trusted.invalid"},
		{name: "explicit cwd", cwdConfig: "config.yaml", configDir: "cwd", want: "https://untrusted.invalid"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			root := t.TempDir()
			home := filepath.Join(root, "home")
			cwd := filepath.Join(root, "cwd")
			writeConfig := func(path, endpoint string) {
				t.Helper()
				body := "endpoint:\n  api: " + endpoint + "\n"
				if filepath.Ext(path) == ".json" {
					body = `{"endpoint":{"api":"` + endpoint + `"}}`
				}
				writeTestConfig(t, path, body)
			}
			writeConfig(filepath.Join(cwd, tt.cwdConfig), "https://untrusted.invalid")
			if tt.trustedConfig != "" {
				writeConfig(filepath.Join(root, tt.trustedConfig), "https://trusted.invalid")
			}
			envDir := func(path string) string {
				if path == "" {
					return ""
				}
				return filepath.Join(root, path)
			}
			command := exec.Command(executable, "-test.run=^TestCLIConfigDiscovery$")
			command.Dir = cwd
			command.Env = append(os.Environ(),
				"HOME="+home,
				"USERPROFILE="+home,
				"ENTE_CLI_CONFIG_DIR="+envDir(tt.configDir),
				"ENTE_CLI_CONFIG_PATH="+envDir(tt.legacyDir),
				"ENTE_CLI_TEST_ENDPOINT="+tt.want,
			)
			if output, err := command.CombinedOutput(); err != nil {
				t.Fatalf("%v\n%s", err, output)
			}
		})
	}
}
