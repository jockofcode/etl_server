import { logout, isAdmin } from './api.js';
import { go } from './router.js';

export function renderHeader() {
  return `
    <header class="app-header">
      <div class="header-brand">
        <span class="header-logo">⚙</span>
        <span class="header-title">ETL Flow Editor</span>
      </div>
      <nav class="header-nav">
        <a href="#/flows"   class="nav-link">Flows</a>
        <a href="#/account" class="nav-link">Account</a>
        ${isAdmin() ? '<a href="#/admin" class="nav-link">Admin</a>' : ''}
        <button class="btn btn-outline btn-sm" id="logout-btn">Sign Out</button>
      </nav>
    </header>
  `;
}

export function attachHeader(container) {
  const btn = container.querySelector('#logout-btn');
  if (btn) {
    btn.addEventListener('click', async () => {
      await logout();
      go('/login');
    });
  }
}

// Escape HTML to prevent XSS
export function esc(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Format a field value for display
export function displayValue(v) {
  if (v === null || v === undefined) return '<span style="color:var(--text-muted)">—</span>';
  if (typeof v === 'object') return `<pre class="node-field-value mono">${esc(JSON.stringify(v, null, 2))}</pre>`;
  return `<span class="node-field-value">${esc(String(v))}</span>`;
}

