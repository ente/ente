package cmd

import (
	"github.com/ente/cli/pkg/model"
	"github.com/spf13/cobra"
)

var exportCmd = &cobra.Command{
	Use:   "export",
	Short: "Starts the export process",
	Long:  ``,
	Run: func(cmd *cobra.Command, args []string) {
		shared, _ := cmd.Flags().GetBool("shared")
		hidden, _ := cmd.Flags().GetBool("hidden")
		albums, _ := cmd.Flags().GetStringSlice("albums")
		emails, _ := cmd.Flags().GetStringSlice("emails")
		excludeAlbums, _ := cmd.Flags().GetStringSlice("exclude-albums")
		filters := model.Filter{
			ExcludeShared: !shared,
			ExcludeHidden: !hidden,
			ExcludeAlbums: excludeAlbums,
			Albums:        albums,
			Emails:        emails,
		}
		ctrl.Export(filters)
	},
}

func init() {
	rootCmd.AddCommand(exportCmd)

	exportCmd.Flags().Bool("shared", true, "to exclude shared albums, pass --shared=false")
	exportCmd.Flags().Bool("hidden", true, "to exclude hidden albums, pass --hidden=false")
	exportCmd.Flags().StringSlice("albums", []string{}, "Comma-separated list of album names to export")
	exportCmd.Flags().StringSlice("emails", []string{}, "Comma-separated list of emails to export files shared with")
	exportCmd.Flags().StringSlice("exclude-albums", []string{}, "Comma-separated list of album names to exclude")
}
