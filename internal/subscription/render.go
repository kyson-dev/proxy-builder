package subscription

import (
	"encoding/base64"
	"fmt"
	"net"
	"net/url"
	"strings"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
	"gopkg.in/yaml.v3"
)

func RenderBase64(user contracts.User, config Config) (string, error) {
	links := []string{renderVLESSURI(user, config), renderHY2URI(user, config)}
	return base64.StdEncoding.EncodeToString([]byte(strings.Join(links, "\n"))), nil
}

func renderVLESSURI(user contracts.User, config Config) string {
	value := url.URL{
		Scheme:   "vless",
		User:     url.User(user.VLESSUUID),
		Host:     net.JoinHostPort(config.ProxyIP, "443"),
		Fragment: user.Name + "-VLESS",
	}
	query := url.Values{}
	query.Set("encryption", "none")
	query.Set("flow", "xtls-rprx-vision")
	query.Set("fp", "chrome")
	query.Set("headerType", "none")
	query.Set("pbk", config.RealityPublicKey)
	query.Set("security", "reality")
	query.Set("sid", config.RealityShortID)
	query.Set("sni", config.RealitySNI)
	query.Set("type", "tcp")
	value.RawQuery = query.Encode()
	return value.String()
}

func renderHY2URI(user contracts.User, config Config) string {
	value := url.URL{
		Scheme:   "hysteria2",
		User:     url.User(user.HY2Password),
		Host:     net.JoinHostPort(config.ProxyIP, "443"),
		Path:     "/",
		Fragment: user.Name + "-HY2",
	}
	query := url.Values{}
	query.Set("insecure", "1")
	query.Set("obfs", "salamander")
	query.Set("obfs-password", config.ObfsPassword)
	query.Set("pinSHA256", config.HY2CertSHA256)
	query.Set("sni", config.HY2SNI)
	value.RawQuery = query.Encode()
	return value.String()
}

type clashConfig struct {
	Proxies     []any        `yaml:"proxies"`
	ProxyGroups []clashGroup `yaml:"proxy-groups"`
	Rules       []string     `yaml:"rules"`
}

type clashVLESS struct {
	Name              string       `yaml:"name"`
	Type              string       `yaml:"type"`
	Server            string       `yaml:"server"`
	Port              int          `yaml:"port"`
	UUID              string       `yaml:"uuid"`
	Network           string       `yaml:"network"`
	TLS               bool         `yaml:"tls"`
	UDP               bool         `yaml:"udp"`
	Flow              string       `yaml:"flow"`
	ServerName        string       `yaml:"servername"`
	ClientFingerprint string       `yaml:"client-fingerprint"`
	RealityOptions    realityClash `yaml:"reality-opts"`
}

type realityClash struct {
	PublicKey string `yaml:"public-key"`
	ShortID   string `yaml:"short-id"`
}

type clashHY2 struct {
	Name           string `yaml:"name"`
	Type           string `yaml:"type"`
	Server         string `yaml:"server"`
	Port           int    `yaml:"port"`
	Password       string `yaml:"password"`
	SNI            string `yaml:"sni"`
	SkipCertVerify bool   `yaml:"skip-cert-verify"`
	Fingerprint    string `yaml:"fingerprint"`
	Obfs           string `yaml:"obfs"`
	ObfsPassword   string `yaml:"obfs-password"`
}

type clashGroup struct {
	Name    string   `yaml:"name"`
	Type    string   `yaml:"type"`
	Proxies []string `yaml:"proxies"`
}

func RenderClash(user contracts.User, config Config) (string, error) {
	vlessName := user.Name + "-VLESS"
	hy2Name := user.Name + "-HY2"
	document := clashConfig{
		Proxies: []any{
			clashVLESS{
				Name:              vlessName,
				Type:              "vless",
				Server:            config.ProxyIP,
				Port:              443,
				UUID:              user.VLESSUUID,
				Network:           "tcp",
				TLS:               true,
				UDP:               true,
				Flow:              "xtls-rprx-vision",
				ServerName:        config.RealitySNI,
				ClientFingerprint: "chrome",
				RealityOptions: realityClash{
					PublicKey: config.RealityPublicKey,
					ShortID:   config.RealityShortID,
				},
			},
			clashHY2{
				Name:           hy2Name,
				Type:           "hysteria2",
				Server:         config.ProxyIP,
				Port:           443,
				Password:       user.HY2Password,
				SNI:            config.HY2SNI,
				SkipCertVerify: false,
				Fingerprint:    config.HY2CertSHA256,
				Obfs:           "salamander",
				ObfsPassword:   config.ObfsPassword,
			},
		},
		ProxyGroups: []clashGroup{{
			Name:    "Auto",
			Type:    "select",
			Proxies: []string{vlessName, hy2Name, "DIRECT"},
		}},
		Rules: []string{"MATCH,Auto"},
	}
	output, err := yaml.Marshal(document)
	if err != nil {
		return "", fmt.Errorf("Clash output cannot be encoded")
	}
	return string(output), nil
}
