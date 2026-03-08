import { getAccount, updateAccount, getTokens, createToken, deleteToken } from '../api.js';
import { renderHeader, attachHeader, esc } from '../layout.js';

export async function mount(container) {
  container.innerHTML = renderHeader() + `
    <main class="main-content">

      <section class="account-section">
        <h2 class="section-title">Account</h2>
        <div id="account-form-area"><div class="loading">Loading…</div></div>
      </section>

      <section class="account-section">
        <div class="section-header">
          <h2 class="section-title">API Tokens</h2>
          <button class="btn btn-primary btn-sm" id="new-token-btn">+ New Token</button>
        </div>
        <p class="section-desc">
          Tokens authenticate requests to your flow subdomains
          (<code>username.etl.cnxkit.com/flow-id</code>).
          A token is only shown once — copy it when you create it.
        </p>
        <div id="tokens-list"><div class="loading">Loading…</div></div>
      </section>

    </main>
    <div id="modal-root"></div>
  `;

  attachHeader(container);

  const formArea   = container.querySelector('#account-form-area');
  const tokensList = container.querySelector('#tokens-list');

  // ── Account section ─────────────────────────────────────────────────────────

  async function loadAccount() {
    try {
      const acct = await getAccount();
      renderAccountForm(acct);
    } catch (err) {
      formArea.innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
    }
  }

  function renderAccountForm(acct) {
    formArea.innerHTML = `
      <div id="acct-msg"></div>
      <div class="form-group">
        <label class="form-label">Email</label>
        <div class="account-static">${esc(acct.email)}</div>
      </div>
      <div class="account-save-row">
        <div class="form-group" style="flex:1;margin-bottom:0">
          <label class="form-label" for="username-input">Username</label>
          <input class="form-control" id="username-input"
            value="${esc(acct.username || '')}"
            placeholder="e.g. jockofcode" maxlength="63">
          <p class="field-hint">
            Lowercase letters, digits, and hyphens only — cannot start or end with a hyphen.
            Becomes your subdomain: <code>username.etl.cnxkit.com</code>
          </p>
        </div>
        <button class="btn btn-primary" id="save-username-btn">Save</button>
      </div>
    `;

    formArea.querySelector('#save-username-btn').addEventListener('click', async () => {
      const input    = formArea.querySelector('#username-input');
      const msgEl    = formArea.querySelector('#acct-msg');
      const btn      = formArea.querySelector('#save-username-btn');
      const username = input.value.trim() || null;
      msgEl.innerHTML = '';

      if (username && !/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?$/.test(username)) {
        msgEl.innerHTML = `<div class="alert alert-error">Use only lowercase letters, digits, and hyphens. Cannot start or end with a hyphen.</div>`;
        return;
      }

      btn.disabled = true;
      try {
        const updated = await updateAccount({ username });
        input.value = updated.username || '';
        msgEl.innerHTML = `<div class="alert alert-success">Username saved.</div>`;
        setTimeout(() => { msgEl.innerHTML = ''; }, 3000);
      } catch (err) {
        msgEl.innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
      } finally {
        btn.disabled = false;
      }
    });
  }

  // ── Tokens section ──────────────────────────────────────────────────────────

  async function loadTokens() {
    try {
      const tokens = await getTokens();
      renderTokens(tokens);
    } catch (err) {
      tokensList.innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
    }
  }

  function renderTokens(tokens) {
    if (!tokens.length) {
      tokensList.innerHTML = `<div class="empty-state">No tokens yet. Create one to authenticate your flow requests.</div>`;
      return;
    }
    tokensList.innerHTML = `
      <table class="tokens-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Created</th>
            <th>Last used</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${tokens.map(t => `
            <tr>
              <td class="token-name">${esc(t.name)}</td>
              <td class="token-date">${fmtDate(t.created_at)}</td>
              <td class="token-date">${t.last_used_at
                ? fmtDate(t.last_used_at)
                : '<span class="text-muted">Never</span>'}</td>
              <td class="token-actions-cell">
                <button class="btn btn-danger btn-sm"
                  data-action="revoke"
                  data-id="${t.id}"
                  data-name="${esc(t.name)}">Revoke</button>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
  }

  tokensList.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-action="revoke"]');
    if (!btn) return;
    if (!confirm(`Revoke token "${btn.dataset.name}"? Any app using it will stop working immediately.`)) return;
    try {
      await deleteToken(btn.dataset.id);
      loadTokens();
    } catch (err) { alert(err.message); }
  });

  container.querySelector('#new-token-btn').addEventListener('click', () => {
    showNewTokenModal(container, loadTokens);
  });

  loadAccount();
  loadTokens();
}

// ── New token modal ──────────────────────────────────────────────────────────

function showNewTokenModal(container, onCreated) {
  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="tok-modal">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">New API Token</span>
          <button class="modal-close" id="tok-close">✕</button>
        </div>
        <div class="modal-body">
          <div id="tok-create-form">
            <div class="form-group">
              <label class="form-label required" for="tok-name">Token name</label>
              <input class="form-control" id="tok-name" placeholder="e.g. production, my-app" autofocus>
              <p class="field-hint">A label to identify this token later.</p>
            </div>
            <div id="tok-error" class="alert alert-error hidden"></div>
          </div>
          <div id="tok-reveal" class="hidden">
            <div class="alert alert-success" style="margin-bottom:1rem">
              Token created. Copy it now — it won't be shown again.
            </div>
            <div class="token-reveal-box">
              <code id="tok-value" class="token-value-text"></code>
              <button class="btn btn-ghost btn-sm" id="tok-copy-btn">Copy</button>
            </div>
          </div>
        </div>
        <div class="modal-footer" id="tok-footer">
          <button class="btn btn-ghost" id="tok-cancel">Cancel</button>
          <button class="btn btn-primary" id="tok-create">Create Token</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; };
  root.querySelector('#tok-close').addEventListener('click', close);
  root.querySelector('#tok-cancel').addEventListener('click', close);
  root.querySelector('#tok-modal').addEventListener('click', (e) => {
    if (e.target === e.currentTarget) close();
  });

  root.querySelector('#tok-create').addEventListener('click', async () => {
    const name  = root.querySelector('#tok-name').value.trim();
    const errEl = root.querySelector('#tok-error');
    errEl.classList.add('hidden');

    if (!name) {
      errEl.textContent = 'Name is required.';
      errEl.classList.remove('hidden');
      return;
    }

    const createBtn = root.querySelector('#tok-create');
    createBtn.disabled = true;

    try {
      const token = await createToken(name);

      // Swap to reveal view
      root.querySelector('#tok-create-form').classList.add('hidden');
      root.querySelector('#tok-value').textContent = token.token;
      root.querySelector('#tok-reveal').classList.remove('hidden');

      // Replace footer with a single Done button
      root.querySelector('#tok-footer').innerHTML =
        `<button class="btn btn-primary" id="tok-done">Done</button>`;
      root.querySelector('#tok-done').addEventListener('click', () => {
        close();
        onCreated();
      });

      root.querySelector('#tok-copy-btn').addEventListener('click', () => {
        navigator.clipboard.writeText(token.token).then(() => {
          const copyBtn = root.querySelector('#tok-copy-btn');
          copyBtn.textContent = 'Copied!';
          setTimeout(() => { if (copyBtn) copyBtn.textContent = 'Copy'; }, 2000);
        });
      });
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
      createBtn.disabled = false;
    }
  });
}

function fmtDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric'
  });
}
