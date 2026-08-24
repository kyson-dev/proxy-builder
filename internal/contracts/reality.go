package contracts

import (
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
)

type RealityDerived struct {
	PublicKey string `json:"reality_public_key"`
	ShortID   string `json:"reality_short_id"`
}

func DeriveReality(encodedPrivateKey string) (RealityDerived, error) {
	if encodedPrivateKey == "" || strings.Contains(encodedPrivateKey, "=") {
		return RealityDerived{}, errors.New("Reality private key must be unpadded URL-safe Base64")
	}
	raw, err := base64.RawURLEncoding.DecodeString(encodedPrivateKey)
	if err != nil || len(raw) != 32 {
		return RealityDerived{}, errors.New("Reality private key must decode to exactly 32 bytes")
	}
	privateKey, err := ecdh.X25519().NewPrivateKey(raw)
	if err != nil {
		return RealityDerived{}, errors.New("Reality private key is invalid")
	}
	sum := sha256.Sum256(raw)
	return RealityDerived{
		PublicKey: base64.RawURLEncoding.EncodeToString(privateKey.PublicKey().Bytes()),
		ShortID:   hex.EncodeToString(sum[:8]),
	}, nil
}

func ValidateRealityPublicKey(encoded string) error {
	if encoded == "" || strings.Contains(encoded, "=") {
		return errors.New("must be unpadded URL-safe Base64")
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(raw) != 32 {
		return errors.New("must decode to exactly 32 bytes")
	}
	if _, err := ecdh.X25519().NewPublicKey(raw); err != nil {
		return errors.New("must be a valid X25519 public key")
	}
	return nil
}
