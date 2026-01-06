package handler

import (
	"encoding/json"
	"html/template"
	"net/http"

	"minibox-sub/internal/repository"
)

type WebHandler struct {
	clientRepo *repository.ClientRepository
}

func NewWebHandler(clientRepo *repository.ClientRepository) *WebHandler {
	return &WebHandler{
		clientRepo: clientRepo,
	}
}

type PageData struct {
	Clients []ClientInfo
}

type ClientInfo struct {
	ID       int
	Name     string
	Inbounds []int
}

func (h *WebHandler) HandleIndex(w http.ResponseWriter, r *http.Request) {
	// 获取所有启用的客户端
	clients, err := h.clientRepo.FindAllEnabled()
	if err != nil {
		http.Error(w, "Failed to load clients", http.StatusInternalServerError)
		return
	}

	// 转换为页面数据
	var clientInfos []ClientInfo
	for _, client := range clients {
		var inboundIDs []int
		json.Unmarshal(client.Inbounds, &inboundIDs)

		clientInfos = append(clientInfos, ClientInfo{
			ID:       client.Id,
			Name:     client.Name,
			Inbounds: inboundIDs,
		})
	}

	data := PageData{
		Clients: clientInfos,
	}

	// 渲染模板
	tmpl := template.Must(template.New("index").Parse(indexHTML))
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	tmpl.Execute(w, data)
}

const indexHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Minibox 订阅中心</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 40px 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        .header {
            text-align: center;
            color: white;
            margin-bottom: 50px;
            animation: fadeInDown 0.8s ease;
        }

        .header h1 {
            font-size: 3rem;
            font-weight: 700;
            margin-bottom: 10px;
            text-shadow: 0 4px 12px rgba(0,0,0,0.2);
        }

        .header p {
            font-size: 1.2rem;
            opacity: 0.9;
        }

        .clients-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 30px;
            animation: fadeInUp 0.8s ease 0.2s both;
        }

        .client-card {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }

        .client-card:hover {
            transform: translateY(-10px);
            box-shadow: 0 30px 80px rgba(0,0,0,0.4);
        }

        .client-header {
            display: flex;
            align-items: center;
            margin-bottom: 25px;
            padding-bottom: 20px;
            border-bottom: 2px solid #f0f0f0;
        }

        .client-avatar {
            width: 60px;
            height: 60px;
            border-radius: 50%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 24px;
            font-weight: bold;
            margin-right: 15px;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }

        .client-info h3 {
            font-size: 1.5rem;
            color: #2d3748;
            margin-bottom: 5px;
        }

        .client-info .nodes {
            color: #718096;
            font-size: 0.9rem;
        }

        .config-section {
            margin-bottom: 25px;
        }

        .config-section h4 {
            font-size: 0.9rem;
            color: #718096;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 12px;
            display: flex;
            align-items: center;
        }

        .config-section h4::before {
            content: '';
            width: 4px;
            height: 16px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin-right: 8px;
            border-radius: 2px;
        }

        .button-group {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
        }

        .btn {
            padding: 12px 20px;
            border: none;
            border-radius: 12px;
            font-size: 0.95rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            text-decoration: none;
            text-align: center;
            display: inline-block;
        }

        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }

        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
        }

        .btn-secondary {
            background: white;
            color: #667eea;
            border: 2px solid #667eea;
        }

        .btn-secondary:hover {
            background: #667eea;
            color: white;
            transform: translateY(-2px);
        }

        .icon {
            margin-right: 6px;
        }

        @keyframes fadeInDown {
            from {
                opacity: 0;
                transform: translateY(-30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        @keyframes fadeInUp {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        @media (max-width: 768px) {
            .header h1 {
                font-size: 2rem;
            }

            .clients-grid {
                grid-template-columns: 1fr;
            }

            .button-group {
                grid-template-columns: 1fr;
            }
        }

        .toast {
            position: fixed;
            bottom: 30px;
            right: 30px;
            background: #48bb78;
            color: white;
            padding: 16px 24px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            display: none;
            animation: slideIn 0.3s ease;
            z-index: 1000;
        }

        .toast.show {
            display: block;
        }

        @keyframes slideIn {
            from {
                transform: translateX(400px);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Minibox 订阅中心</h1>
            <p>选择你的配置，开始畅游互联网</p>
        </div>

        <div class="clients-grid">
            {{range .Clients}}
            <div class="client-card">
                <div class="client-header">
                    <div class="client-avatar">{{slice .Name 0 1}}</div>
                    <div class="client-info">
                        <h3>{{.Name}}</h3>
                        <div class="nodes">📡 {{len .Inbounds}} 个节点</div>
                    </div>
                </div>

                <div class="config-section">
                    <h4>📱 iOS (1.11.4)</h4>
                    <div class="button-group">
                        <button class="btn btn-primary" onclick="copySubscription({{.ID}}, true)">
                            <span class="icon">🔗</span>订阅链接
                        </button>
                        <button class="btn btn-secondary" onclick="downloadConfig({{.ID}}, true, '{{.Name}}')">
                            <span class="icon">📥</span>下载配置
                        </button>
                    </div>
                </div>

                <div class="config-section">
                    <h4>💻 PC/Android (1.12+)</h4>
                    <div class="button-group">
                        <button class="btn btn-primary" onclick="copySubscription({{.ID}}, false)">
                            <span class="icon">🔗</span>订阅链接
                        </button>
                        <button class="btn btn-secondary" onclick="downloadConfig({{.ID}}, false, '{{.Name}}')">
                            <span class="icon">📥</span>下载配置
                        </button>
                    </div>
                </div>
            </div>
            {{end}}
        </div>
    </div>

    <div class="toast" id="toast">✅ 订阅链接已复制到剪贴板！</div>

    <script>
        function downloadConfig(clientId, legacy, clientName) {
            const legacyParam = legacy ? '&legacy=1' : '';
            const suffix = legacy ? '_ios' : '_modern';
            const url = '/api/config?id=' + clientId + legacyParam;
            const filename = clientName + suffix + '.json';
            
            // Create a temporary link and trigger download
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            
            // Show success toast
            showToast('✅ 配置文件下载中...');
        }

        function copySubscription(clientId, legacy) {
            const legacyParam = legacy ? '&legacy=1' : '';
            const url = window.location.origin + '/api/subscription?id=' + clientId + legacyParam;
            
            navigator.clipboard.writeText(url).then(() => {
                showToast('✅ 订阅链接已复制到剪贴板！');
            }).catch(err => {
                alert('复制失败，请手动复制：\n' + url);
            });
        }

        function showToast(message) {
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.classList.add('show');
            setTimeout(() => {
                toast.classList.remove('show');
            }, 3000);
        }
    </script>
</body>
</html>
`
