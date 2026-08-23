package contracts

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestRenderSingBox(t *testing.T) {
	users, err := ParseUsers([]byte(validUsersJSON))
	if err != nil {
		t.Fatal(err)
	}
	template := []byte(`{"inbounds":[{"type":"vless","users":[],"tls":{"server_name":"","reality":{"private_key":"","short_id":[],"handshake":{"server":"","server_port":443}}}},{"type":"hysteria2","users":[],"obfs":{"type":"salamander","password":""},"tls":{}}]}`)
	output, err := RenderSingBox(template, users, validRelease(), "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo", "obfs-password-123456789012")
	if err != nil {
		t.Fatalf("RenderSingBox() error = %v", err)
	}
	var document map[string]any
	if err := json.Unmarshal(output, &document); err != nil {
		t.Fatalf("generated JSON is invalid: %v", err)
	}
	text := string(output)
	if strings.Contains(text, "bob") || !strings.Contains(text, "alice") || !strings.Contains(text, "c9ccbbf12f7c2cf4") {
		t.Fatalf("generated config has wrong users or short ID")
	}
}

func TestRenderSingBoxRejectsTrailingJSON(t *testing.T) {
	users, err := ParseUsers([]byte(validUsersJSON))
	if err != nil {
		t.Fatal(err)
	}
	template := []byte(`{"inbounds":[]} {}`)
	if _, err := RenderSingBox(template, users, validRelease(), "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo", "obfs-password-123456789012"); err == nil {
		t.Fatal("RenderSingBox() unexpectedly accepted trailing JSON")
	}
}
