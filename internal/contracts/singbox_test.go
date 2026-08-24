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

func TestRenderSingBoxFiltersUsersByProtocol(t *testing.T) {
	users, err := ParseUsers([]byte(strings.Replace(validUsersJSON, `"enabled": true`, `"enabled": true, "protocols": {"vless": true, "hysteria2": false}`, 1)))
	if err != nil {
		t.Fatal(err)
	}
	template := []byte(`{"inbounds":[{"type":"vless","users":[],"tls":{"server_name":"","reality":{"private_key":"","short_id":[],"handshake":{"server":"","server_port":443}}}},{"type":"hysteria2","users":[],"obfs":{"type":"salamander","password":""},"tls":{}}]}`)
	output, err := RenderSingBox(template, users, validRelease(), "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo", "obfs-password-123456789012")
	if err != nil {
		t.Fatal(err)
	}
	var document struct {
		Inbounds []struct {
			Type  string `json:"type"`
			Users []any  `json:"users"`
		} `json:"inbounds"`
	}
	if err := json.Unmarshal(output, &document); err != nil {
		t.Fatal(err)
	}
	if len(document.Inbounds) != 2 || len(document.Inbounds[0].Users) != 1 || len(document.Inbounds[1].Users) != 0 {
		t.Fatalf("protocol permissions were not reflected in inbounds: %#v", document.Inbounds)
	}
}
