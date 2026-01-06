package model

// Inbound 对应 s-ui 数据库中的 inbounds 表
// S-UI 使用 sing-box 格式，数据存储在 JSON blob 中
type Inbound struct {
	Id      int    `gorm:"primaryKey;column:id"`
	Type    string `gorm:"column:type"`     // 协议类型: vless, hysteria2, etc.
	Tag     string `gorm:"column:tag"`      // 节点标识
	TlsId   int    `gorm:"column:tls_id"`   // TLS 配置 ID
	Addrs   []byte `gorm:"column:addrs"`    // 地址列表 (JSON blob)
	OutJson []byte `gorm:"column:out_json"` // 出站配置 (JSON blob)
	Options []byte `gorm:"column:options"`  // 监听选项 (JSON blob)
}

// TableName 指定表名
func (Inbound) TableName() string {
	return "inbounds"
}

// OutboundConfig 解析 out_json 字段 (sing-box outbound 格式)
type OutboundConfig struct {
	Type       string                 `json:"type"`
	Tag        string                 `json:"tag"`
	Server     string                 `json:"server"`
	ServerPort int                    `json:"server_port"`
	TLS        *TLSConfig             `json:"tls,omitempty"`
	Transport  map[string]interface{} `json:"transport,omitempty"`
}

// TLSConfig TLS 配置
type TLSConfig struct {
	Enabled    bool           `json:"enabled"`
	ServerName string         `json:"server_name,omitempty"`
	Insecure   bool           `json:"insecure,omitempty"`
	Reality    *RealityConfig `json:"reality,omitempty"`
	UTLS       *UTLSConfig    `json:"utls,omitempty"`
}

// RealityConfig REALITY 配置
type RealityConfig struct {
	Enabled   bool   `json:"enabled"`
	PublicKey string `json:"public_key"`
	ShortId   string `json:"short_id"`
}

// UTLSConfig uTLS 配置
type UTLSConfig struct {
	Enabled     bool   `json:"enabled"`
	Fingerprint string `json:"fingerprint"`
}

// ListenOptions 解析 options 字段
type ListenOptions struct {
	Listen     string                 `json:"listen"`
	ListenPort int                    `json:"listen_port"`
	Multiplex  map[string]interface{} `json:"multiplex,omitempty"`
	Transport  map[string]interface{} `json:"transport,omitempty"`
}
