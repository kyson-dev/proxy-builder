package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func generateTestCert(t *testing.T) (certPath string, cert *x509.Certificate) {
	t.Helper()

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "bing.com"},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(24 * time.Hour),
	}

	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create certificate: %v", err)
	}

	cert, err = x509.ParseCertificate(der)
	if err != nil {
		t.Fatalf("parse certificate: %v", err)
	}

	path := filepath.Join(t.TempDir(), "cert.pem")
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	if err := os.WriteFile(path, pemBytes, 0o600); err != nil {
		t.Fatalf("write cert: %v", err)
	}

	return path, cert
}

func TestLoadCertFingerprints(t *testing.T) {
	path, cert := generateTestCert(t)

	pinSHA256, spkiSHA256 := loadCertFingerprints(path)

	wantPin := sha256.Sum256(cert.Raw)
	wantPinParts := make([]string, len(wantPin))
	for i, b := range wantPin {
		wantPinParts[i] = fmt.Sprintf("%02X", b)
	}
	wantPinStr := strings.Join(wantPinParts, ":")
	if pinSHA256 != wantPinStr {
		t.Fatalf("pinSHA256 mismatch: got %s, want %s", pinSHA256, wantPinStr)
	}

	wantSPKI := sha256.Sum256(cert.RawSubjectPublicKeyInfo)
	wantSPKIStr := base64.StdEncoding.EncodeToString(wantSPKI[:])
	if spkiSHA256 != wantSPKIStr {
		t.Fatalf("spkiSHA256 mismatch: got %s, want %s", spkiSHA256, wantSPKIStr)
	}

	// The two hashes must differ: they cover different parts of the certificate,
	// which is exactly why pinSHA256 can't be reused as the SPKI pin.
	if pinSHA256 == spkiSHA256 {
		t.Fatalf("expected pinSHA256 and spkiSHA256 to differ")
	}
}

func TestLoadCertFingerprints_MissingFile(t *testing.T) {
	pinSHA256, spkiSHA256 := loadCertFingerprints(filepath.Join(t.TempDir(), "missing.pem"))
	if pinSHA256 != "" || spkiSHA256 != "" {
		t.Fatalf("expected empty fingerprints for missing file, got pin=%q spki=%q", pinSHA256, spkiSHA256)
	}
}
