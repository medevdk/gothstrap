package middleware

import (
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"runtime/debug"
	"strings"
	"time"
)

type responseWriter struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (rw *responseWriter) WriteHeader(code int) {
	if rw.wroteHeader {
		return
	}
	rw.status = code
	rw.wroteHeader = true
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	if !rw.wroteHeader {
		rw.WriteHeader(http.StatusOK)
	}
	return rw.ResponseWriter.Write(b)
}

func Chain(h http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		h = middlewares[i](h)
	}
	return h
}

func LogRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Capture the start time to log duration
		start := time.Now()
		ip, _, _ := net.SplitHostPort(r.RemoteAddr)

		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rw, r)

		slog.Info("request",
			"status", rw.status,
			"method", r.Method,
			"path", r.URL.Path,
			"query", r.URL.RawQuery,
			"ip", ip,
			"duration", time.Since(start).Round(time.Millisecond),
		)
	})
}

func CommonHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Set HTML headers for non-static routes
		if !strings.HasPrefix(r.URL.Path, "/static/") {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("X-Content-Type-Options", "no-sniff")
			w.Header().Set("X-Frame-Options", "deny")
		}
		next.ServeHTTP(w, r)
	})
}

func RecoverPanic(serverError func(http.ResponseWriter, *http.Request, error)) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if err := recover(); err != nil {
					w.Header().Set("Connection", "close")
					slog.Error("panic recovered",
						"error", err,
						"trace", string(debug.Stack()),
					)
					serverError(w, r, fmt.Errorf("%s", err))
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}
