package cmd

import (
	"context"
	"fmt"
	"github.com/ente/cli/pkg/model"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"strings"
)

var _adminCmd = &cobra.Command{
	Use:   "admin",
	Short: "Commands for admin actions",
	Long:  "Commands for admin actions like disable or enabling 2fa, bumping up the storage limit, etc.",
}

var _userDetailsCmd = &cobra.Command{
	Use:   "get-user-id",
	Short: "Get user id",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
			if f.Name == "user" {
				flags.UserEmail = f.Value.String()
			}
		})
		if flags.UserEmail == "" {
			return fmt.Errorf("user email is required")
		}
		return ctrl.GetUserId(context.Background(), *flags)
	},
}

var _disable2faCmd = &cobra.Command{
	Use:   "disable-2fa",
	Short: "Disable 2fa for a user",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
			if f.Name == "user" {
				flags.UserEmail = f.Value.String()
			}
		})
		if flags.UserEmail == "" {
			return fmt.Errorf("user email is required")
		}
		return ctrl.Disable2FA(context.Background(), *flags)

	},
}

var _disablePasskeyCmd = &cobra.Command{
	Use:   "disable-passkey",
	Short: "Disable passkey for a user",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
			if f.Name == "user" {
				flags.UserEmail = f.Value.String()
			}
		})
		if flags.UserEmail == "" {
			return fmt.Errorf("user email is required")
		}
		return ctrl.DisablePasskeys(context.Background(), *flags)
	},
}

var _deleteUser = &cobra.Command{
	Use:   "delete-user",
	Short: "Delete  a user",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
			if f.Name == "user" {
				flags.UserEmail = f.Value.String()
			}
		})
		if flags.UserEmail == "" {
			return fmt.Errorf("user email is required")
		}
		return ctrl.DeleteUser(context.Background(), *flags)

	},
}

var _listUsers = &cobra.Command{
	Use:   "list-users",
	Short: "List all users",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
		})
		return ctrl.ListUsers(context.Background(), *flags)
	},
}

var _updateFreeUserStorage = &cobra.Command{
	Use:   "update-subscription",
	Short: "Update subscription for user",
	Long:  "Update subscription for the free user. If you want to apply specific limits, use the `--no-limit False` flag",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		noLimit := false
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
			if f.Name == "user" {
				flags.UserEmail = f.Value.String()
			}
			if f.Name == "no-limit" {
				noLimit = strings.ToLower(f.Value.String()) == "true"
			}
		})
		if flags.UserEmail == "" {
			return fmt.Errorf("user email is required")
		}
		return ctrl.UpdateFreeStorage(context.Background(), *flags, noLimit)
	},
}

var _sendMail = &cobra.Command{
	Use:   "send-mail <to-email> <from-email> <from-name>",
	Args:  cobra.ExactArgs(3),
	Short: "Sends a test mail via the admin api",
	RunE: func(cmd *cobra.Command, args []string) error {
		recoverWithLog()
		var flags = &model.AdminActionForUser{}
		cmd.Flags().VisitAll(func(f *pflag.Flag) {
			if f.Name == "admin-user" {
				flags.AdminEmail = f.Value.String()
			}
		})
		return ctrl.SendTestMail(context.Background(), *flags, args[0], args[1], args[2])
	},
}

func init() {
	rootCmd.AddCommand(_adminCmd)
	_ = _userDetailsCmd.MarkFlagRequired("admin-user")
	_ = _userDetailsCmd.MarkFlagRequired("user")
	_userDetailsCmd.Flags().StringP("admin-user", "a", "", "The email of the admin user. ")
	_userDetailsCmd.Flags().StringP("user", "u", "", "The email of the user to fetch details for. (required)")
	_listUsers.Flags().StringP("admin-user", "a", "", "The email of the admin user. ")
	_disable2faCmd.Flags().StringP("admin-user", "a", "", "The email of the admin user. ")
	_disable2faCmd.Flags().StringP("user", "u", "", "The email of the user to disable 2FA for. (required)")
	_disablePasskeyCmd.Flags().StringP("admin-user", "a", "", "The email of the admin user. ")
	_disablePasskeyCmd.Flags().StringP("user", "u", "", "The email of the user to disable passkey for. (required)")
	_deleteUser.Flags().StringP("admin-user", "a", "", "The email of the admin user. ")
	_deleteUser.Flags().StringP("user", "u", "", "The email of the user to delete. (required)")
	_updateFreeUserStorage.Flags().StringP("admin-user", "a", "", "The email of the admin user.")
	_updateFreeUserStorage.Flags().StringP("user", "u", "", "The email of the user to update subscription for. (required)")
	// add a flag with no value --no-limit
	_updateFreeUserStorage.Flags().String("no-limit", "True", "When true, sets 100TB as storage limit, and expiry to current date + 100 years")
	_sendMail.Flags().StringP("admin-user", "a", "", "The email of the admin user.")
	_adminCmd.AddCommand(_userDetailsCmd, _disable2faCmd, _disablePasskeyCmd, _updateFreeUserStorage, _listUsers, _deleteUser, _sendMail)
}
