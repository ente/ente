package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Prints the current version",
	Long:  ``,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("Version %s\n", version)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
