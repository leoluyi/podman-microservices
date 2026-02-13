/**
 * Partner API Client - Node.js 範例
 *
 * 使用方式：
 * 1. 安裝依賴：npm install jsonwebtoken axios
 * 2. 設定環境變數：
 *    export JWT_SECRET_PARTNER_A="your-secret-from-provider"
 *    export PARTNER_ID="partner-company-a"
 *    export API_BASE_URL="https://your-api.com"
 * 3. 執行：node nodejs-client.js
 */

const jwt = require('jsonwebtoken');
const axios = require('axios');
const https = require('https');

class PartnerAPIClient {
    constructor(partnerId, jwtSecret, baseUrl) {
        this.partnerId = partnerId;
        this.jwtSecret = jwtSecret;
        this.baseUrl = baseUrl;

        // 開發環境：忽略自簽憑證警告
        this.httpClient = axios.create({
            httpsAgent: new https.Agent({
                rejectUnauthorized: false
            })
        });
    }

    /**
     * 產生 JWT Token
     * @param {number} expiresIn - Token 有效期（秒）
     * @returns {string} JWT Token
     */
    generateToken(expiresIn = 3600) {
        const payload = {
            sub: this.partnerId,
            iat: Math.floor(Date.now() / 1000),
            exp: Math.floor(Date.now() / 1000) + expiresIn
        };

        return jwt.sign(payload, this.jwtSecret, {
            algorithm: 'HS256'
        });
    }

    /**
     * 取得訂單列表（GET - 需要 orders:read 權限）
     */
    async getOrders() {
        const token = this.generateToken();

        try {
            const response = await this.httpClient.get(
                `${this.baseUrl}/partner/api/order/`,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                }
            );
            return response.data;
        } catch (error) {
            this.handleError(error, 'GET /partner/api/order/');
        }
    }

    /**
     * 創建訂單（POST - 需要 orders:write 權限）
     */
    async createOrder(orderData) {
        const token = this.generateToken();

        try {
            const response = await this.httpClient.post(
                `${this.baseUrl}/partner/api/order/`,
                orderData,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json'
                    }
                }
            );
            return response.data;
        } catch (error) {
            this.handleError(error, 'POST /partner/api/order/');
        }
    }

    /**
     * 取得產品列表（GET - 需要 products:read 權限）
     */
    async getProducts() {
        const token = this.generateToken();

        try {
            const response = await this.httpClient.get(
                `${this.baseUrl}/partner/api/product/`,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                }
            );
            return response.data;
        } catch (error) {
            this.handleError(error, 'GET /partner/api/product/');
        }
    }

    /**
     * 取得用戶資訊（GET - 需要 users:read 權限）
     */
    async getUsers() {
        const token = this.generateToken();

        try {
            const response = await this.httpClient.get(
                `${this.baseUrl}/partner/api/user/`,
                {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                }
            );
            return response.data;
        } catch (error) {
            this.handleError(error, 'GET /partner/api/user/');
        }
    }

    /**
     * 錯誤處理
     */
    handleError(error, endpoint) {
        if (error.response) {
            // API 返回錯誤
            console.error(`API Error [${endpoint}]:`, error.response.status, error.response.data);

            if (error.response.status === 401) {
                console.error('認證失敗：請檢查 JWT Secret 和 Partner ID');
            } else if (error.response.status === 403) {
                console.error('權限不足：您的 Partner 沒有訪問此 API 的權限');
            }
        } else if (error.request) {
            // 請求發送但沒有回應
            console.error(`Network Error [${endpoint}]:`, error.message);
        } else {
            // 其他錯誤
            console.error(`Error [${endpoint}]:`, error.message);
        }
        throw error;
    }
}

// ============================================================================
// 使用範例
// ============================================================================

async function main() {
    // 從環境變數讀取配置
    const partnerId = process.env.PARTNER_ID || 'partner-company-a';
    const jwtSecret = process.env.JWT_SECRET_PARTNER_A || 'dev-secret-partner-a-change-in-production-32chars';
    const baseUrl = process.env.API_BASE_URL || 'https://localhost';

    console.log('Partner API Client');
    console.log('==================');
    console.log(`Partner ID: ${partnerId}`);
    console.log(`Base URL: ${baseUrl}`);
    console.log('');

    const client = new PartnerAPIClient(partnerId, jwtSecret, baseUrl);

    try {
        // 範例 1：取得訂單
        console.log('1. 取得訂單列表...');
        const orders = await client.getOrders();
        console.log('✓ 訂單：', orders);
        console.log('');

        // 範例 2：取得產品
        console.log('2. 取得產品列表...');
        const products = await client.getProducts();
        console.log('✓ 產品：', products);
        console.log('');

        // 範例 3：取得用戶（可能會失敗，取決於權限）
        console.log('3. 取得用戶資訊...');
        try {
            const users = await client.getUsers();
            console.log('✓ 用戶：', users);
        } catch (error) {
            console.log('✗ 無權訪問用戶 API');
        }
        console.log('');

        // 範例 4：創建訂單（可能會失敗，取決於權限）
        console.log('4. 創建訂單...');
        try {
            const newOrder = await client.createOrder({
                product_id: '123',
                quantity: 5
            });
            console.log('✓ 訂單已創建：', newOrder);
        } catch (error) {
            console.log('✗ 無權創建訂單');
        }

    } catch (error) {
        console.error('執行失敗');
        process.exit(1);
    }
}

// 如果直接執行此檔案
if (require.main === module) {
    main();
}

module.exports = PartnerAPIClient;
