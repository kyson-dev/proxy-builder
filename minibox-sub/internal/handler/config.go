package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"minibox-sub/internal/repository"
	"minibox-sub/internal/service"

	singboxjson "github.com/sagernet/sing/common/json"
)

type ConfigHandler struct {
	clientRepo  *repository.ClientRepository
	inboundRepo *repository.InboundRepository
	configSvc   *service.SingboxConfigService
}

func NewConfigHandler(
	clientRepo *repository.ClientRepository,
	inboundRepo *repository.InboundRepository,
	configSvc *service.SingboxConfigService,
) *ConfigHandler {
	return &ConfigHandler{
		clientRepo:  clientRepo,
		inboundRepo: inboundRepo,
		configSvc:   configSvc,
	}
}

// HandleDownloadConfig 下载配置文件
func (h *ConfigHandler) HandleDownloadConfig(w http.ResponseWriter, r *http.Request) {
	// 获取客户端 ID
	clientIDStr := r.URL.Query().Get("id")
	if clientIDStr == "" {
		http.Error(w, "Missing client ID", http.StatusBadRequest)
		return
	}

	clientID, err := strconv.Atoi(clientIDStr)
	if err != nil {
		http.Error(w, "Invalid client ID", http.StatusBadRequest)
		return
	}

	// 是否使用旧格式
	legacy := r.URL.Query().Get("legacy") == "1"

	// 获取客户端信息
	client, err := h.clientRepo.FindByID(clientID)
	if err != nil {
		http.Error(w, "Client not found", http.StatusNotFound)
		return
	}

	// 获取关联的 inbounds
	var inboundIDs []int
	if err := json.Unmarshal(client.Inbounds, &inboundIDs); err != nil {
		http.Error(w, "Failed to parse inbounds", http.StatusInternalServerError)
		return
	}

	inbounds, err := h.inboundRepo.FindByIDs(inboundIDs)
	if err != nil {
		http.Error(w, "Failed to fetch inbounds", http.StatusInternalServerError)
		return
	}

	// 生成配置
	var opts interface{}
	if legacy {
		opts, err = h.configSvc.GenerateConfigLegacy(*client, inbounds)
	} else {
		opts, err = h.configSvc.GenerateConfig(*client, inbounds)
	}

	if err != nil {
		http.Error(w, "Failed to generate config", http.StatusInternalServerError)
		return
	}

	// 序列化
	data, err := singboxjson.Marshal(opts)
	if err != nil {
		http.Error(w, "Failed to marshal config", http.StatusInternalServerError)
		return
	}

	// 设置响应头
	filename := fmt.Sprintf("%s_config.json", client.Name)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	w.Write(data)
}

// HandleSubscription 订阅链接（返回配置 URL）
func (h *ConfigHandler) HandleSubscription(w http.ResponseWriter, r *http.Request) {
	clientIDStr := r.URL.Query().Get("id")
	if clientIDStr == "" {
		http.Error(w, "Missing client ID", http.StatusBadRequest)
		return
	}

	legacy := r.URL.Query().Get("legacy") == "1"

	// 构建配置下载 URL
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}

	legacyParam := ""
	if legacy {
		legacyParam = "&legacy=1"
	}

	configURL := fmt.Sprintf("%s://%s/api/config?id=%s%s", scheme, r.Host, clientIDStr, legacyParam)

	// 返回订阅链接（sing-box 格式）
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte(configURL))
}
