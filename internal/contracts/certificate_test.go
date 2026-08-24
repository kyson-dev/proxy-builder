package contracts

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"testing"
	"time"
)

func certificateFixture(t *testing.T, sni string, notBefore, notAfter time.Time) ([]byte, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "ignored.example"},
		DNSNames:     []string{sni},
		NotBefore:    notBefore,
		NotAfter:     notAfter,
		KeyUsage:     x509.KeyUsageDigitalSignature,
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

func TestInspectCertificate(t *testing.T) {
	now := time.Date(2026, 8, 23, 12, 0, 0, 0, time.UTC)
	cert, key := certificateFixture(t, "www.example.com", now.Add(-time.Hour), now.Add(time.Hour))
	inspection, err := InspectCertificate(cert, key, "www.example.com", now)
	if err != nil {
		t.Fatalf("InspectCertificate() error = %v", err)
	}
	if len(inspection.SHA256) != 95 {
		t.Fatalf("fingerprint length = %d", len(inspection.SHA256))
	}
}

func TestInspectCertificateRejectsMismatchAndSAN(t *testing.T) {
	now := time.Now().UTC()
	cert, _ := certificateFixture(t, "www.example.com", now.Add(-time.Hour), now.Add(time.Hour))
	_, otherKey := certificateFixture(t, "www.example.com", now.Add(-time.Hour), now.Add(time.Hour))
	if _, err := InspectCertificate(cert, otherKey, "www.example.com", now); err == nil {
		t.Fatal("mismatched key unexpectedly succeeded")
	}
	_, key := certificateFixture(t, "www.example.com", now.Add(-time.Hour), now.Add(time.Hour))
	cert, key = certificateFixture(t, "www.example.com", now.Add(-time.Hour), now.Add(time.Hour))
	if _, err := InspectCertificate(cert, key, "other.example.com", now); err == nil {
		t.Fatal("SAN mismatch unexpectedly succeeded")
	}
}

func TestInspectCertificateRejectsInvalidValidityWindow(t *testing.T) {
	now := time.Date(2026, 8, 23, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name      string
		notBefore time.Time
		notAfter  time.Time
	}{
		{"not yet valid", now.Add(time.Minute), now.Add(time.Hour)},
		{"expired", now.Add(-time.Hour), now.Add(-time.Minute)},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cert, key := certificateFixture(t, "www.example.com", test.notBefore, test.notAfter)
			if _, err := InspectCertificate(cert, key, "www.example.com", now); err == nil {
				t.Fatal("InspectCertificate() unexpectedly accepted invalid certificate validity")
			}
		})
	}
}
