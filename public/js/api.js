// API client for ETL Server
const TOKEN_KEY    = 'etl_token';
const IS_ADMIN_KEY = 'etl_is_admin';

export const getToken   = () => localStorage.getItem(TOKEN_KEY);
export const setToken   = (t) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);
export const isLoggedIn = () => !!getToken();
export const isAdmin    = () => localStorage.getItem(IS_ADMIN_KEY) === 'true';

async function request(method, path, body = null) {
  const headers = { 'Content-Type': 'application/json' };
  const token = getToken();
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const opts = { method, headers };
  if (body !== null) opts.body = JSON.stringify(body);

  const res = await fetch(path, opts);

  if (res.status === 401) {
    clearToken();
    window.location.hash = '#/login';
    throw new Error('Session expired. Please log in again.');
  }

  if (res.status === 204) return null;

  const data = await res.json();
  if (!res.ok) {
    const msg = data.error || (Array.isArray(data.errors) ? data.errors.join(', ') : null) || 'Request failed';
    throw new Error(msg);
  }
  return data;
}

// Auth
export const login = async (email, password) => {
  const data = await request('POST', '/auth/login', { email, password });
  setToken(data.token);
  localStorage.setItem(IS_ADMIN_KEY, data.user?.is_admin ? 'true' : 'false');
  return data;
};
export const logout = async () => {
  clearToken();
  localStorage.removeItem(IS_ADMIN_KEY);
  await request('DELETE', '/auth/logout').catch(() => {});
};

// Flows
export const getFlows          = ()                    => request('GET',    '/flows');
export const getFlow           = (id)                  => request('GET',    `/flows/${id}`);
export const createFlow        = (id, flow)            => request('POST',   '/flows', { id, flow });
export const updateFlow        = (id, flow)            => request('PUT',    `/flows/${id}`, { flow });
export const deleteFlow        = (id)                  => request('DELETE', `/flows/${id}`);
export const copyFlow          = (source_id, dest_id)  => request('POST',   '/flows/copy', { source_id, dest_id });
export const updatePermissions = (id, permissions)     => request('PATCH',  `/flows/${id}/permissions`, { permissions });

// Account
export const getAccount    = ()     => request('GET',   '/account');
export const updateAccount = (data) => request('PATCH', '/account', data);

// Tokens
export const getTokens   = ()     => request('GET',    '/tokens');
export const createToken = (name) => request('POST',   '/tokens', { name });
export const deleteToken = (id)   => request('DELETE', `/tokens/${id}`);

// Schema
export const getCommandSchema   = () => request('GET', '/schema/commands');
export const getTransformSchema = () => request('GET', '/schema/transforms');

// Admin
export const getAdminUsers    = ()         => request('GET',    '/admin/users');
export const createAdminUser  = (user)     => request('POST',   '/admin/users', { user });
export const updateAdminUser  = (id, user) => request('PATCH',  `/admin/users/${id}`, { user });
export const deleteAdminUser  = (id)       => request('DELETE', `/admin/users/${id}`);

