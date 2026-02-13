# BFF Service Dockerfile
# Base: SUSE BCI Node.js 20

FROM registry.suse.com/bci/nodejs:20

LABEL maintainer="your-team@example.com"
LABEL description="BFF (Backend For Frontend) Gateway Service"
LABEL version="1.0.0"

WORKDIR /app

# 建立範例 BFF 應用程式
RUN cat > package.json << 'EOF'
{
  "name": "bff-service",
  "version": "1.0.0",
  "description": "Backend For Frontend Gateway",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

RUN cat > server.js << 'EOF'
const express = require('express');
const app = express();
const PORT = process.env.SERVICE_PORT || 8080;

// 環境變數
const API_USER_URL = process.env.API_USER_URL || 'http://api-user:8080';
const API_ORDER_URL = process.env.API_ORDER_URL || 'http://api-order:8080';
const API_PRODUCT_URL = process.env.API_PRODUCT_URL || 'http://api-product:8080';

app.use(express.json());

// 健康檢查
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'bff' });
});

// API 路由（轉發到 Backend APIs）
app.get('/api/users', async (req, res) => {
  try {
    const userId = req.headers['x-user-id'];
    console.log(`Forwarding request to ${API_USER_URL}/api/users, User: ${userId}`);
    
    // 示範回應（實際應該呼叫 Backend API）
    res.json({
      message: 'Users from BFF',
      authenticated_user: userId,
      source: API_USER_URL,
      data: ['user1', 'user2', 'user3']
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/orders', async (req, res) => {
  try {
    const userId = req.headers['x-user-id'];
    console.log(`Forwarding request to ${API_ORDER_URL}/api/orders, User: ${userId}`);
    
    res.json({
      message: 'Orders from BFF',
      authenticated_user: userId,
      source: API_ORDER_URL,
      data: ['order1', 'order2']
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/products', async (req, res) => {
  try {
    const userId = req.headers['x-user-id'];
    console.log(`Forwarding request to ${API_PRODUCT_URL}/api/products, User: ${userId}`);
    
    res.json({
      message: 'Products from BFF',
      authenticated_user: userId,
      source: API_PRODUCT_URL,
      data: ['product1', 'product2']
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`BFF Service listening on port ${PORT}`);
  console.log(`Backend APIs: User=${API_USER_URL}, Order=${API_ORDER_URL}, Product=${API_PRODUCT_URL}`);
});
EOF

# 安裝依賴
RUN npm install

# 暴露端口
EXPOSE 8080

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 執行應用程式
CMD ["npm", "start"]
