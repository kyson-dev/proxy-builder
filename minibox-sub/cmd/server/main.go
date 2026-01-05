package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"minibox-sub/internal/config"
	"minibox-sub/internal/repository"
	"minibox-sub/internal/service"

	singboxjson "github.com/sagernet/sing/common/json"
)

func main() {
	// 1. 加载配置
	cfg := config.Load()
	log.Printf("Starting minibox-sub server")
	log.Printf("Database: %s", cfg.DBPath)
	//log.Printf("Port: %s", cfg.Port)

	// 2. 初始化数据库
	db, err := repository.InitDB(cfg.DBPath)
	if err != nil {
		log.Fatalf("Failed to connect database: %v", err)
	}

	// 3. 初始化仓储
	clientRepo := repository.NewClientRepository(db)
	inboundRepo := repository.NewInboundRepository(db)

	// 4. 获取服务器地址
	serverAddr := cfg.PublicDomain
	log.Printf("Server Address: %s", serverAddr)

	// 5. 测试：为第一个客户端生成配置
	allClients, err := clientRepo.FindAllEnabled()
	if err != nil {
		log.Fatalf("Failed to find clients: %v", err)
	}

	if len(allClients) == 0 {
		log.Fatal("No enabled clients found")
	}

	// 使用第一个客户端测试
	testClient := allClients[0]
	log.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	log.Printf("Testing config generation for client: %s (ID: %d)", testClient.Name, testClient.Id)

	// 获取客户端的 inbounds
	var inboundIDs []int
	if err := json.Unmarshal(testClient.Inbounds, &inboundIDs); err != nil {
		log.Fatalf("Failed to parse inbound IDs: %v", err)
	}
	log.Printf("Inbound IDs: %v", inboundIDs)

	inbounds, err := inboundRepo.FindByIDs(inboundIDs)
	if err != nil {
		log.Fatalf("Failed to fetch inbounds: %v", err)
	}
	log.Printf("Found %d inbounds", len(inbounds))

	// 6. 生成现代格式配置 (PC/Android)
	configService := service.NewSingboxConfigService(serverAddr)

	log.Printf("\n🔧 Generating Modern Config (PC/Android 1.12+)...")
	modernOpts, err := configService.GenerateConfig(testClient, inbounds)
	if err != nil {
		log.Fatalf("Failed to generate modern config: %v", err)
	}

	modernData, err := singboxjson.Marshal(modernOpts)
	if err != nil {
		log.Fatalf("Failed to marshal modern config: %v", err)
	}

	modernPath := fmt.Sprintf("%s_modern.json", testClient.Name)
	if err := os.WriteFile(modernPath, modernData, 0644); err != nil {
		log.Fatalf("Failed to write modern config: %v", err)
	}
	log.Printf("✅ Modern config saved to: %s", modernPath)

	// 7. 生成旧格式配置 (iOS 1.11.4)
	log.Printf("\n🔧 Generating Legacy Config (iOS 1.11.4)...")
	legacyOpts, err := configService.GenerateConfigLegacy(testClient, inbounds)
	if err != nil {
		log.Fatalf("Failed to generate legacy config: %v", err)
	}

	legacyData, err := singboxjson.Marshal(legacyOpts)
	if err != nil {
		log.Fatalf("Failed to marshal legacy config: %v", err)
	}

	legacyPath := fmt.Sprintf("%s_legacy.json", testClient.Name)
	if err := os.WriteFile(legacyPath, legacyData, 0644); err != nil {
		log.Fatalf("Failed to write legacy config: %v", err)
	}
	log.Printf("✅ Legacy config saved to: %s", legacyPath)

	log.Printf("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	log.Printf("📊 Summary:")
	log.Printf("  Modern (PC/Android): %s", modernPath)
	log.Printf("  Legacy (iOS 1.11.4): %s", legacyPath)
	log.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
