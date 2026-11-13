package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage configuration settings",
}

var showCmd = &cobra.Command{
	Use:   "show",
	Short: "Show configuration settings",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("host:", viper.GetString("host"))
	},
}

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update a configuration setting",
	Run: func(cmd *cobra.Command, args []string) {
		viper.Set("host", host)
		err := viper.WriteConfig()
		if err != nil {
			fmt.Println("Error updating 'host' configuration:", err)
			return
		}
		fmt.Println("Updating 'host' configuration:", host)
	},
}

var host string

func init() {
	viper.SetDefault("host", "https://api.ente.com")

	updateCmd.Flags().StringVarP(&host, "host", "H", viper.GetString("host"), "Update the 'host' configuration")
	updateCmd.MarkFlagRequired("host")

	configCmd.AddCommand(showCmd, updateCmd)
}
