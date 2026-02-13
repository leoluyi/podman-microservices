"""
Partner API Client - Python 範例

使用方式：
1. 安裝依賴：pip install pyjwt requests
2. 設定環境變數：
   export JWT_SECRET_PARTNER_A="your-secret-from-provider"
   export PARTNER_ID="partner-company-a"
   export API_BASE_URL="https://your-api.com"
3. 執行：python python-client.py
"""

import jwt
import requests
import time
import os
from typing import Dict, Any, Optional
from urllib3.exceptions import InsecureRequestWarning

# 開發環境：禁用 SSL 警告
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)


class PartnerAPIClient:
    def __init__(self, partner_id: str, jwt_secret: str, base_url: str):
        self.partner_id = partner_id
        self.jwt_secret = jwt_secret
        self.base_url = base_url.rstrip('/')

    def generate_token(self, expires_in: int = 3600) -> str:
        """
        產生 JWT Token

        Args:
            expires_in: Token 有效期（秒），預設 1 小時

        Returns:
            JWT Token 字串
        """
        payload = {
            'sub': self.partner_id,
            'iss': 'partner-api-system',
            'aud': 'partner-api',
            'iat': int(time.time()),
            'exp': int(time.time()) + expires_in
        }

        return jwt.encode(payload, self.jwt_secret, algorithm='HS256')

    def _make_request(
        self,
        method: str,
        endpoint: str,
        data: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        發送 HTTP 請求

        Args:
            method: HTTP 方法（GET, POST, PUT, DELETE）
            endpoint: API 端點
            data: 請求資料（可選）

        Returns:
            API 回應資料
        """
        token = self.generate_token()
        url = f"{self.base_url}{endpoint}"

        headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }

        try:
            response = requests.request(
                method=method,
                url=url,
                json=data,
                headers=headers,
                verify=False  # 開發環境：忽略 SSL 驗證
            )

            response.raise_for_status()
            return response.json() if response.text else {}

        except requests.exceptions.HTTPError as e:
            self._handle_http_error(e, endpoint)
        except requests.exceptions.RequestException as e:
            print(f"Network Error [{endpoint}]: {str(e)}")
            raise

    def _handle_http_error(
        self,
        error: requests.exceptions.HTTPError,
        endpoint: str
    ):
        """處理 HTTP 錯誤"""
        status_code = error.response.status_code
        try:
            error_data = error.response.json()
        except:
            error_data = {'error': error.response.text}

        print(f"API Error [{endpoint}]: {status_code} - {error_data}")

        if status_code == 401:
            print("認證失敗：請檢查 JWT Secret 和 Partner ID")
        elif status_code == 403:
            print("權限不足：您的 Partner 沒有訪問此 API 的權限")

        raise error

    # ========================================================================
    # API 方法
    # ========================================================================

    def get_orders(self) -> Dict[str, Any]:
        """取得訂單列表（需要 orders:read 權限）"""
        return self._make_request('GET', '/partner/api/order/')

    def create_order(self, order_data: Dict[str, Any]) -> Dict[str, Any]:
        """創建訂單（需要 orders:write 權限）"""
        return self._make_request('POST', '/partner/api/order/', order_data)

    def update_order(self, order_id: str, order_data: Dict[str, Any]) -> Dict[str, Any]:
        """更新訂單（需要 orders:write 權限）"""
        return self._make_request('PUT', f'/partner/api/order/{order_id}', order_data)

    def get_products(self) -> Dict[str, Any]:
        """取得產品列表（需要 products:read 權限）"""
        return self._make_request('GET', '/partner/api/product/')

    def create_product(self, product_data: Dict[str, Any]) -> Dict[str, Any]:
        """創建產品（需要 products:write 權限）"""
        return self._make_request('POST', '/partner/api/product/', product_data)

    def get_users(self) -> Dict[str, Any]:
        """取得用戶資訊（需要 users:read 權限）"""
        return self._make_request('GET', '/partner/api/user/')


# ============================================================================
# 使用範例
# ============================================================================

def main():
    # 從環境變數讀取配置
    partner_id = os.getenv('PARTNER_ID', 'partner-company-a')
    jwt_secret = os.getenv(
        'JWT_SECRET_PARTNER_A',
        'dev-secret-partner-a-change-in-production-32chars'
    )
    base_url = os.getenv('API_BASE_URL', 'https://localhost')

    print('Partner API Client')
    print('==================')
    print(f'Partner ID: {partner_id}')
    print(f'Base URL: {base_url}')
    print()

    client = PartnerAPIClient(partner_id, jwt_secret, base_url)

    try:
        # 範例 1：取得訂單
        print('1. 取得訂單列表...')
        orders = client.get_orders()
        print(f'✓ 訂單：{orders}')
        print()

        # 範例 2：取得產品
        print('2. 取得產品列表...')
        products = client.get_products()
        print(f'✓ 產品：{products}')
        print()

        # 範例 3：取得用戶（可能會失敗，取決於權限）
        print('3. 取得用戶資訊...')
        try:
            users = client.get_users()
            print(f'✓ 用戶：{users}')
        except requests.exceptions.HTTPError:
            print('✗ 無權訪問用戶 API')
        print()

        # 範例 4：創建訂單（可能會失敗，取決於權限）
        print('4. 創建訂單...')
        try:
            new_order = client.create_order({
                'product_id': '123',
                'quantity': 5
            })
            print(f'✓ 訂單已創建：{new_order}')
        except requests.exceptions.HTTPError:
            print('✗ 無權創建訂單')
        print()

        print('✓ 測試完成')

    except Exception as e:
        print(f'執行失敗：{str(e)}')
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
