package cmd

import (
	"context"
	"fmt"
	"github.com/ente/cli/internal/api"
	"github.com/ente/cli/pkg/model"
	"github.com/spf13/cobra"
)

// Define the 'account' command and its subcommands
var accountCmd = &cobra.Command{
	Use:   "account",
	Short: "Manage account settings",
}

// Subcommand for 'account list'
var listAccCmd = &cobra.Command{
	Use:   "list",
	Short: "list configured accounts",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		return ctrl.ListAccounts(context.Background())
	},
}

// Subcommand for 'account add'
var addAccCmd = &cobra.Command{
	Use:   "add",
	Short: "login into existing account",
	Long:  "Use this command to add an existing account to cli. For creating a new account, use the mobile,web or desktop app",
	Run: func(cmd *cobra.Command, args []string) {
		recoverWithLog()
		ctrl.AddAccount(context.Background())
	},
}

// Subcommand for 'account update'
var updateAccCmd = &cobra.Command{
	Use:   "update",
	Short: "Update an existing account's export directory",
	Run: func(cmd *cobra.Command, args []string) {
		recoverWithLog()
		exportDir, _ := cmd.Flags().GetString("dir")
		app, _ := cmd.Flags().GetString("app")
		email, _ := cmd.Flags().GetString("email")
		if email == "" {
			fmt.Println("email must be specified")
			return
		}
		if exportDir == "" {
			fmt.Println("dir param must be specified")
			return
		}

		validApps := map[string]bool{
			"photos": true,
			"locker": true,
			"auth":   true,
		}

		if !validApps[app] {
			fmt.Printf("invalid app. Accepted values are 'photos', 'locker', 'auth'")

		}
		err := ctrl.UpdateAccount(context.Background(), model.AccountCommandParams{
			Email:     email,
			App:       api.StringToApp(app),
			ExportDir: &exportDir,
		})
		if err != nil {
			fmt.Printf("Error updating account: %v\n", err)
		}
	},
}

// Subcommand for 'account update'
var getTokenCmd = &cobra.Command{
	Use:   "get-token",
	Short: "Get token for an account for a specific app",
	Run: func(cmd *cobra.Command, args []string) {
		recoverWithLog()
		app, _ := cmd.Flags().GetString("app")
		email, _ := cmd.Flags().GetString("email")
		if email == "" {

			fmt.Println("email must be specified, use --help for more information")
			// print help
			return
		}

		validApps := map[string]bool{
			"photos": true,
			"locker": true,
			"auth":   true,
		}

		if !validApps[app] {
			fmt.Printf("invalid app. Accepted values are 'photos', 'locker', 'auth'")

		}
		err := ctrl.GetToken(context.Background(), model.AccountCommandParams{
			Email: email,
			App:   api.StringToApp(app),
		})
		if err != nil {
			fmt.Printf("Error getting token for %s (app:%s): %v\n", email, app, err)
		}
	},
}

func init() {
	// Add 'config' subcommands to the root command
	rootCmd.AddCommand(accountCmd)
	// Add 'config' subcommands to the 'config' command
	updateAccCmd.Flags().String("dir", "", "update export directory")
	updateAccCmd.Flags().String("email", "", "email address of the account")
	updateAccCmd.Flags().String("app", "photos", "Specify the app, default is 'photos'")
	getTokenCmd.Flags().String("email", "", "email address of the account")
	getTokenCmd.Flags().String("app", "photos", "Specify the app, default is 'photos'")
	accountCmd.AddCommand(listAccCmd, addAccCmd, updateAccCmd, getTokenCmd)
}
