package subscription

import (
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"regexp"
	"strconv"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

var certificateFingerprint = regexp.MustCompile(`^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$`)

type Config struct {
	ProxyIP          string
	RealityPublicKey string
	RealityShortID   string
	RealityDest      string
	RealitySNI       string
	HY2SNI           string
	HY2CertSHA256    string
	ObfsPassword     string
	Users            contracts.UsersDocument
	Port             int
}

func LoadConfig(getenv func(string) string) (Config, error) {
	proxyIP := getenv("PROXY_IP")
	parsedIP := net.ParseIP(proxyIP)
	if parsedIP == nil || parsedIP.To4() == nil {
		return Config{}, errors.New("PROXY_IP must be an IPv4 address")
	}
	realityPublicKey := getenv("REALITY_PUBLIC_KEY")
	if err := contracts.ValidateRealityPublicKey(realityPublicKey); err != nil {
		return Config{}, fmt.Errorf("REALITY_PUBLIC_KEY %w", err)
	}
	realityShortID := getenv("REALITY_SHORT_ID")
	decodedShortID, err := hex.DecodeString(realityShortID)
	if err != nil || len(decodedShortID) != 8 || realityShortID != fmt.Sprintf("%x", decodedShortID) {
		return Config{}, errors.New("REALITY_SHORT_ID must be 16 lowercase hexadecimal characters")
	}
	realityDest := getenv("REALITY_DEST")
	realitySNI, _, err := contracts.SplitHostPort(realityDest)
	if err != nil {
		return Config{}, fmt.Errorf("REALITY_DEST %w", err)
	}
	if net.ParseIP(realitySNI) != nil {
		return Config{}, errors.New("REALITY_DEST host must be a hostname")
	}
	hy2SNI := getenv("HY2_SNI")
	if err := contracts.ValidateHostname(hy2SNI); err != nil {
		return Config{}, fmt.Errorf("HY2_SNI %w", err)
	}
	hy2CertSHA256 := getenv("HY2_CERT_SHA256")
	if !certificateFingerprint.MatchString(hy2CertSHA256) {
		return Config{}, errors.New("HY2_CERT_SHA256 must be uppercase colon-separated SHA-256")
	}
	obfsPassword := getenv("OBFS_PASSWORD")
	if len([]byte(obfsPassword)) < 24 {
		return Config{}, errors.New("OBFS_PASSWORD must be at least 24 UTF-8 bytes")
	}
	users, err := contracts.ParseUsers([]byte(getenv("PROXY_USERS_JSON")))
	if err != nil {
		return Config{}, fmt.Errorf("PROXY_USERS_JSON: %w", err)
	}
	port := 8080
	if value := getenv("PORT"); value != "" {
		port, err = strconv.Atoi(value)
		if err != nil || port < 1 || port > 65535 {
			return Config{}, errors.New("PORT must be between 1 and 65535")
		}
	}
	return Config{
		ProxyIP:          parsedIP.To4().String(),
		RealityPublicKey: realityPublicKey,
		RealityShortID:   realityShortID,
		RealityDest:      realityDest,
		RealitySNI:       realitySNI,
		HY2SNI:           hy2SNI,
		HY2CertSHA256:    hy2CertSHA256,
		ObfsPassword:     obfsPassword,
		Users:            users,
		Port:             port,
	}, nil
}
