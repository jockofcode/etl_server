import { getAdminUsers, createAdminUser, updateAdminUser, deleteAdminUser, isAdmin } from '../api.js';
import { renderHeader, attachHeader, esc } from '../layout.js';
import { go } from '../router.js';

export async function mount(container) {
  if (!isAdmin()) { go('/flows'); return; }

  container.innerHTML = renderHeader() + `
    <main class="main-content">
      <section class="account-section">
        <div class="section-header">
          <h2 class="section-title">Users</h2>
          <button class="btn btn-primary btn-sm" id="new-user-btn">+ New User</button>
        </div>
        <div id="users-list"><div class="loading">Loading…</div></div>
      </section>
    </main>
    <div id="modal-root"></div>
  `;

  attachHeader(container);

  const listEl = container.querySelector('#users-list');

  async function loadUsers() {
    try {
      const users = await getAdminUsers();
      renderUsers(users);
    } catch (err) {
      listEl.innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
    }
  }

  function renderUsers(users) {
    if (!users.length) {
      listEl.innerHTML = `<div class="empty-state">No users found.</div>`;
      return;
    }
    listEl.innerHTML = `
      <table class="tokens-table">
        <thead>
          <tr>
            <th>Email</th>
            <th>Username</th>
            <th>Admin</th>
            <th>Created</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${users.map(u => `
            <tr>
              <td>${esc(u.email)}</td>
              <td class="token-date">${u.username ? esc(u.username) : '<span class="text-muted">—</span>'}</td>
              <td>${u.is_admin ? '<span class="admin-badge">Admin</span>' : ''}</td>
              <td class="token-date">${fmtDate(u.created_at)}</td>
              <td class="token-actions-cell">
                <button class="btn btn-ghost btn-sm" data-action="edit" data-id="${u.id}">Edit</button>
                <button class="btn btn-danger btn-sm" data-action="delete" data-id="${u.id}" data-email="${esc(u.email)}">Delete</button>
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
  }

  listEl.addEventListener('click', async (e) => {
    const editBtn = e.target.closest('[data-action="edit"]');
    if (editBtn) {
      const users = await getAdminUsers().catch(() => []);
      const user = users.find(u => String(u.id) === editBtn.dataset.id);
      if (user) showUserModal(container, user, loadUsers);
      return;
    }

    const delBtn = e.target.closest('[data-action="delete"]');
    if (delBtn) {
      if (!confirm(`Delete user "${delBtn.dataset.email}"? This cannot be undone.`)) return;
      try {
        await deleteAdminUser(delBtn.dataset.id);
        loadUsers();
      } catch (err) { alert(err.message); }
    }
  });

  container.querySelector('#new-user-btn').addEventListener('click', () => {
    showUserModal(container, null, loadUsers);
  });

  loadUsers();
}

function showUserModal(container, user, onSaved) {
  const isNew = !user;
  const root = container.querySelector('#modal-root');

  root.innerHTML = `
    <div class="modal-overlay" id="user-modal">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">${isNew ? 'New User' : 'Edit User'}</span>
          <button class="modal-close" id="um-close">✕</button>
        </div>
        <div class="modal-body">
          <div id="um-error" class="alert alert-error hidden"></div>
          <div class="form-group">
            <label class="form-label required" for="um-email">Email</label>
            <input class="form-control" id="um-email" type="email" value="${esc(user?.email || '')}" autocomplete="off">
          </div>
          <div class="form-group">
            <label class="form-label" for="um-username">Username</label>
            <input class="form-control" id="um-username" value="${esc(user?.username || '')}" placeholder="e.g. jockofcode">
            <p class="field-hint">Lowercase letters, digits, hyphens. Leave blank to clear.</p>
          </div>
          <div class="form-group">
            <label class="form-label ${isNew ? 'required' : ''}" for="um-password">Password</label>
            <input class="form-control" id="um-password" type="password" autocomplete="new-password"
              placeholder="${isNew ? '' : 'Leave blank to keep current'}">
          </div>
          <div class="form-group">
            <label class="form-label ${isNew ? 'required' : ''}" for="um-password-conf">Confirm Password</label>
            <input class="form-control" id="um-password-conf" type="password" autocomplete="new-password"
              placeholder="${isNew ? '' : 'Leave blank to keep current'}">
          </div>
          <div class="form-group">
            <label class="form-label admin-check-label">
              <input type="checkbox" id="um-is-admin" ${user?.is_admin ? 'checked' : ''}>
              Admin
            </label>
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-ghost" id="um-cancel">Cancel</button>
          <button class="btn btn-primary" id="um-save">${isNew ? 'Create' : 'Save'}</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; };
  root.querySelector('#um-close').addEventListener('click', close);
  root.querySelector('#um-cancel').addEventListener('click', close);
  root.querySelector('#user-modal').addEventListener('click', (e) => {
    if (e.target === e.currentTarget) close();
  });

  root.querySelector('#um-save').addEventListener('click', async () => {
    const errEl    = root.querySelector('#um-error');
    const saveBtn  = root.querySelector('#um-save');
    const email    = root.querySelector('#um-email').value.trim();
    const username = root.querySelector('#um-username').value.trim() || null;
    const password = root.querySelector('#um-password').value;
    const passwordConf = root.querySelector('#um-password-conf').value;
    const isAdminCheck = root.querySelector('#um-is-admin').checked;

    errEl.classList.add('hidden');

    if (!email) {
      errEl.textContent = 'Email is required.';
      errEl.classList.remove('hidden');
      return;
    }
    if (isNew && !password) {
      errEl.textContent = 'Password is required.';
      errEl.classList.remove('hidden');
      return;
    }
    if (password && password !== passwordConf) {
      errEl.textContent = 'Passwords do not match.';
      errEl.classList.remove('hidden');
      return;
    }

    saveBtn.disabled = true;

    const payload = { email, username, is_admin: isAdminCheck };
    if (password) {
      payload.password = password;
      payload.password_confirmation = passwordConf;
    }

    try {
      if (isNew) {
        await createAdminUser(payload);
      } else {
        await updateAdminUser(user.id, payload);
      }
      close();
      onSaved();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
      saveBtn.disabled = false;
    }
  });
}

function fmtDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric'
  });
}
