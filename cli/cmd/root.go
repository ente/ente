package cmd

import (
	"fmt"
	"os"
	"runtime"

	"github.com/ente/cli/pkg"
	"github.com/ente/cli/pkg/secrets"
	"github.com/spf13/cobra"
	"github.com/spf13/cobra/doc"
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

func Execute(controller *pkg.ClICtrl, ver string, networkConfigErr error) {
	ctrl = controller
	version = ver
	rootCmd.PersistentPreRunE = func(command *cobra.Command, args []string) error {
		network := command == exportCmd || command == addAccCmd || command.Parent() == _adminCmd
		if network && networkConfigErr != nil {
			return networkConfigErr
		}
		if network || command.Parent() == accountCmd {
			ctrl.KeyHolder = secrets.NewKeyHolder(secrets.GetOrCreateClISecret())
			return ctrl.Init()
		}
		return nil
	}
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}

func recoverWithLog() {
	if r := recover(); r != nil {
		fmt.Println("Panic occurred:", r)
		stackTrace := make([]byte, 1024*8)
		stackTrace = stackTrace[:runtime.Stack(stackTrace, false)]
		fmt.Printf("Stack Trace:\n%s", stackTrace)
	}
}
