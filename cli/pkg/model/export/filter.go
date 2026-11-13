package export

type Filters struct {
	ExcludeShared bool
	ExcludeSharedFiles bool
	ExcludeHidden bool
	Albums []string
	Emails []string
	ExcludeAlbums []string
}
