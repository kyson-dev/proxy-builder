package contracts

import (
	"bytes"
	"crypto"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"strings"
	"time"
)

type CertificateInspection struct {
	SHA256     string `json:"hy2_cert_sha256"`
	SPKISHA256 string `json:"hy2_spki_sha256"`
}

func InspectCertificate(certificatePEM, privateKeyPEM []byte, sni string, now time.Time) (CertificateInspection, error) {
	certificateBlock, _ := pem.Decode(certificatePEM)
	if certificateBlock == nil || certificateBlock.Type != "CERTIFICATE" {
		return CertificateInspection{}, errors.New("HY2 certificate PEM is invalid")
	}
	certificate, err := x509.ParseCertificate(certificateBlock.Bytes)
	if err != nil {
		return CertificateInspection{}, errors.New("HY2 certificate cannot be parsed")
	}
	privateKey, err := parsePrivateKey(privateKeyPEM)
	if err != nil {
		return CertificateInspection{}, err
	}
	privatePublic, err := x509.MarshalPKIXPublicKey(privateKey.Public())
	if err != nil || !bytes.Equal(privatePublic, certificate.RawSubjectPublicKeyInfo) {
		return CertificateInspection{}, errors.New("HY2 certificate and private key do not match")
	}
	if now.Before(certificate.NotBefore) {
		return CertificateInspection{}, errors.New("HY2 certificate is not valid yet")
	}
	if now.After(certificate.NotAfter) {
		return CertificateInspection{}, errors.New("HY2 certificate has expired")
	}
	if err := certificate.VerifyHostname(sni); err != nil {
		return CertificateInspection{}, errors.New("HY2 certificate SAN does not contain the configured SNI")
	}

	sum := sha256.Sum256(certificate.Raw)
	spkiSum := sha256.Sum256(certificate.RawSubjectPublicKeyInfo)
	encoded := strings.ToUpper(hex.EncodeToString(sum[:]))
	parts := make([]string, 0, len(encoded)/2)
	for index := 0; index < len(encoded); index += 2 {
		parts = append(parts, encoded[index:index+2])
	}
	return CertificateInspection{
		SHA256:     strings.Join(parts, ":"),
		SPKISHA256: base64.StdEncoding.EncodeToString(spkiSum[:]),
	}, nil
}

func parsePrivateKey(data []byte) (crypto.Signer, error) {
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, errors.New("HY2 private key PEM is invalid")
	}
	if value, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		if signer, ok := value.(crypto.Signer); ok {
			return signer, nil
		}
	}
	if value, err := x509.ParseECPrivateKey(block.Bytes); err == nil {
		return value, nil
	}
	if value, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return value, nil
	}
	return nil, errors.New("HY2 private key cannot be parsed")
}
