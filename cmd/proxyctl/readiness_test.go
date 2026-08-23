package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
	"github.com/kyson-dev/proxy-builder/internal/subscription"
)

func TestMigrateUsersProducesV1Document(t *testing.T) {
	directory := t.TempDir()
	input := filepath.Join(directory, "legacy.json")
	output := filepath.Join(directory, "users.json")
	legacy := `[{
  "name":"alice",
  "vless_uuid":"00000000-0000-4000-8000-000000000001",
  "hy2_password":"hy2-password-123456789012",
  "sub_token":"subscription-token-123456"
}]`
	if err := os.WriteFile(input, []byte(legacy), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := migrateUsers([]string{"--input", input, "--output", output}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	document, err := contracts.ParseUsers(data)
	if err != nil {
		t.Fatal(err)
	}
	if !document.Users[0].Enabled || document.Users[0].SubscriptionToken != "subscription-token-123456" {
		t.Fatalf("unexpected migrated document: %#v", document)
	}
	info, err := os.Stat(output)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("output mode = %o, want 600", info.Mode().Perm())
	}
}

func TestMigrateUsersRejectsUnknownAndTrailingFields(t *testing.T) {
	for name, input := range map[string]string{
		"unknown":  `[{"name":"alice","vless_uuid":"00000000-0000-4000-8000-000000000001","hy2_password":"hy2-password-123456789012","sub_token":"subscription-token-123456","enabled":true}]`,
		"trailing": `[] {}`,
	} {
		t.Run(name, func(t *testing.T) {
			directory := t.TempDir()
			path := filepath.Join(directory, "input.json")
			if err := os.WriteFile(path, []byte(input), 0o600); err != nil {
				t.Fatal(err)
			}
			if err := migrateUsers([]string{"--input", path, "--output", filepath.Join(directory, "output.json")}); err == nil {
				t.Fatal("migrateUsers unexpectedly succeeded")
			}
		})
	}
}

func TestValidateSubscriptionAcceptsRenderedFormats(t *testing.T) {
	user := contracts.User{Name: "alice", Enabled: true, VLESSUUID: "00000000-0000-4000-8000-000000000001", HY2Password: "hy2-password-123456789012", SubscriptionToken: "subscription-token-123456"}
	config := subscription.Config{
		ProxyIP: "203.0.113.10", RealityPublicKey: "public-key", RealityShortID: "0123456789abcdef",
		RealitySNI: "example.com", HY2SNI: "example.com", HY2CertSHA256: strings.Repeat("AA:", 31) + "AA", ObfsPassword: "obfs-password-1234567890",
	}
	base64Body, err := subscription.RenderBase64(user, config)
	if err != nil {
		t.Fatal(err)
	}
	clashBody, err := subscription.RenderClash(user, config)
	if err != nil {
		t.Fatal(err)
	}
	for format, body := range map[string]string{"base64": base64Body, "clash": clashBody} {
		t.Run(format, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "response")
			if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
				t.Fatal(err)
			}
			if err := validateSubscription([]string{"--input", path, "--format", format}); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestValidateSubscriptionRejectsNonstandardHY2Parameter(t *testing.T) {
	links := "vless://id@203.0.113.10:443?encryption=none&flow=x&fp=x&headerType=none&pbk=x&security=reality&sid=x&sni=x&type=tcp\n" +
		"hysteria2://password@203.0.113.10:443?insecure=1&obfs=salamander&obfs-password=x&pinSHA256=x&pubKeySHA256=x&sni=x"
	path := filepath.Join(t.TempDir(), "response")
	if err := os.WriteFile(path, []byte(base64.StdEncoding.EncodeToString([]byte(links))), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := validateSubscription([]string{"--input", path, "--format", "base64"}); err == nil {
		t.Fatal("validateSubscription unexpectedly succeeded")
	}
}

func TestEnvironmentInspectionJSONContainsOnlyPublicFields(t *testing.T) {
	directory := t.TempDir()
	cert, key := readinessCertificateFixture(t, "www.example.com")
	files := map[string]string{
		"users.json": `{"version":1,"users":[{"name":"alice","enabled":true,"vless_uuid":"00000000-0000-4000-8000-000000000001","hy2_password":"hy2-password-123456789012","subscription_token":"subscription-token-123456"}]}`,
		"reality":    "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
		"obfs":       "obfs-password-123456789012",
		"cert.pem":   string(cert),
		"key.pem":    string(key),
	}
	for name, value := range files {
		if err := os.WriteFile(filepath.Join(directory, name), []byte(value), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	output := filepath.Join(directory, "public.json")
	err := inspectEnvironment([]string{
		"--users", filepath.Join(directory, "users.json"),
		"--private-key-file", filepath.Join(directory, "reality"),
		"--obfs-password-file", filepath.Join(directory, "obfs"),
		"--cert", filepath.Join(directory, "cert.pem"),
		"--key", filepath.Join(directory, "key.pem"),
		"--sni", "www.example.com", "--output", output,
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(data, &fields); err != nil {
		t.Fatal(err)
	}
	if len(fields) != 3 || fields["reality_public_key"] != "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo" {
		t.Fatalf("unexpected public inspection: %#v", fields)
	}
	value := string(data)
	for _, forbidden := range []string{"private", "password", "users", "token", "subscription-token-123456"} {
		if strings.Contains(value, forbidden) {
			t.Fatalf("public inspection contains %q: %s", forbidden, value)
		}
	}
}

func readinessCertificateFixture(t *testing.T, sni string) ([]byte, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	template := x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: sni}, DNSNames: []string{sni},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature,
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})
}
