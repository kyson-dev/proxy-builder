package contracts

import (
	"encoding/json"
	"strings"
	"testing"
)

func validRelease() Release {
	sha := strings.Repeat("a", 40)
	return Release{
		SchemaVersion: 1,
		ReleaseID:     sha + "-12345-2",
		Environment:   "development",
		GitSHA:        sha,
		DeploymentID:  "12345-2",
		SingBoxImage:  "ghcr.io/sagernet/sing-box@sha256:" + strings.Repeat("b", 64),
		RealityDest:   "www.example.com:443",
		HY2SNI:        "hy2.example.com",
		CreatedAt:     "2026-08-23T12:00:00Z",
	}
}

func TestParseRelease(t *testing.T) {
	data, _ := json.Marshal(validRelease())
	if _, err := ParseRelease(data); err != nil {
		t.Fatalf("ParseRelease() error = %v", err)
	}
}

func TestReleaseRejectsMutableImageAndIdentityMismatch(t *testing.T) {
	release := validRelease()
	release.SingBoxImage = "ghcr.io/sagernet/sing-box:latest"
	if err := release.Validate(); err == nil {
		t.Fatal("tag image unexpectedly succeeded")
	}
	release = validRelease()
	release.ReleaseID = "wrong"
	if err := release.Validate(); err == nil {
		t.Fatal("mismatched release ID unexpectedly succeeded")
	}
}
