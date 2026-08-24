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

func TestRenderProbeConfigUsesSubscriptionCredentials(t *testing.T) {
	user := contracts.User{Name: "alice", Enabled: true, VLESSUUID: "00000000-0000-4000-8000-000000000001", HY2Password: "hy2-password-123456789012", SubscriptionToken: "subscription-token-123456"}
	config := subscription.Config{
		ProxyIP: "203.0.113.10", RealityPublicKey: "public-key", RealityShortID: "0123456789abcdef",
		RealitySNI: "www.example.com", HY2SNI: "hy2.example.com", HY2CertSHA256: strings.Repeat("AA:", 31) + "AA", ObfsPassword: "obfs-password-1234567890",
	}
	body, err := subscription.RenderBase64(user, config)
	if err != nil {
		t.Fatal(err)
	}
	input := filepath.Join(t.TempDir(), "subscription")
	if err := os.WriteFile(input, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	for protocol, expectedSecret := range map[string]string{"vless": user.VLESSUUID, "hysteria2": user.HY2Password} {
		t.Run(protocol, func(t *testing.T) {
			output := filepath.Join(t.TempDir(), protocol+".json")
			if err := renderProbeConfig([]string{"--input", input, "--protocol", protocol, "--listen-port", "18080", "--output", output}); err != nil {
				t.Fatal(err)
			}
			data, err := os.ReadFile(output)
			if err != nil {
				t.Fatal(err)
			}
			var rendered struct {
				Inbounds  []map[string]any `json:"inbounds"`
				Outbounds []map[string]any `json:"outbounds"`
			}
			if err := json.Unmarshal(data, &rendered); err != nil {
				t.Fatal(err)
			}
			if len(rendered.Inbounds) != 1 || rendered.Inbounds[0]["listen_port"] != float64(18080) || len(rendered.Outbounds) != 1 || rendered.Outbounds[0]["type"] != protocol {
				t.Fatalf("unexpected %s probe config: %#v", protocol, rendered)
			}
			secretKey := "password"
			if protocol == "vless" {
				secretKey = "uuid"
			}
			if rendered.Outbounds[0][secretKey] != expectedSecret {
				t.Fatalf("%s probe config does not use the subscription credential", protocol)
			}
		})
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
