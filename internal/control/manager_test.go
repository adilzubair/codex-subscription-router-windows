package control

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestManagerPageIsEmbeddedWithStrictCSP(t *testing.T) {
	server := New("127.0.0.1:0", strings.Repeat("a", 64), nil, false)
	request := httptest.NewRequest(http.MethodGet, "/manager", nil)
	response := httptest.NewRecorder()

	server.http.Handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("manager returned %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), "Subscription Router") {
		t.Fatal("manager page is missing its heading")
	}
	csp := response.Header().Get("Content-Security-Policy")
	if !strings.Contains(csp, "default-src 'none'") || !strings.Contains(csp, "connect-src 'self'") {
		t.Fatalf("manager CSP is not restrictive enough: %q", csp)
	}
}

func TestUnknownManagerPathReturnsNotFound(t *testing.T) {
	server := New("127.0.0.1:0", strings.Repeat("b", 64), nil, false)
	request := httptest.NewRequest(http.MethodGet, "/not-a-route", nil)
	response := httptest.NewRecorder()

	server.http.Handler.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("unknown route returned %d", response.Code)
	}
}
