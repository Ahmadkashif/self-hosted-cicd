package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestUp(t *testing.T) {
	rec := httptest.NewRecorder()
	(&server{}).routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/up", nil))
	if rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "ok" {
		t.Fatalf("GET /up = %d %q, want 200 ok", rec.Code, rec.Body.String())
	}
}

func TestHello(t *testing.T) {
	rec := httptest.NewRecorder()
	(&server{}).routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK || !strings.HasPrefix(rec.Body.String(), "hello from ") {
		t.Fatalf("GET / = %d %q", rec.Code, rec.Body.String())
	}
}

func TestVisitsWithoutDB(t *testing.T) {
	rec := httptest.NewRecorder()
	(&server{}).routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/visits", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("GET /visits without DB = %d, want 503", rec.Code)
	}
}

func TestVersionIsJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	(&server{}).routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/version", nil))
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("GET /version Content-Type = %q, want application/json", ct)
	}
}
