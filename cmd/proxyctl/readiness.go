package main

import (
	"bytes"
	"encoding/base64"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
	"gopkg.in/yaml.v3"
)

type environmentInspection struct {
	RealityPublicKey string `json:"reality_public_key"`
	RealityShortID   string `json:"reality_short_id"`
	HY2CertSHA256    string `json:"hy2_cert_sha256"`
}

func inspectEnvironment(args []string) error {
	flags := flag.NewFlagSet("inspect-environment", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	usersPath := flags.String("users", "", "users JSON path")
	privateKeyPath := flags.String("private-key-file", "", "Reality private key path")
	obfsPasswordPath := flags.String("obfs-password-file", "", "obfs password path")
	certificatePath := flags.String("cert", "", "HY2 certificate path")
	certificateKeyPath := flags.String("key", "", "HY2 certificate private key path")
	sni := flags.String("sni", "", "expected HY2 SNI")
	output := flags.String("output", "", "public inspection JSON path")
	if err := flags.Parse(args); err != nil {
		return errors.New("inspect-environment arguments are invalid")
	}
	if *usersPath == "" || *privateKeyPath == "" || *obfsPasswordPath == "" || *certificatePath == "" || *certificateKeyPath == "" || *sni == "" || *output == "" || flags.NArg() != 0 {
		return errors.New("inspect-environment requires --users, --private-key-file, --obfs-password-file, --cert, --key, --sni and --output")
	}

	usersData, err := os.ReadFile(*usersPath)
	if err != nil {
		return errors.New("users input cannot be read")
	}
	if _, err := contracts.ParseUsers(usersData); err != nil {
		return fmt.Errorf("users input: %w", err)
	}
	privateKey, err := readTrimmed(*privateKeyPath, "Reality private key")
	if err != nil {
		return err
	}
	reality, err := contracts.DeriveReality(privateKey)
	if err != nil {
		return err
	}
	obfsPassword, err := readTrimmed(*obfsPasswordPath, "obfs password")
	if err != nil {
		return err
	}
	if len([]byte(obfsPassword)) < 24 {
		return errors.New("obfs password must be at least 24 UTF-8 bytes")
	}
	certificatePEM, err := os.ReadFile(*certificatePath)
	if err != nil {
		return errors.New("HY2 certificate cannot be read")
	}
	certificateKeyPEM, err := os.ReadFile(*certificateKeyPath)
	if err != nil {
		return errors.New("HY2 private key cannot be read")
	}
	certificate, err := contracts.InspectCertificate(certificatePEM, certificateKeyPEM, *sni, time.Now())
	if err != nil {
		return err
	}
	return writeJSON(*output, environmentInspection{
		RealityPublicKey: reality.PublicKey,
		RealityShortID:   reality.ShortID,
		HY2CertSHA256:    certificate.SHA256,
	})
}

func validateSubscription(args []string) error {
	flags := flag.NewFlagSet("validate-subscription", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	input := flags.String("input", "", "response body path")
	format := flags.String("format", "", "base64 or clash")
	if err := flags.Parse(args); err != nil {
		return errors.New("validate-subscription arguments are invalid")
	}
	if *input == "" || (*format != "base64" && *format != "clash") || flags.NArg() != 0 {
		return errors.New("validate-subscription requires --input and --format=base64|clash")
	}
	data, err := os.ReadFile(*input)
	if err != nil {
		return errors.New("subscription response cannot be read")
	}
	if *format == "base64" {
		return validateBase64Subscription(data)
	}
	return validateClashSubscription(data)
}

func validateBase64Subscription(data []byte) error {
	_, err := parseBase64Subscription(data)
	return err
}

func parseBase64Subscription(data []byte) ([]*url.URL, error) {
	decoded, err := base64.StdEncoding.Strict().DecodeString(strings.TrimSpace(string(data)))
	if err != nil {
		return nil, errors.New("base64 subscription is not strict standard Base64")
	}
	lines := strings.Split(string(decoded), "\n")
	if len(lines) != 2 || lines[0] == "" || lines[1] == "" {
		return nil, errors.New("base64 subscription must contain exactly two non-empty links")
	}
	if err := validateSubscriptionURL(lines[0], "vless", map[string]string{
		"encryption": "none", "flow": "xtls-rprx-vision", "fp": "chrome", "headerType": "none",
		"pbk": "", "security": "reality", "sid": "", "sni": "", "type": "tcp",
	}); err != nil {
		return nil, err
	}
	if err := validateSubscriptionURL(lines[1], "hysteria2", map[string]string{
		"insecure": "1", "obfs": "salamander", "obfs-password": "", "pinSHA256": "", "sni": "",
	}); err != nil {
		return nil, err
	}
	if strings.Contains(string(decoded), "pubKeySHA256") {
		return nil, errors.New("base64 subscription contains the unsupported pubKeySHA256 parameter")
	}
	vless, _ := url.Parse(lines[0])
	hy2, _ := url.Parse(lines[1])
	return []*url.URL{vless, hy2}, nil
}

func renderProbeConfig(args []string) error {
	flags := flag.NewFlagSet("render-probe-config", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	input := flags.String("input", "", "Base64 subscription path")
	protocol := flags.String("protocol", "", "vless or hysteria2")
	listenPort := flags.Int("listen-port", 0, "local SOCKS port")
	output := flags.String("output", "", "client config path")
	if err := flags.Parse(args); err != nil {
		return errors.New("render-probe-config arguments are invalid")
	}
	if *input == "" || (*protocol != "vless" && *protocol != "hysteria2") || *listenPort < 1024 || *listenPort > 65535 || *output == "" || flags.NArg() != 0 {
		return errors.New("render-probe-config requires --input, --protocol=vless|hysteria2, --listen-port and --output")
	}
	data, err := os.ReadFile(*input)
	if err != nil {
		return errors.New("subscription response cannot be read")
	}
	links, err := parseBase64Subscription(data)
	if err != nil {
		return err
	}
	link := links[0]
	if *protocol == "hysteria2" {
		link = links[1]
	}
	query := link.Query()
	outbound := map[string]any{
		"type": link.Scheme, "tag": "probe-out", "server": link.Hostname(), "server_port": 443,
	}
	if *protocol == "vless" {
		outbound["uuid"] = link.User.Username()
		outbound["flow"] = query.Get("flow")
		outbound["tls"] = map[string]any{
			"enabled": true, "server_name": query.Get("sni"),
			"utls":    map[string]any{"enabled": true, "fingerprint": query.Get("fp")},
			"reality": map[string]any{"enabled": true, "public_key": query.Get("pbk"), "short_id": query.Get("sid")},
		}
	} else {
		outbound["password"] = link.User.Username()
		outbound["obfs"] = map[string]any{"type": query.Get("obfs"), "password": query.Get("obfs-password")}
		outbound["tls"] = map[string]any{"enabled": true, "server_name": query.Get("sni"), "insecure": true}
	}
	config := map[string]any{
		"log":       map[string]any{"level": "warn"},
		"inbounds":  []any{map[string]any{"type": "socks", "tag": "probe-in", "listen": "127.0.0.1", "listen_port": *listenPort}},
		"outbounds": []any{outbound},
		"route":     map[string]any{"final": "probe-out"},
	}
	return writeJSON(*output, config)
}

func validateSubscriptionURL(raw, scheme string, expected map[string]string) error {
	value, err := url.Parse(raw)
	if err != nil || value.Scheme != scheme || value.User == nil || value.Hostname() == "" || value.Port() != "443" {
		return fmt.Errorf("subscription contains an invalid %s link", scheme)
	}
	query := value.Query()
	if len(query) != len(expected) {
		return fmt.Errorf("%s subscription link has unexpected query parameters", scheme)
	}
	for key, wanted := range expected {
		if query.Get(key) == "" {
			return fmt.Errorf("%s subscription link is missing %s", scheme, key)
		}
		if wanted != "" && query.Get(key) != wanted {
			return fmt.Errorf("%s subscription link has invalid %s", scheme, key)
		}
	}
	return nil
}

func validateClashSubscription(data []byte) error {
	type proxy struct {
		Name           string         `yaml:"name"`
		Type           string         `yaml:"type"`
		Server         string         `yaml:"server"`
		Port           int            `yaml:"port"`
		UUID           string         `yaml:"uuid"`
		Network        string         `yaml:"network"`
		TLS            bool           `yaml:"tls"`
		UDP            bool           `yaml:"udp"`
		Flow           string         `yaml:"flow"`
		ServerName     string         `yaml:"servername"`
		ClientFP       string         `yaml:"client-fingerprint"`
		Password       string         `yaml:"password"`
		SNI            string         `yaml:"sni"`
		SkipCertVerify bool           `yaml:"skip-cert-verify"`
		RealityOptions map[string]any `yaml:"reality-opts"`
		Fingerprint    string         `yaml:"fingerprint"`
		Obfs           string         `yaml:"obfs"`
		ObfsPassword   string         `yaml:"obfs-password"`
	}
	type group struct {
		Name    string   `yaml:"name"`
		Type    string   `yaml:"type"`
		Proxies []string `yaml:"proxies"`
	}
	type document struct {
		Proxies     []proxy  `yaml:"proxies"`
		ProxyGroups []group  `yaml:"proxy-groups"`
		Rules       []string `yaml:"rules"`
	}
	var value document
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	decoder.KnownFields(true)
	if err := decoder.Decode(&value); err != nil {
		return errors.New("Clash subscription is not valid strict YAML")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("Clash subscription contains a trailing YAML document")
	}
	if len(value.Proxies) != 2 || value.Proxies[0].Type != "vless" || value.Proxies[1].Type != "hysteria2" {
		return errors.New("Clash subscription must contain one VLESS and one Hysteria2 proxy")
	}
	for _, item := range value.Proxies {
		if item.Name == "" || item.Server == "" || item.Port != 443 {
			return errors.New("Clash subscription proxy structure is incomplete")
		}
	}
	if value.Proxies[0].UUID == "" || value.Proxies[0].Network != "tcp" || !value.Proxies[0].TLS || !value.Proxies[0].UDP ||
		value.Proxies[0].Flow != "xtls-rprx-vision" || value.Proxies[0].ServerName == "" || value.Proxies[0].ClientFP != "chrome" ||
		len(value.Proxies[0].RealityOptions) != 2 || value.Proxies[0].RealityOptions["public-key"] == nil || value.Proxies[0].RealityOptions["short-id"] == nil {
		return errors.New("Clash VLESS proxy structure is incomplete")
	}
	if value.Proxies[1].Password == "" || value.Proxies[1].SNI == "" || value.Proxies[1].SkipCertVerify ||
		value.Proxies[1].Fingerprint == "" || value.Proxies[1].Obfs != "salamander" || value.Proxies[1].ObfsPassword == "" {
		return errors.New("Clash Hysteria2 proxy structure is incomplete")
	}
	if len(value.ProxyGroups) != 1 || value.ProxyGroups[0].Name != "Auto" || value.ProxyGroups[0].Type != "select" ||
		len(value.ProxyGroups[0].Proxies) != 3 || value.ProxyGroups[0].Proxies[0] != value.Proxies[0].Name ||
		value.ProxyGroups[0].Proxies[1] != value.Proxies[1].Name || value.ProxyGroups[0].Proxies[2] != "DIRECT" {
		return errors.New("Clash subscription proxy group is invalid")
	}
	if len(value.Rules) != 1 || value.Rules[0] != "MATCH,Auto" {
		return errors.New("Clash subscription rules are invalid")
	}
	return nil
}
