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

var rootCmd = &cobra.Command{
	Use:   "ente",
	Short: "CLI tool for exporting your photos from Ente",
}

func GenerateDocs() error {
	return doc.GenMarkdownTree(rootCmd, "./docs/generated")
}

func Execute(controller *pkg.ClICtrl, ver string) {
	ctrl = controller
	version = ver
	if code := exitCode(rootCmd.Execute()); code != 0 {
		os.Exit(code)
	}
}

// exitCode maps the outcome of a command to the process exit code. A failed
// command, such as an export whose account sync errored, must not look like a
// success to scripts and cron jobs.
func exitCode(err error) int {
	if err != nil {
		return 1
	}
	return 0
}

func init() {
	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
	viper.SetConfigName("config")
	viper.AddConfigPath(".")
	viper.ReadInConfig()
}

func recoverWithLog() {
	if r := recover(); r != nil {
		fmt.Println("Panic occurred:", r)
		stackTrace := make([]byte, 1024*8)
		stackTrace = stackTrace[:runtime.Stack(stackTrace, false)]
		fmt.Printf("Stack Trace:\n%s", stackTrace)
	}
}
