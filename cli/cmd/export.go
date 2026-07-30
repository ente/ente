package cmd

import (
	"github.com/ente/cli/pkg/model"
	"github.com/spf13/cobra"
)

// exportCmd represents the export command
var exportCmd = &cobra.Command{
	Use:   "export",
	Short: "Starts the export process",
	Long:  ``,
	Run: func(cmd *cobra.Command, args []string) {
		// Retrieve flag values
		shared, _ := cmd.Flags().GetBool("shared")
		hidden, _ := cmd.Flags().GetBool("hidden")
		albums, _ := cmd.Flags().GetStringSlice("albums")
		emails, _ := cmd.Flags().GetStringSlice("emails")
		excludeAlbums, _ := cmd.Flags().GetStringSlice("exclude-albums")
		// Create Filters struct with flag values
		filters := model.Filter{
			ExcludeShared: !shared,
			ExcludeHidden: !hidden,
			ExcludeAlbums: excludeAlbums,
			Albums:        albums,
			Emails:        emails,
		}
		// Call the Export function with the filters
		ctrl.Export(filters)
	},
}

func init() {
	rootCmd.AddCommand(exportCmd)

	// Add flags for Filters struct fields with default value true
	exportCmd.Flags().Bool("shared", true, "to exclude shared albums, pass --shared=false")
	exportCmd.Flags().Bool("hidden", true, "to exclude hidden albums, pass --hidden=false")
	exportCmd.Flags().StringSlice("albums", []string{}, "Comma-separated list of album names to export")
	exportCmd.Flags().StringSlice("emails", []string{}, "Comma-separated list of emails to export files shared with")
	exportCmd.Flags().StringSlice("exclude-albums", []string{}, "Comma-separated list of album names to exclude")
}
