package config

import "os"

type Config struct {
	DBPath string
	//Port   string
	PublicDomain string
}

func Load() Config {
	// 默认值逻辑
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		// 默认指向本地开发环境的路径
		dbPath = "../s-ui/db/s-ui.db"
	}

	publicDomain := os.Getenv("PUBLIC_DOMAIN")
	if publicDomain == "" {
		publicDomain = "127.0.0.1"
	}

	return Config{
		DBPath:       dbPath,
		PublicDomain: publicDomain,
	}
}
