package cmd

import (
	"fmt"
	"os"
	"runtime"

	"github.com/ente/cli/pkg"
	"github.com/spf13/cobra/doc"

	"github.com/spf13/viper"

	"github.com/spf13/cobra"
)

var version string

var ctrl *pkg.ClICtrl

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "ente",
	Short: "CLI tool for exporting your photos from Ente",
}

func GenerateDocs() error {
	return doc.GenMarkdownTree(rootCmd, "./docs/generated")
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute(controller *pkg.ClICtrl, ver string) {
	ctrl = controller
	version = ver
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	// rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.cli-go.yaml)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
	viper.SetConfigName("config") // Name of your configuration file (e.g., config.yaml)
	viper.AddConfigPath(".")      // Search for config file in the current directory
	viper.ReadInConfig()          // Read the configuration file if it exists
}

func recoverWithLog() {
	if r := recover(); r != nil {
		fmt.Println("Panic occurred:", r)
		// Print the stack trace
		stackTrace := make([]byte, 1024*8)
		stackTrace = stackTrace[:runtime.Stack(stackTrace, false)]
		fmt.Printf("Stack Trace:\n%s", stackTrace)
	}
}
