package main

import (
	"fmt"
	"github.com/ente/cli/cmd"
	"github.com/ente/cli/internal"
	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg"
	"github.com/ente/cli/pkg/secrets"
	"github.com/ente/cli/utils/constants"
	"github.com/spf13/viper"
	"log"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

var AppVersion = "v0.3.0"

func main() {
	cliConfigDir, err := GetCLIConfigDir()
	if secrets.IsRunningInContainer() {
		cliConfigDir = constants.CliDataPath
		_, err := internal.ValidateDirForWrite(cliConfigDir)
		if err != nil {
			log.Fatalf("Please mount a volume to %s\n%v\n", cliConfigDir, err)
		}
	}
	if err != nil {
		log.Fatalf("Could not create cli config path\n%v\n", err)
	}
	if err := initConfig(cliConfigDir); err != nil {
		log.Fatal(err)
	}
	newCliDBPath := filepath.Join(cliConfigDir, "ente-cli.db")
	if !strings.HasPrefix(cliConfigDir, "/") {
		oldCliPath := fmt.Sprintf("%sente-cli.db", cliConfigDir)
		if _, err := os.Stat(oldCliPath); err == nil {
			log.Printf("migrating old cli db from %s to %s\n", oldCliPath, newCliDBPath)
			if err := os.Rename(oldCliPath, newCliDBPath); err != nil {
				log.Fatalf("Could not rename old cli db\n%v\n", err)
			}
		}
	}
	db, err := pkg.GetDB(newCliDBPath)

	if err != nil {
		if strings.Contains(err.Error(), "timeout") {
			log.Fatalf("Please close all other instances of the cli and try again\n%v\n", err)
		} else {
			panic(err)
		}
	}

	defer func() {
		if err := db.Close(); err != nil {
			panic(err)
		}
	}()
	ctrl := pkg.ClICtrl{
		Client: api.NewClient(api.Params{
			Debug: viper.GetBool("log.http"),
			Host:  viper.GetString("endpoint.api"),
		}),
		DB: db,
	}

	if len(os.Args) == 1 {
		os.Args = append(os.Args, "help")
	}
	if len(os.Args) == 2 && os.Args[1] == "docs" {
		log.Println("Generating docs")
		err = cmd.GenerateDocs()
		if err != nil {
			log.Fatal(err)
		}
		return
	}
	if os.Args[1] == "version" && viper.GetString("endpoint.api") != constants.EnteApiUrl {
		log.Printf("Custom endpoint: %s\n", viper.GetString("endpoint.api"))
	}
	cmd.Execute(&ctrl, AppVersion, checkWorkingDirectoryConfig(cliConfigDir))
}

func initConfig(cliConfigDir string) error {
	viper.SetConfigType("yaml")
	path, err := findConfigFile(cliConfigDir)
	if err != nil {
		return fmt.Errorf("cannot inspect trusted configuration directory %q", cliConfigDir)
	}
	if path != "" {
		viper.SetConfigFile(path)
		if err := viper.ReadInConfig(); err != nil {
			return fmt.Errorf("cannot load trusted configuration %q; check file permissions and YAML syntax", path)
		}
	}
	value := viper.Get("endpoint.api")
	keys := viper.AllKeys()
	if value != nil || slices.Contains(keys, "endpoint") || slices.Contains(keys, "endpoint.api") {
		endpoint, ok := value.(string)
		if !ok || strings.TrimSpace(endpoint) == "" {
			return fmt.Errorf("invalid endpoint.api in trusted configuration %q; expected a non-empty string", path)
		}
	}
	viper.SetDefault("endpoint.api", constants.EnteApiUrl)
	viper.SetDefault("log.http", false)
	return nil
}

func findConfigFile(dir string) (string, error) {
	info, err := os.Stat(dir)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("%q is not a directory", dir)
	}
	for i := 0; i <= len(viper.SupportedExts); i++ {
		name := "config"
		if i < len(viper.SupportedExts) {
			name += "." + viper.SupportedExts[i]
		}
		path := filepath.Join(dir, name)
		info, err := os.Lstat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return "", err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			info, err = os.Stat(path)
			if err != nil {
				return "", err
			}
		}
		if !info.IsDir() {
			return path, nil
		}
	}
	return "", nil
}

func checkWorkingDirectoryConfig(cliConfigDir string) error {
	cwd, err := os.Stat(".")
	if err != nil {
		return fmt.Errorf("cannot inspect the working directory")
	}
	trustedDir, err := os.Stat(cliConfigDir)
	if err != nil {
		return fmt.Errorf("cannot inspect trusted configuration directory %q", cliConfigDir)
	}
	if os.SameFile(cwd, trustedDir) {
		return nil
	}
	path, err := findConfigFile(".")
	if err != nil {
		return fmt.Errorf("cannot inspect working-directory configuration")
	}
	if path != "" {
		return fmt.Errorf("refusing network command: working-directory configuration %q is ignored. If it contains your intended Ente CLI settings, migrate them into %q and remove or rename the old file; otherwise run from another directory. ENTE_CLI_CONFIG_DIR selects both configuration and account storage", path, cliConfigDir)
	}
	return nil
}

func GetCLIConfigDir() (string, error) {
	var configDir = os.Getenv("ENTE_CLI_CONFIG_DIR")

	if configDir == "" {
		// ENTE_CLI_CONFIG_PATH is kept for backward compatibility.
		configDir = os.Getenv("ENTE_CLI_CONFIG_PATH")
	}

	if configDir != "" {
		return filepath.Clean(configDir), nil
	}
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}

	cliDBPath := filepath.Join(homeDir, ".ente")

	if _, err := os.Stat(cliDBPath); os.IsNotExist(err) {
		err := os.MkdirAll(cliDBPath, 0755)
		if err != nil {
			return "", err
		}
	}

	return cliDBPath, nil
}
