package subscription

import (
	"encoding/base64"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestRenderBase64UsesStandardHY2Parameters(t *testing.T) {
	config := validConfig()
	encoded, err := RenderBase64(config.Users.Users[0], config)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	value := string(decoded)
	for _, expected := range []string{"vless://", "hysteria2://", "insecure=1", "pinSHA256=", "obfs=salamander"} {
		if !strings.Contains(value, expected) {
			t.Fatalf("output does not contain %q", expected)
		}
	}
	if strings.Contains(value, "pubKeySHA256") {
		t.Fatal("output contains non-standard pubKeySHA256")
	}
}

func TestRenderClashProducesParseableYAML(t *testing.T) {
	config := validConfig()
	output, err := RenderClash(config.Users.Users[0], config)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := yaml.Unmarshal([]byte(output), &document); err != nil {
		t.Fatalf("YAML cannot be parsed: %v", err)
	}
	if len(document["proxies"].([]any)) != 2 {
		t.Fatalf("unexpected proxies: %#v", document["proxies"])
	}
}

func TestRenderSubscriptionsFilterUnauthorizedProtocol(t *testing.T) {
	config := validConfig()
	for name, protocols := range map[string]struct {
		vless     bool
		hysteria2 bool
	}{
		"VLESS only":     {vless: true, hysteria2: false},
		"Hysteria2 only": {vless: false, hysteria2: true},
	} {
		t.Run(name, func(t *testing.T) {
			user := config.Users.Users[0]
			user.Protocols.VLESS = protocols.vless
			user.Protocols.Hysteria2 = protocols.hysteria2
			base64Output, err := RenderBase64(user, config)
			if err != nil {
				t.Fatal(err)
			}
			decoded, err := base64.StdEncoding.DecodeString(base64Output)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(decoded), "vless://") != protocols.vless || strings.Contains(string(decoded), "hysteria2://") != protocols.hysteria2 {
				t.Fatalf("Base64 subscription did not match protocol permissions: %s", decoded)
			}
			clashOutput, err := RenderClash(user, config)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(clashOutput, "type: vless") != protocols.vless || strings.Contains(clashOutput, "type: hysteria2") != protocols.hysteria2 {
				t.Fatalf("Clash subscription did not match protocol permissions: %s", clashOutput)
			}
		})
	}
}
