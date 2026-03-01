package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// ==============================================================================
// 数据结构
// ==============================================================================

type User struct {
	Name        string `json:"name"`
	VlessUUID   string `json:"vless_uuid"`
	Hy2Password string `json:"hy2_password"`
}

// ==============================================================================
// 服务配置
// ==============================================================================

type Config struct {
	ServerIP         string
	RealityPublicKey string
	RealityShortID   string // 多个时取第一个
	SNI              string // 从 REALITY_DEST 提取
	UsersFile        string
}

func loadConfig() Config {
	dest := os.Getenv("REALITY_DEST")
	sni := strings.SplitN(dest, ":", 2)[0]

	shortIDs := os.Getenv("REALITY_SHORT_ID")
	shortID := strings.SplitN(shortIDs, ",", 2)[0] // 多个时取第一个

	return Config{
		RealityPublicKey: os.Getenv("REALITY_PUBLIC_KEY"),
		RealityShortID:   shortID,
		SNI:              sni,
		UsersFile:        "/etc/sing-box/users.json",
	}
}

// ==============================================================================
// 获取公网 IP
// ==============================================================================

func getPublicIP() string {
	endpoints := []string{
		"https://ifconfig.me",
		"https://ip.sb",
		"https://ipinfo.io/ip",
	}
	client := &http.Client{Timeout: 5 * time.Second}
	for _, url := range endpoints {
		req, _ := http.NewRequest("GET", url, nil)
		req.Header.Set("User-Agent", "curl/7.68.0")
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err == nil && resp.StatusCode == 200 {
			return strings.TrimSpace(string(body))
		}
	}
	return "127.0.0.1"
}

// ==============================================================================
// 读取用户列表（每次请求重新读取，支持热更新）
// ==============================================================================

func loadUsers(path string) ([]User, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var users []User
	if err := json.Unmarshal(data, &users); err != nil {
		return nil, err
	}
	return users, nil
}

// ==============================================================================
// 生成代理链接
// ==============================================================================

func buildLinks(user User, cfg Config) []string {
	var links []string

	if user.VlessUUID != "" {
		link := fmt.Sprintf(
			"vless://%s@%s:443?encryption=none&flow=xtls-rprx-vision&security=reality"+
				"&sni=%s&fp=chrome&pbk=%s&sid=%s&headerType=none#%s-VLESS",
			user.VlessUUID, cfg.ServerIP,
			cfg.SNI, cfg.RealityPublicKey, cfg.RealityShortID, user.Name,
		)
		links = append(links, link)
	}

	if user.Hy2Password != "" {
		link := fmt.Sprintf(
			"hysteria2://%s@%s:443?insecure=1&sni=%s#%s-HY2",
			user.Hy2Password, cfg.ServerIP, cfg.SNI, user.Name,
		)
		links = append(links, link)
	}

	return links
}

func buildClashConfig(user User, cfg Config) string {
	var sb strings.Builder
	sb.WriteString("proxies:\n")

	if user.VlessUUID != "" {
		sb.WriteString(fmt.Sprintf("  - {name: \"%s-VLESS\", type: vless, server: %s, port: 443, uuid: %s, network: tcp, tls: true, udp: true, flow: xtls-rprx-vision, servername: %s, client-fingerprint: chrome, reality-opts: {public-key: %s, short-id: \"%s\"}}\n",
			user.Name, cfg.ServerIP, user.VlessUUID, cfg.SNI, cfg.RealityPublicKey, cfg.RealityShortID))
	}

	if user.Hy2Password != "" {
		sb.WriteString(fmt.Sprintf("  - {name: \"%s-HY2\", type: hysteria2, server: %s, port: 443, password: %s, sni: %s, skip-cert-verify: true, up: 1000, down: 1000}\n",
			user.Name, cfg.ServerIP, user.Hy2Password, cfg.SNI))
	}

	sb.WriteString("\nproxy-groups:\n")
	sb.WriteString("  - name: \"Auto\"\n")
	sb.WriteString("    type: select\n")
	sb.WriteString("    proxies:\n")
	if user.VlessUUID != "" {
		sb.WriteString(fmt.Sprintf("      - \"%s-VLESS\"\n", user.Name))
	}
	if user.Hy2Password != "" {
		sb.WriteString(fmt.Sprintf("      - \"%s-HY2\"\n", user.Name))
	}
	sb.WriteString("      - DIRECT\n")

	sb.WriteString("\nrules:\n")
	sb.WriteString("  - MATCH,Auto\n")

	return sb.String()
}

// ==============================================================================
// HTTP 处理器
// ==============================================================================

type SubServer struct {
	cfg Config
}

func (s *SubServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 健康检查
	if r.URL.Path == "/health" {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
		return
	}

	if r.URL.Path != "/sub" {
		http.NotFound(w, r)
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "Missing token", http.StatusBadRequest)
		return
	}

	users, err := loadUsers(s.cfg.UsersFile)
	if err != nil {
		log.Printf("Error reading users.json: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	// 按 name 查找用户
	var matched *User
	for i := range users {
		if users[i].Name == token {
			matched = &users[i]
			break
		}
	}

	if matched == nil {
		log.Printf("Invalid token from %s", r.RemoteAddr)
		http.Error(w, "Invalid token", http.StatusForbidden)
		return
	}

	// 检查是否需要 Clash 格式
	ua := r.Header.Get("User-Agent")
	flag := r.URL.Query().Get("flag")
	if strings.Contains(strings.ToLower(ua), "clash") || flag == "clash" {
		log.Printf("Serving Clash YAML for %s", matched.Name)
		content := buildClashConfig(*matched, s.cfg)
		w.Header().Set("Content-Type", "text/yaml; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(content))
		return
	}

	log.Printf("Serving URIs for %s", matched.Name)
	links := buildLinks(*matched, s.cfg)
	content := base64.StdEncoding.EncodeToString([]byte(strings.Join(links, "\n")))

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(content))
}

// ==============================================================================
// 主入口
// ==============================================================================

func main() {
	cfg := loadConfig()

	log.Println("Detecting public IP...")
	cfg.ServerIP = getPublicIP()
	log.Printf("  Server IP:  %s", cfg.ServerIP)
	log.Printf("  SNI:        %s", cfg.SNI)
	log.Printf("  Public Key: %s...", cfg.RealityPublicKey[:min(16, len(cfg.RealityPublicKey))])
	log.Printf("  Users file: %s", cfg.UsersFile)

	server := &SubServer{cfg: cfg}
	addr := ":8080"
	log.Printf("Subscription server started on %s", addr)

	if err := http.ListenAndServe(addr, server); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
