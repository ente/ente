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
	initConfig(cliConfigDir)
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

	// Define a set of commands that do not require KeyHolder or cli initialisation.
	skipInitCommands := map[string]struct{}{"version": {}, "docs": {}, "help": {}}

	var keyHolder *secrets.KeyHolder
	// Only initialise KeyHolder if the command isn't in the skip list.
	shouldInit := len(os.Args) > 1
	if len(os.Args) > 1 {
		if _, skip := skipInitCommands[os.Args[1]]; skip {
			shouldInit = false
		}
	}

	if shouldInit {
		keyHolder = secrets.NewKeyHolder(secrets.GetOrCreateClISecret())
	}
	ctrl := pkg.ClICtrl{
		Client: api.NewClient(api.Params{
			Debug: viper.GetBool("log.http"),
			Host:  viper.GetString("endpoint.api"),
		}),
		DB:        db,
		KeyHolder: keyHolder,
	}

	if len(os.Args) == 1 {
		// If no arguments are passed, show help
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
	if shouldInit {
		err = ctrl.Init()
		if err != nil {
			panic(err)
		}
		defer func() {
			if err := db.Close(); err != nil {
				panic(err)
			}
		}()
	}
	if os.Args[1] == "version" && viper.GetString("endpoint.api") != constants.EnteApiUrl {
		log.Printf("Custom endpoint: %s\n", viper.GetString("endpoint.api"))
	}
	cmd.Execute(&ctrl, AppVersion)
}

func initConfig(cliConfigDir string) {
	viper.SetConfigName("config")           // name of config file (without extension)
	viper.SetConfigType("yaml")             // REQUIRED if the config file does not have the extension in the name
	viper.AddConfigPath(cliConfigDir + "/") // path to look for the config file in
	viper.AddConfigPath(".")                // optionally look for config in the working directory

	viper.SetDefault("endpoint.api", constants.EnteApiUrl)
	viper.SetDefault("log.http", false)
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
		} else {
			// Config file was found but another error was produced
		}
	}
}

// GetCLIConfigDir returns the path to the .ente-cli folder and creates it if it doesn't exist.
func GetCLIConfigDir() (string, error) {
	var configDir = os.Getenv("ENTE_CLI_CONFIG_DIR")

	if configDir == "" {
		// for backward compatibility, check for ENTE_CLI_CONFIG_PATH
		configDir = os.Getenv("ENTE_CLI_CONFIG_PATH")
	}

	if configDir != "" {
		// remove trailing slash (for all OS)
		configDir = strings.TrimSuffix(configDir, string(filepath.Separator))
		return configDir, nil
	}
	// Get the user's home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}

	cliDBPath := filepath.Join(homeDir, ".ente")

	// Check if the folder already exists, if not, create it
	if _, err := os.Stat(cliDBPath); os.IsNotExist(err) {
		err := os.MkdirAll(cliDBPath, 0755)
		if err != nil {
			return "", err
		}
	}

	return cliDBPath, nil
}
