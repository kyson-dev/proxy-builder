package subscription

import (
	"strings"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

const (
	testToken    = "subscription-token-canary-123456"
	testPassword = "hy2-password-canary-123456789"
	testObfs     = "obfs-password-canary-12345678"
)

func validConfig() Config {
	return Config{
		ProxyIP:          "203.0.113.10",
		RealityPublicKey: "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
		RealityShortID:   "c9ccbbf12f7c2cf4",
		RealityDest:      "www.example.com:443",
		RealitySNI:       "www.example.com",
		HY2SNI:           "hy2.example.com",
		HY2CertSHA256:    strings.TrimSuffix(strings.Repeat("AA:", 32), ":"),
		HY2SPKISHA256:    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		ObfsPassword:     testObfs,
		Users: contracts.UsersDocument{Version: 1, Users: []contracts.User{
			{
				Name:              "alice",
				Enabled:           true,
				Protocols:         contracts.Protocols{VLESS: true, Hysteria2: true},
				VLESSUUID:         "00000000-0000-4000-8000-000000000001",
				HY2Password:       testPassword,
				SubscriptionToken: testToken,
			},
			{
				Name:              "disabled",
				Enabled:           false,
				Protocols:         contracts.Protocols{VLESS: true, Hysteria2: true},
				VLESSUUID:         "00000000-0000-4000-8000-000000000002",
				HY2Password:       "hy2-password-disabled-12345",
				SubscriptionToken: "subscription-token-disabled-1",
			},
		}},
		Port: 8080,
	}
}
