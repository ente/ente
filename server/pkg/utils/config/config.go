// The config package contains functions for configuring Viper.
//
// # Configuration
//
// We use the Viper package to read in configuration from YAML files. In
// addition, we also read in values from the OS environment. These values
// override the ones in the config files.
//
// The names of the OS environment variables should be
//
//   - prefixed with 'ENTE_',
//
//   - uppercased versions of the config file variable names,
//
//   - dashes are replaced with '_',
//
//   - for nested config variables, dots should be replaced with '_'.
//
// For example, the environment variable corresponding to
//
//	foo:
//	    bar-baz: quux
//
// would be `ENTE_FOO_BAR_BAZ`.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/ente/stacktrace"
	"github.com/spf13/viper"
)

func ConfigureViper(environment string) error {
	// Ask Viper to read in values from the environment. These values will
	// override the values specified in the config files.
	viper.AutomaticEnv()
	// Set the prefix for the environment variables that Viper will look for.
	viper.SetEnvPrefix("ENTE")
	// Ask Viper to look for underscores (instead of dots) for nested configs.
	// Also replace "-" with underscores since "-" cannot be used in environment
	// variable names.
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_", "-", "_"))

	viper.SetConfigFile("configurations/" + environment + ".yaml")
	err := viper.ReadInConfig()
	if err != nil {
		return err
	}

	credentialsFile := viper.GetString("credentials-file")
	if credentialsFile == "" {
		credentialsFile = "credentials.yaml"
	}
	err = mergeConfigFileIfExists(credentialsFile)
	if err != nil {
		return err
	}

	err = mergeConfigFileIfExists("museum.yaml")
	if err != nil {
		return err
	}

	return nil
}

func mergeConfigFileIfExists(configFile string) error {
	configFileExists, err := doesFileExist(configFile)
	if err != nil {
		return err
	}
	if configFileExists {
		viper.SetConfigFile(configFile)
		err = viper.MergeInConfig()
		if err != nil {
			return err
		}
	}

	return nil
}

func doesFileExist(path string) (bool, error) {
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	if info == nil {
		return false, nil
	}
	// Return false if the stat entry exists, but is a directory.
	//
	// This allows us to ignore the default museum.yaml directory that gets
	// mounted on a fresh checkout.
	if info.IsDir() {
		return false, nil
	}
	return true, nil
}

func GetPGInfo() string {
	return fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=%s %s",
		viper.GetString("db.host"),
		viper.GetInt("db.port"),
		viper.GetString("db.user"),
		viper.GetString("db.password"),
		viper.GetString("db.name"),
		viper.GetString("db.sslmode"),
		viper.GetString("db.extra"))
}

func IsLocalEnvironment() bool {
	evn := os.Getenv("ENVIRONMENT")
	return evn == "" || evn == "local"
}

// CredentialFilePath returns the path to an existing file in the credentials
// directory.
//
// This file must exist if we're running in a non-local configuration.
//
// By default, it search in the credentials/ directory, but that can be
// customized using the "credentials-dir" config option.
func CredentialFilePath(name string) (string, error) {
	credentialsDir := viper.GetString("credentials-dir")
	if credentialsDir == "" {
		credentialsDir = "credentials"
	}

	path := credentialsDir + "/" + name
	return productionFilePath(path)
}

// BillingConfigFilePath returns the path to an existing file in the
// billing directory.
//
// This file must exist if we're running in a non-local configuration.
//
// By default, it search in the data/billing directory, but that can be
// customized using the "billing-config-dir" config option.
func BillingConfigFilePath(name string) (string, error) {
	billingConfigDir := viper.GetString("billing-config-dir")
	if billingConfigDir == "" {
		billingConfigDir = "data/billing/"
	}

	path := billingConfigDir + name
	return productionFilePath(path)
}

func productionFilePath(path string) (string, error) {
	pathExists, err := doesFileExist(path)
	if err != nil {
		return "", stacktrace.Propagate(err, "")
	}
	if pathExists {
		return path, nil
	}
	// The path must exist if we're running in production (or more precisely, in
	// any non-local environment).
	if IsLocalEnvironment() {
		return "", nil
	}
	return "", fmt.Errorf("required file not found at %s", path)
}
