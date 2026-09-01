package subscription

import (
	"encoding/json"
	"testing"
)

func TestLoadConfig(t *testing.T) {
	config := validConfig()
	users, _ := json.Marshal(config.Users)
	values := map[string]string{
		"PROXY_IP":           config.ProxyIP,
		"REALITY_PUBLIC_KEY": config.RealityPublicKey,
		"REALITY_SHORT_ID":   config.RealityShortID,
		"REALITY_DEST":       config.RealityDest,
		"HY2_SNI":            config.HY2SNI,
		"HY2_CERT_SHA256":    config.HY2CertSHA256,
		"HY2_SPKI_SHA256":    config.HY2SPKISHA256,
		"OBFS_PASSWORD":      config.ObfsPassword,
		"PROXY_USERS_JSON":   string(users),
	}
	loaded, err := LoadConfig(func(key string) string { return values[key] })
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if loaded.Port != 8080 || loaded.RealitySNI != "www.example.com" {
		t.Fatalf("unexpected config: %#v", loaded)
	}
}

func TestLoadConfigRejectsInvalidSPKIPin(t *testing.T) {
	config := validConfig()
	users, _ := json.Marshal(config.Users)
	values := map[string]string{
		"PROXY_IP":           config.ProxyIP,
		"REALITY_PUBLIC_KEY": config.RealityPublicKey,
		"REALITY_SHORT_ID":   config.RealityShortID,
		"REALITY_DEST":       config.RealityDest,
		"HY2_SNI":            config.HY2SNI,
		"HY2_CERT_SHA256":    config.HY2CertSHA256,
		"HY2_SPKI_SHA256":    "not-a-sha256-pin",
		"OBFS_PASSWORD":      config.ObfsPassword,
		"PROXY_USERS_JSON":   string(users),
	}
	if _, err := LoadConfig(func(key string) string { return values[key] }); err == nil {
		t.Fatal("LoadConfig() unexpectedly accepted invalid HY2_SPKI_SHA256")
	}
}

func TestLoadConfigRejectsInvalidFieldWithoutValue(t *testing.T) {
	secret := "secret-value-that-must-not-leak"
	values := map[string]string{"PROXY_IP": secret}
	_, err := LoadConfig(func(key string) string { return values[key] })
	if err == nil {
		t.Fatal("LoadConfig() unexpectedly succeeded")
	}
	if got := err.Error(); got == "" || got == secret {
		t.Fatalf("unsafe error: %q", got)
	}
}
