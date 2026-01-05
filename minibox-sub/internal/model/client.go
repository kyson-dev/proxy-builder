package model

// Client 对应 s-ui 数据库中的 clients 表
type Client struct {
	Id       int    `gorm:"primaryKey;column:id"`
	Enable   bool   `gorm:"column:enable"`
	Name     string `gorm:"column:name"`
	Config   []byte `gorm:"column:config"`   // 客户端配置 JSON
	Inbounds []byte `gorm:"column:inbounds"` // 关联的 inbound IDs
	Links    []byte `gorm:"column:links"`    // 代理链接列表 JSON
	Volume   int64  `gorm:"column:volume"`   // 流量限制
	Expiry   int64  `gorm:"column:expiry"`   // 过期时间
	Down     int64  `gorm:"column:down"`     // 下行流量
	Up       int64  `gorm:"column:up"`       // 上行流量
	Desc     string `gorm:"column:desc"`     // 描述
	Group    string `gorm:"column:group"`    // 分组
}

func (Client) TableName() string {
	return "clients"
}

// ProxyLink 代理链接结构
type ProxyLink struct {
	Remark string `json:"remark"`
	Type   string `json:"type"`
	URI    string `json:"uri"`
}
