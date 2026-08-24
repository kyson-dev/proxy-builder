package subscription

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestServerHTTPContract(t *testing.T) {
	tests := []struct {
		name        string
		method      string
		target      string
		status      int
		code        string
		contentType string
	}{
		{"health", http.MethodGet, "/healthz", 200, "", "application/json"},
		{"health method", http.MethodPost, "/healthz", 405, "method_not_allowed", "application/json"},
		{"missing token", http.MethodGet, "/v1/subscription?format=base64", 400, "missing_token", "application/json"},
		{"invalid format", http.MethodGet, "/v1/subscription?token=" + testToken, 400, "invalid_format", "application/json"},
		{"invalid token", http.MethodGet, "/v1/subscription?token=invalid-token-value-123456&format=base64", 401, "invalid_token", "application/json"},
		{"disabled", http.MethodGet, "/v1/subscription?token=subscription-token-disabled-1&format=base64", 403, "user_disabled", "application/json"},
		{"base64", http.MethodGet, "/v1/subscription?token=" + testToken + "&format=base64", 200, "", "text/plain; charset=utf-8"},
		{"clash", http.MethodGet, "/v1/subscription?token=" + testToken + "&format=clash", 200, "", "text/yaml; charset=utf-8"},
		{"not found", http.MethodGet, "/other", 404, "not_found", "application/json"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var logs bytes.Buffer
			server := NewServer(validConfig(), log.New(&logs, "", 0))
			server.requestID = func() string { return "request-id" }
			request := httptest.NewRequest(test.method, test.target, nil)
			response := httptest.NewRecorder()
			server.ServeHTTP(response, request)
			if response.Code != test.status {
				t.Fatalf("status = %d, want %d; body=%s", response.Code, test.status, response.Body.String())
			}
			if !strings.HasPrefix(response.Header().Get("Content-Type"), test.contentType) {
				t.Fatalf("Content-Type = %q", response.Header().Get("Content-Type"))
			}
			if strings.HasPrefix(test.target, "/v1/subscription") && response.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("subscription response is cacheable")
			}
			if response.Header().Get("X-Request-ID") != "request-id" {
				t.Fatal("missing request ID")
			}
			if test.code != "" {
				var body struct {
					Error struct {
						Code string `json:"code"`
					} `json:"error"`
				}
				if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil || body.Error.Code != test.code {
					t.Fatalf("error body = %s", response.Body.String())
				}
			}
			for _, secret := range []string{testToken, testPassword, testObfs, "00000000-0000-4000-8000-000000000001", "alice"} {
				if strings.Contains(logs.String(), secret) {
					t.Fatalf("logs contain secret value")
				}
			}
		})
	}
}

func TestServerPanicIsSanitized(t *testing.T) {
	var logs bytes.Buffer
	server := NewServer(validConfig(), log.New(&logs, "", 0))
	server.requestID = func() string { return "request-id" }
	server.beforeServe = func(*http.Request) { panic(testToken) }
	response := httptest.NewRecorder()
	server.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if response.Code != http.StatusInternalServerError || !strings.Contains(response.Body.String(), "internal_error") {
		t.Fatalf("panic response = %d %s", response.Code, response.Body.String())
	}
	if strings.Contains(logs.String(), testToken) {
		t.Fatal("panic value leaked to logs")
	}
}
