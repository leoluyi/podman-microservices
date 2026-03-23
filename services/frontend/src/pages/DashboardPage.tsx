import React, { useState } from 'react';
import { useAuth } from '../auth/useAuth';
import client from '../api/client';

interface Order {
  id?: string;
  productId: string;
  quantity: number;
  status?: string;
  createdAt?: string;
}

export function DashboardPage() {
  const { user, logout, hasRole } = useAuth();

  const [orders, setOrders] = useState<Order[]>([]);
  const [ordersLoading, setOrdersLoading] = useState(false);
  const [ordersError, setOrdersError] = useState('');

  const [productId, setProductId] = useState('');
  const [quantity, setQuantity] = useState(1);
  const [createMsg, setCreateMsg] = useState('');
  const [creating, setCreating] = useState(false);

  const [apiResponse, setApiResponse] = useState<string>('');

  const fetchOrders = async () => {
    setOrdersLoading(true);
    setOrdersError('');
    try {
      const { data } = await client.get('/orders');
      setOrders(Array.isArray(data) ? data : data.content || []);
      setApiResponse(JSON.stringify(data, null, 2));
    } catch (err: unknown) {
      const msg = extractError(err);
      setOrdersError(msg);
      setApiResponse(msg);
    } finally {
      setOrdersLoading(false);
    }
  };

  const createOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setCreateMsg('');
    try {
      const { data } = await client.post('/orders', { productId, quantity });
      setCreateMsg(`Order created: ${data.id || JSON.stringify(data)}`);
      setApiResponse(JSON.stringify(data, null, 2));
      setProductId('');
      setQuantity(1);
    } catch (err: unknown) {
      const msg = extractError(err);
      setCreateMsg(msg);
      setApiResponse(msg);
    } finally {
      setCreating(false);
    }
  };

  const deleteOrder = async (id: string) => {
    try {
      await client.delete(`/orders/${id}`);
      setOrders((prev) => prev.filter((o) => o.id !== id));
      setApiResponse(`Deleted order ${id}`);
    } catch (err: unknown) {
      setApiResponse(extractError(err));
    }
  };

  return (
    <div style={{ maxWidth: 800, margin: '40px auto', padding: 24 }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <h1 style={{ margin: 0 }}>Dashboard</h1>
        <button
          onClick={logout}
          style={{ padding: '8px 16px', background: '#d32f2f', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer' }}
        >
          Logout
        </button>
      </header>

      {/* User Info */}
      <section style={{ background: '#f5f5f5', padding: 16, borderRadius: 4, marginBottom: 24 }}>
        <h2 style={{ marginTop: 0 }}>User Info</h2>
        <p><strong>Username:</strong> {user?.username}</p>
        <p><strong>Roles:</strong> {user?.roles.length ? user.roles.join(', ') : 'none'}</p>
        <p><strong>Permissions:</strong> {user?.permissions.length ? user.permissions.join(', ') : 'none'}</p>
      </section>

      {/* Create Order */}
      <section style={{ marginBottom: 24 }}>
        <h2>Create Order</h2>
        <form onSubmit={createOrder} style={{ display: 'flex', gap: 8, alignItems: 'flex-end', flexWrap: 'wrap' }}>
          <div>
            <label htmlFor="productId" style={{ display: 'block', marginBottom: 4, fontWeight: 500 }}>Product ID</label>
            <input
              id="productId"
              type="text"
              value={productId}
              onChange={(e) => setProductId(e.target.value)}
              required
              style={{ padding: 8 }}
            />
          </div>
          <div>
            <label htmlFor="quantity" style={{ display: 'block', marginBottom: 4, fontWeight: 500 }}>Quantity</label>
            <input
              id="quantity"
              type="number"
              min={1}
              value={quantity}
              onChange={(e) => setQuantity(Number(e.target.value))}
              required
              style={{ padding: 8, width: 80 }}
            />
          </div>
          <button
            type="submit"
            disabled={creating}
            style={{ padding: '8px 16px', background: '#1976d2', color: '#fff', border: 'none', borderRadius: 4, cursor: creating ? 'not-allowed' : 'pointer' }}
          >
            {creating ? 'Creating...' : 'Create'}
          </button>
        </form>
        {createMsg && <p style={{ marginTop: 8, color: createMsg.startsWith('Order created') ? '#2e7d32' : '#d32f2f' }}>{createMsg}</p>}
      </section>

      {/* Orders List */}
      <section style={{ marginBottom: 24 }}>
        <h2>Orders</h2>
        <button
          onClick={fetchOrders}
          disabled={ordersLoading}
          style={{ padding: '8px 16px', background: '#1976d2', color: '#fff', border: 'none', borderRadius: 4, cursor: ordersLoading ? 'not-allowed' : 'pointer', marginBottom: 12 }}
        >
          {ordersLoading ? 'Loading...' : 'List Orders'}
        </button>

        {ordersError && <p style={{ color: '#d32f2f' }}>{ordersError}</p>}

        {orders.length > 0 && (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #ccc', textAlign: 'left' }}>
                <th style={{ padding: 8 }}>ID</th>
                <th style={{ padding: 8 }}>Product</th>
                <th style={{ padding: 8 }}>Qty</th>
                <th style={{ padding: 8 }}>Status</th>
                <th style={{ padding: 8 }}>Created</th>
                {hasRole('ADMIN') && <th style={{ padding: 8 }}>Actions</th>}
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr key={order.id} style={{ borderBottom: '1px solid #eee' }}>
                  <td style={{ padding: 8, fontFamily: 'monospace', fontSize: 13 }}>{order.id}</td>
                  <td style={{ padding: 8 }}>{order.productId}</td>
                  <td style={{ padding: 8 }}>{order.quantity}</td>
                  <td style={{ padding: 8 }}>{order.status || '-'}</td>
                  <td style={{ padding: 8 }}>{order.createdAt || '-'}</td>
                  {hasRole('ADMIN') && (
                    <td style={{ padding: 8 }}>
                      <button
                        onClick={() => order.id && deleteOrder(order.id)}
                        style={{ padding: '4px 8px', background: '#d32f2f', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer', fontSize: 12 }}
                      >
                        Delete
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      {/* API Response */}
      {apiResponse && (
        <section>
          <h2>Last API Response</h2>
          <pre style={{ background: '#263238', color: '#aed581', padding: 16, borderRadius: 4, overflow: 'auto', maxHeight: 300, fontSize: 13 }}>
            {apiResponse}
          </pre>
        </section>
      )}
    </div>
  );
}

function extractError(err: unknown): string {
  if (err && typeof err === 'object' && 'response' in err) {
    const axiosErr = err as { response?: { status?: number; data?: { message?: string } } };
    const status = axiosErr.response?.status || '';
    const message = axiosErr.response?.data?.message || 'Request failed';
    return `Error ${status}: ${message}`;
  }
  return 'Network error';
}
