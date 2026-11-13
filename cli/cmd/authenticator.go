package cmd

import (
	"github.com/ente/cli/pkg/authenticator"
	"github.com/spf13/cobra"
)

var authenticatorCmd = &cobra.Command{
	Use:   "auth",
	Short: "Authenticator commands",
}

var decryptExportCmd = &cobra.Command{
	Use:   "decrypt [input] [output]",
	Short: "Decrypt authenticator export",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		inputPath := args[0]
		outputPath := args[1]

		password, _ := cmd.Flags().GetString("password")

		return authenticator.DecryptExport(inputPath, outputPath, password)
	},
}

func init() {
	decryptExportCmd.Flags().StringP("password", "p", "", "Password for decryption")

	rootCmd.AddCommand(authenticatorCmd)
	authenticatorCmd.AddCommand(decryptExportCmd)
}
