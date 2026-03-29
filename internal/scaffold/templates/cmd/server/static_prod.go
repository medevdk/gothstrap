//go:build prod

package main

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed ui
var staticFiles embed.FS

func staticHandler() http.Handler {
	static, _ := fs.Sub(staticFiles, "static")
	return http.FileServer(http.FS(static))
}
