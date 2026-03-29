//go:build !prod

package main

import "net/http"

func staticHandler() http.Handler {
	return http.FileServer(http.Dir("./static"))
}
