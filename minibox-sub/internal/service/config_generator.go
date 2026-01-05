package service

import (
	"context"
	"encoding/json"
	"fmt"

	"minibox-sub/internal/model"

	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singboxjson "github.com/sagernet/sing/common/json"
)

// SingboxConfigService 生成 sing-box 客户端配置
type SingboxConfigService struct {
	ServerAddr string
}

func NewSingboxConfigService(serverAddr string) *SingboxConfigService {
	return &SingboxConfigService{
		ServerAddr: serverAddr,
	}
}

// GenerateConfig 为指定客户端生成完整的 sing-box 配置 (现代格式 - PC/Android 1.12+)
func (s *SingboxConfigService) GenerateConfig(client model.Client, inbounds []model.Inbound) (*option.Options, error) {
	return s.generateConfigInternal(client, inbounds, false)
}

// GenerateConfigLegacy 生成兼容旧版本的配置 (iOS 1.11.4)
func (s *SingboxConfigService) GenerateConfigLegacy(client model.Client, inbounds []model.Inbound) (*option.Options, error) {
	return s.generateConfigInternal(client, inbounds, true)
}

// generateConfigInternal 内部配置生成逻辑
func (s *SingboxConfigService) generateConfigInternal(client model.Client, inbounds []model.Inbound, legacy bool) (*option.Options, error) {
	// 1. 创建基础配置骨架
	opts := &option.Options{}

	// 2. 转换 S-UI Inbounds 为 sing-box Outbounds
	proxyTags := []string{}
	for _, inbound := range inbounds {
		outbound, err := s.convertToOutbound(client, inbound)
		if err != nil {
			fmt.Printf("Warning: failed to convert inbound %s: %v\n", inbound.Tag, err)
			continue
		}
		opts.Outbounds = append(opts.Outbounds, *outbound)
		proxyTags = append(proxyTags, outbound.Tag)
	}

	// 3. 添加策略组 (direct, block, proxy)
	s.addPolicyOutbounds(opts, proxyTags)

	// 4. 添加 Log 配置
	s.addLogConfig(opts)

	// 5. 添加 Route 配置 (复用 minibox 的默认路由)
	if err := s.addRouteConfig(opts); err != nil {
		return nil, err
	}

	// 6. 添加 TUN Inbound
	s.addTUNInbound(opts)

	// 7. 根据版本添加对应的 DNS 配置
	if legacy {
		// iOS 1.11.4 - 使用旧格式
		if err := s.addLegacyDNS(opts); err != nil {
			return nil, err
		}
	} else {
		// PC/Android 1.12+ - 使用新格式
		if err := s.addTUNDNS(opts); err != nil {
			return nil, err
		}
	}

	return opts, nil
}

// convertToOutbound 将 S-UI Inbound 转换为 sing-box Outbound
func (s *SingboxConfigService) convertToOutbound(client model.Client, inbound model.Inbound) (*option.Outbound, error) {
	// 解析服务端配置
	var rawOutConfig model.OutboundConfig
	if err := json.Unmarshal(inbound.OutJson, &rawOutConfig); err != nil {
		return nil, err
	}

	var rawListenOpts model.ListenOptions
	if err := json.Unmarshal(inbound.Options, &rawListenOpts); err != nil {
		return nil, err
	}

	// 解析客户端认证信息
	var clientConfig map[string]map[string]interface{}
	if err := json.Unmarshal(client.Config, &clientConfig); err != nil {
		return nil, err
	}

	// 根据协议类型转换
	switch inbound.Type {
	case "hysteria2":
		return s.buildHysteria2(clientConfig, inbound.Tag, rawListenOpts.ListenPort, rawOutConfig)
	case "vless":
		return s.buildVless(clientConfig, inbound.Tag, rawListenOpts.ListenPort, rawOutConfig)
	default:
		return nil, fmt.Errorf("unsupported protocol: %s", inbound.Type)
	}
}

// buildHysteria2 构建 Hysteria2 出站
func (s *SingboxConfigService) buildHysteria2(clientConfig map[string]map[string]interface{}, tag string, port int, raw model.OutboundConfig) (*option.Outbound, error) {
	auth, ok := clientConfig["hysteria2"]
	if !ok {
		return nil, fmt.Errorf("no hysteria2 config")
	}
	password, _ := auth["password"].(string)

	// 使用 map 构建，然后序列化（避免字段不匹配问题）
	outboundMap := map[string]any{
		"type":        "hysteria2",
		"tag":         tag,
		"server":      s.ServerAddr,
		"server_port": port,
		"password":    password,
		"tls": map[string]any{
			"enabled":  true,
			"insecure": true,
		},
	}

	return s.mapToOutbound(outboundMap)
}

// buildVless 构建 VLESS Reality 出站
func (s *SingboxConfigService) buildVless(clientConfig map[string]map[string]interface{}, tag string, port int, raw model.OutboundConfig) (*option.Outbound, error) {
	auth, ok := clientConfig["vless"]
	if !ok {
		return nil, fmt.Errorf("no vless config")
	}
	uuid, _ := auth["uuid"].(string)
	flow, _ := auth["flow"].(string)

	outboundMap := map[string]any{
		"type":        "vless",
		"tag":         tag,
		"server":      s.ServerAddr,
		"server_port": port,
		"uuid":        uuid,
		"flow":        flow,
		"tls": map[string]any{
			"enabled":     true,
			"server_name": raw.TLS.ServerName,
			"utls": map[string]any{
				"enabled":     true,
				"fingerprint": "chrome",
			},
			"reality": map[string]any{
				"enabled":    true,
				"public_key": raw.TLS.Reality.PublicKey,
				"short_id":   raw.TLS.Reality.ShortId,
			},
		},
	}

	return s.mapToOutbound(outboundMap)
}

// mapToOutbound 将 map 转换为 option.Outbound
func (s *SingboxConfigService) mapToOutbound(m map[string]any) (*option.Outbound, error) {
	data, err := singboxjson.Marshal(m)
	if err != nil {
		return nil, err
	}

	var outbound option.Outbound
	// 使用 include.Context 来正确解析 outbound 类型
	ctx := include.Context(context.Background())
	if err := singboxjson.UnmarshalContext(ctx, data, &outbound); err != nil {
		return nil, err
	}

	return &outbound, nil
}

// addPolicyOutbounds 添加策略组 (参考 minibox OutboundModule)
func (s *SingboxConfigService) addPolicyOutbounds(opts *option.Options, proxyTags []string) {
	// Direct
	directMap := map[string]any{"type": "direct", "tag": "direct"}
	direct, _ := s.mapToOutbound(directMap)
	opts.Outbounds = append(opts.Outbounds, *direct)

	// Block
	blockMap := map[string]any{"type": "block", "tag": "block"}
	block, _ := s.mapToOutbound(blockMap)
	opts.Outbounds = append(opts.Outbounds, *block)

	// DNS Outbound (for DNS routing)
	dnsOutMap := map[string]any{"type": "dns", "tag": "dns-out"}
	dnsOut, _ := s.mapToOutbound(dnsOutMap)
	opts.Outbounds = append(opts.Outbounds, *dnsOut)

	// Proxy Selector
	var defaultProxy string
	if len(proxyTags) > 0 {
		defaultProxy = proxyTags[0] // 默认使用第一个节点
	} else {
		defaultProxy = "direct" // 如果没有节点，默认直连
	}

	proxyMap := map[string]any{
		"type":      "selector",
		"tag":       "proxy",
		"outbounds": proxyTags,
		"default":   defaultProxy,
	}
	proxy, _ := s.mapToOutbound(proxyMap)
	opts.Outbounds = append(opts.Outbounds, *proxy)
}

// addLogConfig 添加日志配置 (和 minibox 一致)
func (s *SingboxConfigService) addLogConfig(opts *option.Options) {
	if opts.Log == nil {
		opts.Log = &option.LogOptions{}
	}
	opts.Log.Level = "info"
}

// addTUNInbound 添加 TUN 入站 (适用于 iOS/Android)
func (s *SingboxConfigService) addTUNInbound(opts *option.Options) {
	tunMap := map[string]any{
		"type":                       "tun",
		"tag":                        "tun-in",
		"mtu":                        9000,
		"auto_route":                 true,
		"strict_route":               true,
		"inet4_address":              "172.19.0.1/30",
		"sniff":                      true,
		"sniff_override_destination": true,
	}

	data, _ := singboxjson.Marshal(tunMap)
	var inbound option.Inbound
	// 使用 include.Context 来正确解析 inbound 类型
	ctx := include.Context(context.Background())
	singboxjson.UnmarshalContext(ctx, data, &inbound)
	opts.Inbounds = append(opts.Inbounds, inbound)
}

// addTUNDNS 添加 TUN 模式的 DNS 配置 (和 minibox 一致)
func (s *SingboxConfigService) addTUNDNS(opts *option.Options) error {
	dnsMap := map[string]any{
		"servers": []map[string]any{
			{
				"tag":             "local_dns",
				"type":            "https",
				"server":          "dns.alidns.com",
				"domain_resolver": "resolver_dns",
			},
			{
				"tag":             "proxy_dns",
				"type":            "https",
				"server":          "dns.google",
				"domain_resolver": "resolver_dns",
				"detour":          "proxy",
			},
			{
				"tag":    "resolver_dns",
				"type":   "udp",
				"server": "223.5.5.5",
			},
		},
		"rules": []map[string]any{
			{
				"rule_set": "geosite-cn",
				"action":   "route",
				"server":   "local_dns",
			},
			{
				"rule_set": "geosite-google",
				"action":   "route",
				"server":   "proxy_dns",
			},
		},
		"final":    "proxy_dns",
		"strategy": "ipv4_only",
	}

	data, err := singboxjson.Marshal(dnsMap)
	if err != nil {
		return err
	}

	var dnsOpts option.DNSOptions
	// 使用 include.Context 来正确解析 DNS 类型
	ctx := include.Context(context.Background())
	if err := singboxjson.UnmarshalContext(ctx, data, &dnsOpts); err != nil {
		return err
	}

	opts.DNS = &dnsOpts
	return nil
}

// addLegacyDNS 添加旧版 DNS 配置 (兼容 iOS 1.11.4)
func (s *SingboxConfigService) addLegacyDNS(opts *option.Options) error {
	// 使用旧格式：address + address_resolver
	dnsMap := map[string]any{
		"servers": []map[string]any{
			{
				"tag":              "dns_proxy",
				"address":          "https://dns.google/dns-query",
				"address_resolver": "dns_resolver",
				"detour":           "proxy",
			},
			{
				"tag":              "dns_direct",
				"address":          "https://dns.alidns.com/dns-query",
				"address_resolver": "dns_resolver",
				"detour":           "direct",
			},
			{
				"tag":     "dns_resolver",
				"address": "223.5.5.5",
				"detour":  "direct",
			},
		},
		"rules": []map[string]any{
			{
				"rule_set": "geosite-cn",
				"server":   "dns_direct",
			},
			{
				"rule_set": "geosite-google",
				"server":   "dns_proxy",
			},
			{
				"outbound": "any",
				"server":   "dns_resolver",
			},
		},
		"final":    "dns_proxy",
		"strategy": "ipv4_only",
	}

	data, err := singboxjson.Marshal(dnsMap)
	if err != nil {
		return err
	}

	var dnsOpts option.DNSOptions
	ctx := include.Context(context.Background())
	if err := singboxjson.UnmarshalContext(ctx, data, &dnsOpts); err != nil {
		return err
	}

	opts.DNS = &dnsOpts
	return nil
}

// addRouteConfig 添加路由配置 (复用 minibox 的默认路由)
func (s *SingboxConfigService) addRouteConfig(opts *option.Options) error {
	// 直接复制 minibox route_module.go 的 generateDefaultRoute 逻辑
	routeMap := map[string]any{
		"rule_set": []map[string]any{
			{
				"tag":             "geosite-google",
				"type":            "remote",
				"format":          "binary",
				"url":             "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google.srs",
				"download_detour": "proxy",
			},
			{
				"tag":             "geosite-cn",
				"type":            "remote",
				"format":          "binary",
				"url":             "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
				"download_detour": "proxy",
			},
			{
				"tag":             "geoip-cn",
				"type":            "remote",
				"format":          "binary",
				"url":             "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
				"download_detour": "proxy",
			},
			{
				"tag":             "geosite-apple",
				"type":            "remote",
				"format":          "binary",
				"url":             "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-apple.srs",
				"download_detour": "proxy",
			},
			{
				"tag":             "geosite-ads",
				"type":            "remote",
				"format":          "binary",
				"url":             "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
				"download_detour": "proxy",
			},
		},
		"rules": []map[string]any{
			{"rule_set": []string{"geosite-ads"}, "outbound": "block"},
			{"protocol": []string{"dns"}, "outbound": "dns-out"},
			{"protocol": []string{"ntp"}, "outbound": "direct"},
			{"ip_is_private": true, "outbound": "direct"},
			{"rule_set": []string{"geosite-apple"}, "outbound": "direct"},
			{"rule_set": []string{"geosite-cn", "geoip-cn"}, "outbound": "direct"},
			{"domain": []string{"googleapis.cn", "google.cn"}, "outbound": "proxy"},
			{"rule_set": []string{"geosite-google"}, "outbound": "proxy"},
		},
		"final":                 "proxy",
		"auto_detect_interface": true,
	}

	data, err := singboxjson.Marshal(routeMap)
	if err != nil {
		return err
	}

	var routeOpts option.RouteOptions
	if err := singboxjson.Unmarshal(data, &routeOpts); err != nil {
		return err
	}

	opts.Route = &routeOpts
	return nil
}
