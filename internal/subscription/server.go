package subscription

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

type tokenUser struct {
	digest [sha256.Size]byte
	user   contracts.User
}

type Server struct {
	config      Config
	users       []tokenUser
	logger      *log.Logger
	requestID   func() string
	beforeServe func(*http.Request)
}

func NewServer(config Config, logger *log.Logger) *Server {
	users := make([]tokenUser, 0, len(config.Users.Users))
	for _, user := range config.Users.Users {
		users = append(users, tokenUser{digest: sha256.Sum256([]byte(user.SubscriptionToken)), user: user})
	}
	if logger == nil {
		logger = log.New(io.Discard, "", 0)
	}
	return &Server{config: config, users: users, logger: logger, requestID: randomRequestID}
}

type requestResult struct {
	PathType string
	Status   int
	Format   string
	UserID   string
}

func (server *Server) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	started := time.Now()
	requestID := server.requestID()
	writer.Header().Set("X-Request-ID", requestID)
	result := requestResult{PathType: pathType(request.URL.Path), Status: http.StatusInternalServerError}
	recorder := &statusRecorder{ResponseWriter: writer}

	defer func() {
		if recover() != nil {
			if !recorder.wroteHeader {
				writeError(recorder, http.StatusInternalServerError, "internal_error", "internal server error")
			}
			result.Status = http.StatusInternalServerError
		}
		if recorder.status != 0 {
			result.Status = recorder.status
		}
		server.logRequest(requestID, result, time.Since(started))
	}()

	if server.beforeServe != nil {
		server.beforeServe(request)
	}
	result = server.serve(recorder, request)
}

func (server *Server) serve(writer http.ResponseWriter, request *http.Request) requestResult {
	result := requestResult{PathType: pathType(request.URL.Path)}
	if request.Method != http.MethodGet {
		writer.Header().Set("Allow", http.MethodGet)
		if request.URL.Path == "/v1/subscription" {
			writer.Header().Set("Cache-Control", "no-store")
		}
		writeError(writer, http.StatusMethodNotAllowed, "method_not_allowed", "method is not allowed")
		result.Status = http.StatusMethodNotAllowed
		return result
	}

	switch request.URL.Path {
	case "/healthz":
		writeJSON(writer, http.StatusOK, []byte(`{"status":"ok"}`))
		result.Status = http.StatusOK
		return result
	case "/v1/subscription":
		writer.Header().Set("Cache-Control", "no-store")
		return server.serveSubscription(writer, request, result)
	default:
		writeError(writer, http.StatusNotFound, "not_found", "resource was not found")
		result.Status = http.StatusNotFound
		return result
	}
}

func (server *Server) serveSubscription(writer http.ResponseWriter, request *http.Request, result requestResult) requestResult {
	token := request.URL.Query().Get("token")
	if token == "" {
		writeError(writer, http.StatusBadRequest, "missing_token", "subscription token is required")
		result.Status = http.StatusBadRequest
		return result
	}
	format := request.URL.Query().Get("format")
	if format != "base64" && format != "clash" {
		writeError(writer, http.StatusBadRequest, "invalid_format", "subscription format is invalid")
		result.Status = http.StatusBadRequest
		return result
	}
	result.Format = format
	user := server.matchToken(token)
	if user == nil {
		writeError(writer, http.StatusUnauthorized, "invalid_token", "subscription token is invalid")
		result.Status = http.StatusUnauthorized
		return result
	}
	digest := sha256.Sum256([]byte(user.SubscriptionToken))
	result.UserID = hex.EncodeToString(digest[:8])
	if !user.Enabled {
		writeError(writer, http.StatusForbidden, "user_disabled", "subscription user is disabled")
		result.Status = http.StatusForbidden
		return result
	}

	if format == "base64" {
		body, err := RenderBase64(*user, server.config)
		if err != nil {
			writeError(writer, http.StatusInternalServerError, "internal_error", "internal server error")
			result.Status = http.StatusInternalServerError
			return result
		}
		writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(writer, body)
	} else {
		body, err := RenderClash(*user, server.config)
		if err != nil {
			writeError(writer, http.StatusInternalServerError, "internal_error", "internal server error")
			result.Status = http.StatusInternalServerError
			return result
		}
		writer.Header().Set("Content-Type", "text/yaml; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(writer, body)
	}
	result.Status = http.StatusOK
	return result
}

func (server *Server) matchToken(token string) *contracts.User {
	digest := sha256.Sum256([]byte(token))
	matched := -1
	for index := range server.users {
		if subtle.ConstantTimeCompare(digest[:], server.users[index].digest[:]) == 1 {
			matched = index
		}
	}
	if matched < 0 {
		return nil
	}
	return &server.users[matched].user
}

func (server *Server) logRequest(requestID string, result requestResult, latency time.Duration) {
	event := struct {
		RequestID string `json:"request_id"`
		Path      string `json:"path"`
		Status    int    `json:"status"`
		Format    string `json:"format,omitempty"`
		LatencyMS int64  `json:"latency_ms"`
		UserID    string `json:"user_id,omitempty"`
	}{requestID, result.PathType, result.Status, result.Format, latency.Milliseconds(), result.UserID}
	encoded, _ := json.Marshal(event)
	server.logger.Print(string(encoded))
}

func randomRequestID() string {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return fmt.Sprintf("fallback-%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(value)
}

func pathType(path string) string {
	switch path {
	case "/healthz":
		return "healthz"
	case "/v1/subscription":
		return "subscription"
	default:
		return "other"
	}
}

func writeError(writer http.ResponseWriter, status int, code, message string) {
	body, _ := json.Marshal(struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}{Error: struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	}{code, message}})
	writeJSON(writer, status, body)
}

func writeJSON(writer http.ResponseWriter, status int, body []byte) {
	writer.Header().Set("Content-Type", "application/json")
	writer.WriteHeader(status)
	_, _ = writer.Write(append(body, '\n'))
}

type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (recorder *statusRecorder) WriteHeader(status int) {
	if recorder.wroteHeader {
		return
	}
	recorder.status = status
	recorder.wroteHeader = true
	recorder.ResponseWriter.WriteHeader(status)
}

func (recorder *statusRecorder) Write(data []byte) (int, error) {
	if !recorder.wroteHeader {
		recorder.WriteHeader(http.StatusOK)
	}
	return recorder.ResponseWriter.Write(data)
}
