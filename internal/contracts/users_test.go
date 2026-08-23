package contracts

import (
	"os"
	"strings"
	"testing"
)

const validUsersJSON = `{
  "version": 1,
  "users": [
    {
      "name": "alice",
      "enabled": true,
      "vless_uuid": "00000000-0000-4000-8000-000000000001",
      "hy2_password": "hy2-password-123456789012",
      "subscription_token": "subscription-token-123456"
    },
    {
      "name": "bob",
      "enabled": false,
      "vless_uuid": "00000000-0000-4000-8000-000000000002",
      "hy2_password": "hy2-password-abcdefghijkl",
      "subscription_token": "subscription-token-abcdef"
    }
  ]
}`

func TestParseUsers(t *testing.T) {
	document, err := ParseUsers([]byte(validUsersJSON))
	if err != nil {
		t.Fatalf("ParseUsers() error = %v", err)
	}
	if len(document.Users) != 2 || !document.Users[0].Enabled || document.Users[1].Enabled {
		t.Fatalf("unexpected users document: %#v", document)
	}
}

func TestRepositoryUsersExampleUsesV1Schema(t *testing.T) {
	data, err := os.ReadFile("../../users.example.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ParseUsers(data); err != nil {
		t.Fatalf("users.example.json is invalid: %v", err)
	}
}

func TestParseUsersRejectsInvalidDocuments(t *testing.T) {
	tests := map[string]string{
		"unknown field":      strings.Replace(validUsersJSON, `"enabled": true`, `"enabled": true, "extra": 1`, 1),
		"missing enabled":    strings.Replace(validUsersJSON, "      \"enabled\": false,\n", "", 1),
		"trailing value":     validUsersJSON + `{}`,
		"duplicate uuid":     strings.Replace(validUsersJSON, "00000000-0000-4000-8000-000000000002", "00000000-0000-4000-8000-000000000001", 1),
		"duplicate password": strings.Replace(validUsersJSON, "hy2-password-abcdefghijkl", "hy2-password-123456789012", 1),
		"duplicate token":    strings.Replace(validUsersJSON, "subscription-token-abcdef", "subscription-token-123456", 1),
		"no enabled user":    strings.Replace(validUsersJSON, `"enabled": true`, `"enabled": false`, 1),
		"uppercase uuid":     strings.Replace(validUsersJSON, "00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-00000000000A", 1),
		"short password":     strings.Replace(validUsersJSON, "hy2-password-123456789012", "too-short", 1),
		"trimmed name":       strings.Replace(validUsersJSON, `"name": "alice"`, `"name": " alice"`, 1),
	}
	for name, input := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseUsers([]byte(input)); err == nil {
				t.Fatal("ParseUsers() unexpectedly succeeded")
			}
		})
	}
}
