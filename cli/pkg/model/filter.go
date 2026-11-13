package model

import (
	"log"
	"strings"
)

type Filter struct {
	ExcludeShared bool
	ExcludeSharedFiles bool
	ExcludeHidden bool
	Albums []string
	Emails []string
	ExcludeAlbums []string
}

func (f Filter) SkipAccount(email string) bool {
	if len(f.Emails) == 0 {
		return false
	}
	for _, e := range f.Emails {
		if strings.ToLower(e) == strings.ToLower(strings.TrimSpace(email)) {
			return false
		}
	}
	return true
}

func (f Filter) SkipAlbum(album RemoteAlbum, shouldLog bool) bool {
	if f.excludeByName(album) {
		if shouldLog {
			log.Printf("Skipping album %s as it's not part of album to export", album.AlbumName)
		}
		return true
	}
	if f.ExcludeShared && album.IsShared {
		if shouldLog {
			log.Printf("Skipping album %s as it's shared", album.AlbumName)
		}
		return true
	}
	if f.ExcludeHidden && album.IsHidden() {
		if shouldLog {
			log.Printf("Skipping album %s as it's hidden", album.AlbumName)
		}
		return true
	}
	return false
}

func (f Filter) excludeByName(album RemoteAlbum) bool {
	for _, a := range f.ExcludeAlbums {
		if strings.ToLower(a) == strings.ToLower(strings.TrimSpace(album.AlbumName)) {
			return true
		}
	}

	if len(f.Albums) > 0 {
		for _, a := range f.Albums {
			if strings.ToLower(a) == strings.ToLower(strings.TrimSpace(album.AlbumName)) {
				return false
			}
		}
		return true
	}
	return false
}
