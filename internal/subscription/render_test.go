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
