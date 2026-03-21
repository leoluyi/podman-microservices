# Frontend Dockerfile
# Base: SUSE BCI Nginx

FROM registry.suse.com/suse/nginx:1.21

LABEL maintainer="your-team@example.com"
LABEL description="Frontend Static Website"
LABEL version="1.0.0"

# 建立簡單的 HTML 頁面（示範用）
RUN mkdir -p /usr/share/nginx/html

RUN cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>微服務架構範例</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container { 
            background: white; 
            padding: 40px; 
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            max-width: 800px;
            width: 100%;
        }
        h1 { color: #333; margin-bottom: 20px; }
        .status { 
            background: #f0f0f0; 
            padding: 20px; 
            border-radius: 5px;
            margin: 20px 0;
        }
        .badge { 
            display: inline-block;
            padding: 5px 10px;
            background: #4CAF50;
            color: white;
            border-radius: 3px;
            font-size: 12px;
            margin-left: 10px;
        }
        button {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
        }
        button:hover { background: #5568d3; }
        .result { 
            background: #f9f9f9;
            padding: 15px;
            border-left: 4px solid #667eea;
            margin-top: 20px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Podman 微服務架構範例</h1>
        
        <div class="status">
            <p><strong>架構：</strong>方案 A - 統一 SSL Termination</p>
            <p><strong>前端：</strong>Nginx <span class="badge">Running</span></p>
            <p><strong>網關：</strong>SSL Proxy + BFF <span class="badge">Active</span></p>
            <p><strong>後端：</strong>3 個微服務（隔離網路）</p>
        </div>

        <h2>測試 API 端點</h2>
        <p>點擊按鈕測試 API（需要 JWT Token）</p>

        <div>
            <button onclick="testAPI('/api/health', false)">測試 BFF 狀態</button>
            <button onclick="testAPI('/api/users')">測試 Users API</button>
            <button onclick="testAPI('/api/orders')">測試 Orders API</button>
            <button onclick="testAPI('/api/products')">測試 Products API</button>
        </div>

        <div id="result" class="result" style="display:none;"></div>

        <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee;">
            <p style="font-size: 14px; color: #666;">
                📖 查看完整文件：<code>/docs</code> 目錄<br>
                🔧 管理指令：<code>./scripts/</code> 目錄
            </p>
        </div>
    </div>

    <script>
        async function testAPI(endpoint, requireJWT = true) {
            const resultDiv = document.getElementById('result');
            resultDiv.style.display = 'block';
            resultDiv.textContent = '正在請求 ' + endpoint + '...\n';

            try {
                const headers = {};
                if (requireJWT) {
                    headers['Authorization'] = 'Bearer YOUR_JWT_TOKEN_HERE';
                }
                const response = await fetch(endpoint, { headers });
                const data = await response.json();
                resultDiv.textContent = JSON.stringify(data, null, 2);
            } catch (error) {
                resultDiv.textContent = '錯誤: ' + error.message + (requireJWT ? '\n\n提示：需要有效的 JWT Token' : '');
            }
        }
    </script>
</body>
</html>
EOF

# 建立健康檢查頁面
RUN cat > /usr/share/nginx/html/health.html << 'EOF'
OK
EOF

# 複製 Nginx 配置（將使用 Volume 掛載）
# 這裡不需要複製，因為會透過 Quadlet Volume 掛載

EXPOSE 80

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# 使用 Nginx 原生啟動方式
CMD ["nginx", "-g", "daemon off;"]
