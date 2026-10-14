// hello is a tiny HTTP service used to verify the self-hosted CI/CD blueprint end to end.
//
//	GET /up      health check used by kamal-proxy (200 "ok")
//	GET /        "hello from <version>"
//	GET /visits  increments and returns a counter in Postgres (503 if DATABASE_URL is unset)
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"example.com/hello/internal/store"
)

// version is set at build time: -ldflags "-X main.version=<git sha>".
var version = "dev"

type server struct {
	store *store.Store
}

func (s *server) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /up", s.up)
	mux.HandleFunc("GET /{$}", s.hello)
	mux.HandleFunc("GET /visits", s.visits)
	mux.HandleFunc("GET /version", s.versionInfo)
	return mux
}

func (s *server) up(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ok")
}

func (s *server) hello(w http.ResponseWriter, _ *http.Request) {
	fmt.Fprintf(w, "hello from %s\n", version)
}

func (s *server) versionInfo(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, "{\"version\": %q}\n", version)
}

func (s *server) visits(w http.ResponseWriter, r *http.Request) {
	if s.store == nil {
		http.Error(w, "no database configured", http.StatusServiceUnavailable)
		return
	}
	n, err := s.store.Incr(r.Context(), "visits")
	if err != nil {
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}
	fmt.Fprintf(w, "%d\n", n)
}

func main() {
	srv := &server{}
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		st, err := store.Open(ctx, dsn)
		cancel()
		if err != nil {
			log.Fatalf("database: %v", err)
		}
		srv.store = st
	}
	addr := ":" + envOr("PORT", "3000")
	log.Printf("hello %s listening on %s", version, addr)
	h := &http.Server{Addr: addr, Handler: srv.routes(), ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(h.ListenAndServe())
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
