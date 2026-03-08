import { getFlows, createFlow, deleteFlow } from '../api.js';
import { go } from '../router.js';
import { renderHeader, attachHeader, esc } from '../layout.js';

export async function mount(container) {
  const flash = new URLSearchParams(window.location.search).get('flash');
  const flashHtml = flash === 'unauthorized'
    ? `<div class="alert alert-error flash-banner" id="flash-banner">
         You don't have permission to run that flow.
         <button class="flash-close" id="flash-close">✕</button>
       </div>`
    : '';

  container.innerHTML = renderHeader() + `
    <main class="main-content">
      ${flashHtml}
      <div class="page-toolbar">
        <input type="search" id="search" class="search-input" placeholder="Search flows by name or ID…">
        <button class="btn btn-primary" id="new-flow-btn">+ New Flow</button>
      </div>
      <div id="flows-grid" class="flows-grid">
        <div class="loading">Loading flows…</div>
      </div>
    </main>
    <div id="modal-root"></div>
  `;

  attachHeader(container);

  if (flash) {
    // Remove the flash param from the URL without triggering a reload
    const clean = new URL(window.location.href);
    clean.searchParams.delete('flash');
    history.replaceState(null, '', clean.toString());

    container.querySelector('#flash-close')?.addEventListener('click', () => {
      container.querySelector('#flash-banner')?.remove();
    });
  }

  let allFlows = [];
  const grid = container.querySelector('#flows-grid');

  async function loadFlows() {
    try {
      allFlows = await getFlows();
      renderFlows(allFlows);
    } catch (err) {
      grid.innerHTML = `<div class="alert alert-error">${esc(err.message)}</div>`;
    }
  }

  function renderFlows(flows) {
    if (!flows.length) {
      grid.innerHTML = '<div class="empty-state">No flows found. Create your first flow!</div>';
      return;
    }
    grid.innerHTML = flows.map(f => `
      <div class="flow-card">
        <div class="flow-card-header">
          <span class="flow-card-name">${esc(f.name)}</span>
          <span class="flow-card-id">${esc(f.id)}</span>
        </div>
        ${f.description ? `<p class="flow-card-desc">${esc(f.description)}</p>` : ''}
        <div class="flow-card-actions">
          <button class="btn btn-primary btn-sm" data-action="open" data-id="${esc(f.id)}">Open</button>
          <button class="btn btn-danger  btn-sm" data-action="delete" data-id="${esc(f.id)}">Delete</button>
        </div>
      </div>
    `).join('');
  }

  // Search
  container.querySelector('#search').addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase();
    renderFlows(allFlows.filter(f =>
      (f.name || '').toLowerCase().includes(q) ||
      (f.id || '').toLowerCase().includes(q) ||
      (f.description || '').toLowerCase().includes(q)
    ));
  });

  // Grid delegation
  grid.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const { action, id } = btn.dataset;
    if (action === 'open') { go(`/flows/${id}`); return; }
    if (action === 'delete') {
      if (!confirm(`Delete flow "${id}"? This cannot be undone.`)) return;
      try {
        await deleteFlow(id);
        allFlows = allFlows.filter(f => f.id !== id);
        renderFlows(allFlows);
      } catch (err) { alert(err.message); }
    }
  });

  // New flow
  container.querySelector('#new-flow-btn').addEventListener('click', () => showNewFlowModal(container, async () => {
    allFlows = await getFlows();
    renderFlows(allFlows);
  }));

  loadFlows();
}

function showNewFlowModal(container, onCreated) {
  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="new-modal">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">Create New Flow</span>
          <button class="modal-close" id="modal-close-btn">✕</button>
        </div>
        <div class="modal-body">
          <p class="modal-subtitle">Flow IDs can only contain lowercase letters, numbers, underscores and hyphens.</p>
          <form id="new-flow-form" novalidate>
            <div class="form-group">
              <label class="form-label required" for="nf-id">Flow ID</label>
              <input class="form-control" id="nf-id" placeholder="e.g. my_etl_flow" pattern="[a-z0-9_\\-]+" required>
            </div>
            <div class="form-group">
              <label class="form-label required" for="nf-name">Name</label>
              <input class="form-control" id="nf-name" placeholder="Human-readable name" required>
            </div>
            <div class="form-group">
              <label class="form-label" for="nf-desc">Description</label>
              <textarea class="form-control" id="nf-desc" rows="2" placeholder="Optional description"></textarea>
            </div>
            <div id="nf-error" class="alert alert-error hidden"></div>
          </form>
        </div>
        <div class="modal-footer">
          <button class="btn btn-ghost" id="modal-cancel-btn">Cancel</button>
          <button class="btn btn-primary" id="modal-create-btn">Create Flow</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; };
  root.querySelector('#modal-close-btn').addEventListener('click', close);
  root.querySelector('#modal-cancel-btn').addEventListener('click', close);
  root.querySelector('#new-modal').addEventListener('click', (e) => { if (e.target === e.currentTarget) close(); });

  root.querySelector('#modal-create-btn').addEventListener('click', async () => {
    const id   = root.querySelector('#nf-id').value.trim();
    const name = root.querySelector('#nf-name').value.trim();
    const desc = root.querySelector('#nf-desc').value.trim();
    const errEl = root.querySelector('#nf-error');
    errEl.classList.add('hidden');

    if (!id || !name) { errEl.textContent = 'ID and Name are required.'; errEl.classList.remove('hidden'); return; }
    if (!/^[a-z0-9_-]+$/.test(id)) { errEl.textContent = 'ID may only contain lowercase letters, numbers, _ and -.'; errEl.classList.remove('hidden'); return; }

    try {
      await createFlow(id, { START_NODE: { name, ...(desc ? { description: desc } : {}) } });
      close();
      await onCreated();
    } catch (err) { errEl.textContent = err.message; errEl.classList.remove('hidden'); }
  });
}

