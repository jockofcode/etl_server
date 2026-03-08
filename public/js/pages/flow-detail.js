import { getFlow, updateFlow, deleteFlow, getCommandSchema, getAccount, updatePermissions } from '../api.js';
import { go } from '../router.js';
import { renderHeader, attachHeader, esc, displayValue } from '../layout.js';

// ── State ────────────────────────────────────────────────────────────────────
let flowId      = null;
let flowData    = {};   // raw YAML data { START_NODE, ...nodes }
let chainData   = {};   // { entry_node, chain }
let schema      = {};   // { type -> { fields: { name -> { type, required, description } } } }
let username    = null; // current user's subdomain username
let selectedKey = null; // currently open node detail

// ── Entry point ───────────────────────────────────────────────────────────────
export async function mount(container, id) {
  flowId = id;
  selectedKey = null;

  container.innerHTML = renderHeader() + `
    <main class="main-content" id="detail-main">
      <div class="loading">Loading flow…</div>
    </main>
    <div id="modal-root"></div>
  `;
  attachHeader(container);

  try {
    const [flowResp, schemaResp, accountResp] = await Promise.all([getFlow(id), getCommandSchema(), getAccount()]);
    flowData  = flowResp.flow;
    chainData = flowResp.chain;
    schema    = schemaResp;
    username  = accountResp?.username || null;
    renderPage(container);
  } catch (err) {
    container.querySelector('#detail-main').innerHTML =
      `<div class="alert alert-error">${esc(err.message)}</div>`;
  }
}

// ── Page render ───────────────────────────────────────────────────────────────
function renderPage(container) {
  const start = flowData.START_NODE || {};
  const main  = container.querySelector('#detail-main');

  main.innerHTML = `
    <a href="#/flows" class="back-link">← All Flows</a>
    <div class="flow-detail-header">
      <div class="flow-detail-meta">
        <h1>${esc(start.name || flowId)}</h1>
        ${start.description ? `<p>${esc(start.description)}</p>` : ''}
        <p style="margin-top:.25rem;font-family:monospace;font-size:.8rem;color:var(--text-muted)">${esc(flowId)}</p>
      </div>
      <div class="flow-detail-actions">
        <button class="btn btn-ghost" id="run-btn">▶ Run Flow</button>
        <button class="btn btn-ghost" id="share-btn">⇀ Share</button>
        <button class="btn btn-primary" id="add-node-btn">+ Add Operation</button>
      </div>
    </div>
    <div id="chain-root" class="chain-scroll-wrap">
      ${renderDiagram(chainData.chain || [])}
    </div>
    <div class="chain-add-row">
      <p style="font-size:.8rem;color:var(--text-muted)">Click any operation to view its details.</p>
    </div>
  `;

  attachChainEvents(main, container);

  main.querySelector('#run-btn').addEventListener('click', () => {
    if (!username) {
      alert('Set a username on your Account page before running flows.');
      return;
    }
    window.open(`https://${username}.etl.cnxkit.com/${flowId}`, '_blank');
  });

  main.querySelector('#share-btn').addEventListener('click', () => {
    showShareModal(container);
  });

  main.querySelector('#add-node-btn').addEventListener('click', () => {
    showAddNodeModal(container);
  });
}

// ── Diagram layout constants ───────────────────────────────────────────────────
const NODE_W  = 220; // must match .op-block width in CSS
const NODE_H  = 78;  // rendered op-block height at default font size
const H_GAP   = 48;  // horizontal space for connector line between nodes
const V_GAP   = 24;  // vertical gap between branch rows
const BOX_PAD = 10;  // padding around for_each outline box

// Recursively computes absolute pixel positions for nodes, edges, and loop boxes.
// Returns { nodes: [{key, node, x, y}], edges: [{x1,y1,x2,y2,type}], boxes: [{x,y,width,height,label}], width, height }
function layoutChain(chain, x0, y0) {
  if (!chain || chain.length === 0) return { nodes: [], edges: [], boxes: [], width: 0, height: NODE_H };

  const nodes = [];
  const edges = [];
  const boxes = [];
  let x      = x0;
  let height = NODE_H;

  for (let i = 0; i < chain.length; i++) {
    const step = chain[i];
    nodes.push({ key: step.key, node: step.node, x, y: y0 });

    if (step.branches.on_success?.length || step.branches.on_failure?.length || step.branches.next_branches?.length) {
      const forkX = x + NODE_W + H_GAP;
      const fromX = x + NODE_W;
      const fromY = y0 + NODE_H / 2;
      let   curY  = y0;
      let   maxW  = 0;

      // Each element in on_success/on_failure/next_branches is itself a chain (array of steps).
      for (const chain of (step.branches.on_success || [])) {
        const r = layoutChain(chain, forkX, curY);
        edges.push({ x1: fromX, y1: fromY, x2: forkX, y2: curY + NODE_H / 2, type: 'success' });
        nodes.push(...r.nodes);
        edges.push(...r.edges);
        boxes.push(...r.boxes);
        maxW  = Math.max(maxW, r.width);
        curY += Math.max(r.height, NODE_H) + V_GAP;
      }

      for (const chain of (step.branches.on_failure || [])) {
        const r = layoutChain(chain, forkX, curY);
        edges.push({ x1: fromX, y1: fromY, x2: forkX, y2: curY + NODE_H / 2, type: 'failure' });
        nodes.push(...r.nodes);
        edges.push(...r.edges);
        boxes.push(...r.boxes);
        maxW  = Math.max(maxW, r.width);
        curY += Math.max(r.height, NODE_H) + V_GAP;
      }

      for (const chain of (step.branches.next_branches || [])) {
        const r = layoutChain(chain, forkX, curY);
        edges.push({ x1: fromX, y1: fromY, x2: forkX, y2: curY + NODE_H / 2, type: 'normal' });
        nodes.push(...r.nodes);
        edges.push(...r.edges);
        boxes.push(...r.boxes);
        maxW  = Math.max(maxW, r.width);
        curY += Math.max(r.height, NODE_H) + V_GAP;
      }

      const branchCount = (step.branches.on_success?.length || 0)
                        + (step.branches.on_failure?.length || 0)
                        + (step.branches.next_branches?.length || 0);
      height = branchCount > 0 ? Math.max(curY - V_GAP - y0, NODE_H) : NODE_H;
      x = forkX + maxW;
      break;
    }

    if (step.branches.iterator) {
      const forkX    = x + NODE_W + H_GAP;
      const ir       = layoutChain(step.branches.iterator, forkX, y0);
      const iterEndX = forkX + (ir.width || 0);
      edges.push({ x1: x + NODE_W, y1: y0 + NODE_H / 2, x2: forkX,    y2: y0 + NODE_H / 2, type: 'iterator' });
      nodes.push(...ir.nodes);
      edges.push(...ir.edges);
      height = Math.max(height, ir.height);

      // Outline box around the for_each node + its entire iterator sub-chain.
      // Outer box is pushed first (drawn behind), then nested ir.boxes on top.
      const boxH = Math.max(NODE_H, ir.height || 0) + BOX_PAD * 2;
      const label = `for each ${step.node.item_key || 'item'}`;
      boxes.push({ x: x - BOX_PAD, y: y0 - BOX_PAD, width: (iterEndX - x) + BOX_PAD * 2, height: boxH, label });
      boxes.push(...ir.boxes);

      if (i < chain.length - 1) {
        // Exit connector branches off the for_each box's right border, not from the last iterator node.
        edges.push({ x1: iterEndX + BOX_PAD, y1: y0 + NODE_H / 2, x2: iterEndX + H_GAP, y2: y0 + NODE_H / 2, type: 'foreach_next' });
        x = iterEndX + H_GAP;
      } else {
        x = iterEndX;
      }
    } else {
      if (i < chain.length - 1) {
        edges.push({ x1: x + NODE_W, y1: y0 + NODE_H / 2, x2: x + NODE_W + H_GAP, y2: y0 + NODE_H / 2, type: 'normal' });
        x += NODE_W + H_GAP;
      } else {
        x += NODE_W;
      }
    }
  }

  return { nodes, edges, boxes, width: x - x0, height };
}

// Returns an SVG path string for a connector between two points.
// Straight horizontal if y is the same; right-angle elbow otherwise.
function elbowPath(x1, y1, x2, y2) {
  if (Math.abs(y2 - y1) < 2) return `M ${x1} ${y1} H ${x2}`;
  const midX = Math.round(x1 + (x2 - x1) / 2);
  return `M ${x1} ${y1} H ${midX} V ${y2} H ${x2}`;
}

// Renders the full diagram as a position:relative container with SVG overlay
// and absolutely positioned op-block divs.
function renderDiagram(chain) {
  if (!chain || chain.length === 0) {
    return '<p class="empty-state">No operations yet.</p>';
  }

  const PAD = 20;
  const { nodes, edges, boxes, width, height } = layoutChain(chain, PAD, PAD);
  const W = width  + PAD * 2;
  const H = height + PAD * 2;

  // Boxes are rendered first (behind edges and nodes).
  // A white background rect at the top-left of each box creates a "legend" slot for the label.
  const boxSvg = boxes.map(({ x, y, width: bw, height: bh, label }) => {
    const labelBgW = label.length * 6.5 + 12;
    return [
      `<rect x="${x}" y="${y}" width="${bw}" height="${bh}" rx="8" fill="rgba(99,102,241,0.05)" stroke="#6366f1" stroke-width="1.5" stroke-dasharray="6 3"/>`,
      `<rect x="${x + 10}" y="${y - 8}" width="${labelBgW}" height="15" fill="#f8fafc"/>`,
      `<text x="${x + 14}" y="${y + 3}" fill="#6366f1" font-size="10" font-family="system-ui,sans-serif" font-weight="600" letter-spacing="0.3">${esc(label)}</text>`,
    ].join('');
  }).join('');

  const paths = edges.map(({ x1, y1, x2, y2, type }) => {
    const color = type === 'success'      ? '#16a34a'
                : type === 'failure'      ? '#dc2626'
                : type === 'iterator'     ? '#6366f1'
                : type === 'foreach_next' ? '#6366f1'
                : '#94a3b8';
    const dash = type === 'foreach_next' ? ' stroke-dasharray="5 3"' : '';
    return `<path d="${elbowPath(x1, y1, x2, y2)}" stroke="${color}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"${dash}/>`;
  }).join('');

  const nodeHtml = nodes.map(({ key, node, x, y }) => {
    const type = node.type || 'start';
    const isSelected = key === selectedKey;
    const isBranchNode = !!(flowData[key]?.on_success || flowData[key]?.on_failure || Array.isArray(flowData[key]?.next));
    const addBtn = isBranchNode ? '' : `<button class="node-add-btn" data-action="add-after" data-key="${esc(key)}">+</button>`;
    return `<div class="op-block${isSelected ? ' selected' : ''}" data-action="select-node" data-key="${esc(key)}" style="position:absolute;left:${x}px;top:${y}px">
      <span class="op-key">${esc(key)}</span>
      <span class="op-badge badge-${esc(type)}">${esc(type.replace(/_/g, ' '))}</span>
      ${addBtn}
    </div>`;
  }).join('');

  return `<div style="position:relative;width:${W}px;height:${H}px;min-height:${H}px">
    <svg style="position:absolute;top:0;left:0" width="${W}" height="${H}" overflow="visible">
      ${boxSvg}
      ${paths}
    </svg>
    ${nodeHtml}
  </div>`;
}

// ── Event wiring ──────────────────────────────────────────────────────────────
function attachChainEvents(main, container) {
  main.querySelector('#chain-root').addEventListener('click', (e) => {
    // "+" add-after button — must be checked before select-node since it sits inside the block
    const addBtn = e.target.closest('[data-action="add-after"]');
    if (addBtn) {
      e.stopPropagation();
      showAddNodeModal(container, addBtn.dataset.key);
      return;
    }

    const block = e.target.closest('[data-action="select-node"]');
    if (!block) return;
    const key = block.dataset.key;
    selectedKey = key;
    main.querySelectorAll('.op-block').forEach(b => b.classList.toggle('selected', b.dataset.key === key));
    showNodeDetail(container, key);
  });
}

// ── Node detail card (modal) ──────────────────────────────────────────────────
function showNodeDetail(container, key) {
  const node = flowData[key];
  if (!node) return;
  const type    = node.type || 'start';
  const fields  = Object.entries(node).filter(([k]) => k !== 'type');
  const isStart = key === 'START_NODE';

  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="detail-overlay">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">
            <span class="op-badge badge-${esc(type)}" style="font-size:.65rem">${esc(type.replace(/_/g,' '))}</span>
            ${esc(key)}
          </span>
          <button class="modal-close" id="detail-close">✕</button>
        </div>
        <div class="modal-body">
          ${fields.map(([k, v]) => `
            <div class="node-detail-field">
              <div class="node-field-name">${esc(k)}</div>
              ${displayValue(v)}
            </div>
          `).join('')}
          ${fields.length === 0 ? '<p style="color:var(--text-muted);font-size:.875rem">No fields defined.</p>' : ''}
        </div>
        <div class="modal-footer">
          ${!isStart ? `<button class="btn btn-danger btn-sm" id="detail-remove">Remove</button>` : ''}
          <button class="btn btn-ghost btn-sm" id="detail-edit">Edit</button>
          <button class="btn btn-primary btn-sm" id="detail-close2">Close</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; selectedKey = null; container.querySelector('.op-block.selected')?.classList.remove('selected'); };
  root.querySelector('#detail-close').addEventListener('click', close);
  root.querySelector('#detail-close2').addEventListener('click', close);
  root.querySelector('#detail-overlay').addEventListener('click', (e) => { if (e.target === e.currentTarget) close(); });
  root.querySelector('#detail-edit')?.addEventListener('click', () => showEditNodeModal(container, key));
  root.querySelector('#detail-remove')?.addEventListener('click', () => handleRemoveNode(container, key));
}

// ── Remove node ───────────────────────────────────────────────────────────────
async function handleRemoveNode(container, key) {
  if (!confirm(`Remove operation "${key}"? References to it will be cleared.`)) return;
  const node = flowData[key];
  const successor = node.next || node.on_success || null;

  // Redirect any pointers that target this key to its successor
  for (const [, n] of Object.entries(flowData)) {
    if (!n || typeof n !== 'object') continue;
    for (const ptr of ['next', 'on_success', 'on_failure', 'iterator', 'after_iterator']) {
      if (n[ptr] === key) n[ptr] = successor || null;
    }
  }
  delete flowData[key];

  try {
    await updateFlow(flowId, flowData);
    const resp  = await getFlow(flowId);
    flowData  = resp.flow;
    chainData = resp.chain;
    selectedKey = null;
    renderPage(container);
  } catch (err) { alert(err.message); }
}

// ── Node-array chip input helpers ─────────────────────────────────────────────
// Renders a tag/chip input for fields of type "node_array".
function nodeArrayInput(name, values) {
  const chips = values.map(v =>
    `<span class="user-chip" data-value="${esc(v)}">${esc(v)}<button type="button" class="chip-remove" data-name="${esc(name)}" data-value="${esc(v)}" title="Remove">×</button></span>`
  ).join('');
  return `<div class="node-chips-wrap" data-field="${esc(name)}">
    <div class="chips-list node-array-chips">${chips}</div>
    <div style="display:flex;gap:.4rem;margin-top:.35rem">
      <input class="form-control node-array-input" style="flex:1" placeholder="node key…" data-for="${esc(name)}">
      <button type="button" class="btn btn-ghost btn-sm node-array-add" data-for="${esc(name)}">+</button>
    </div>
  </div>`;
}

// Wires chip-add and chip-remove events on a form containing node-array fields.
function setupNodeArrayInputs(form) {
  if (!form) return;
  form.addEventListener('click', (e) => {
    const removeBtn = e.target.closest('.chip-remove[data-name]');
    if (removeBtn) { removeBtn.closest('.user-chip').remove(); return; }
    const addBtn = e.target.closest('.node-array-add');
    if (addBtn) addNodeArrayChip(form, addBtn.dataset.for);
  });
  form.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.matches('.node-array-input')) {
      e.preventDefault();
      addNodeArrayChip(form, e.target.dataset.for);
    }
  });
}

function addNodeArrayChip(form, name) {
  const input = form.querySelector(`.node-array-input[data-for="${name}"]`);
  if (!input) return;
  const val = input.value.trim();
  if (!val) return;
  const wrap  = form.querySelector(`[data-field="${name}"]`);
  const chips = wrap.querySelector('.node-array-chips');
  if (!Array.from(chips.querySelectorAll('.user-chip')).some(c => c.dataset.value === val)) {
    const span = document.createElement('span');
    span.className = 'user-chip';
    span.dataset.value = val;
    span.innerHTML = `${esc(val)}<button type="button" class="chip-remove" data-name="${esc(name)}" data-value="${esc(val)}" title="Remove">×</button>`;
    chips.appendChild(span);
  }
  input.value = '';
}

// Reads chip values from a node-array field wrap.
// Returns: undefined (0 chips), string (1 chip), or array (2+ chips).
function readNodeArrayField(form, name) {
  const wrap = form?.querySelector(`[data-field="${name}"]`);
  if (!wrap) return undefined;
  const vals = Array.from(wrap.querySelectorAll('.user-chip')).map(c => c.dataset.value);
  if (vals.length === 0) return undefined;
  return vals.length === 1 ? vals[0] : vals;
}

// ── Edit node modal ───────────────────────────────────────────────────────────
function showEditNodeModal(container, key) {
  const node    = flowData[key] || {};
  const type    = node.type || 'START_NODE';
  const isStart = key === 'START_NODE';
  const cmdSchema = !isStart ? (schema[type] || null) : null;
  const fields    = cmdSchema ? Object.entries(cmdSchema.fields) : [];

  const startFields = isStart ? [
    { name: 'name',        spec: { type: 'string',     required: true,  description: 'Display name for this flow' } },
    { name: 'description', spec: { type: 'string',     required: false, description: 'Optional description' } },
    { name: 'next',        spec: { type: 'node_array', required: false, description: 'First operation key(s)' } },
  ] : [];

  const allFields = isStart ? startFields.map(f => [f.name, f.spec]) : fields;

  function fieldInput(name, spec) {
    const val = node[name];
    if (spec.type === 'node_array') {
      const values = val == null ? [] : Array.isArray(val) ? val : [ String(val) ];
      return nodeArrayInput(name, values);
    }
    const disp = (val === null || val === undefined) ? '' : (typeof val === 'object' ? JSON.stringify(val, null, 2) : String(val));
    if (spec.type === 'object' || spec.type === 'array') {
      return `<textarea class="form-control" name="${esc(name)}" rows="4">${esc(disp)}</textarea>`;
    }
    if (spec.type === 'integer') {
      return `<input class="form-control" type="number" name="${esc(name)}" value="${esc(disp)}">`;
    }
    return `<input class="form-control" type="text" name="${esc(name)}" value="${esc(disp)}">`;
  }

  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="edit-overlay">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">Edit — ${esc(key)}</span>
          <button class="modal-close" id="edit-close">✕</button>
        </div>
        <div class="modal-body">
          ${cmdSchema ? `<p class="modal-subtitle">${esc(cmdSchema.description || '')}</p>` : ''}
          <form id="edit-form" novalidate>
            ${allFields.map(([name, spec]) => `
              <div class="form-group">
                <label class="form-label${spec.required ? ' required' : ''}">
                  ${esc(name)}
                  <span class="field-type">${esc(spec.type)}</span>
                </label>
                ${fieldInput(name, spec)}
                ${spec.description ? `<p class="field-hint">${esc(spec.description)}</p>` : ''}
              </div>
            `).join('')}
          </form>
          <div id="edit-error" class="alert alert-error hidden"></div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-ghost" id="edit-cancel">Cancel</button>
          <button class="btn btn-primary" id="edit-save">Save Changes</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; showNodeDetail(container, key); };
  root.querySelector('#edit-close').addEventListener('click', close);
  root.querySelector('#edit-cancel').addEventListener('click', close);
  root.querySelector('#edit-overlay').addEventListener('click', (e) => { if (e.target === e.currentTarget) close(); });

  setupNodeArrayInputs(root.querySelector('#edit-form'));

  root.querySelector('#edit-save').addEventListener('click', async () => {
    const form   = root.querySelector('#edit-form');
    const errEl  = root.querySelector('#edit-error');
    errEl.classList.add('hidden');

    const updated = { ...node };
    for (const [name, spec] of allFields) {
      if (spec.type === 'node_array') {
        const val = readNodeArrayField(form, name);
        if (val === undefined) { delete updated[name]; } else { updated[name] = val; }
        continue;
      }
      const el  = form.querySelector(`[name="${name}"]`);
      if (!el) continue;
      const raw = el.value.trim();
      if (raw === '') { delete updated[name]; continue; }
      if (spec.type === 'object' || spec.type === 'array') {
        try { updated[name] = JSON.parse(raw); }
        catch { errEl.textContent = `"${name}" must be valid JSON.`; errEl.classList.remove('hidden'); return; }
      } else if (spec.type === 'integer') {
        updated[name] = parseInt(raw, 10);
      } else {
        updated[name] = raw;
      }
    }

    flowData[key] = updated;
    try {
      await updateFlow(flowId, flowData);
      const resp  = await getFlow(flowId);
      flowData  = resp.flow;
      chainData = resp.chain;
      renderPage(container);
      showNodeDetail(container, key);
    } catch (err) {
      flowData[key] = node; // rollback local change
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  });
}

// ── Share / permissions modal ─────────────────────────────────────────────────
function showShareModal(container) {
  const perms       = flowData.START_NODE?.permissions || {};
  let localPublic   = perms.public === true;
  let localShared   = Array.isArray(perms.shared_with) ? [ ...perms.shared_with ] : [];

  const renderChips = () => localShared.map(u =>
    `<span class="user-chip">${esc(u)}<button class="chip-remove" data-user="${esc(u)}" title="Remove">×</button></span>`
  ).join('');

  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="share-overlay">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">Share Flow</span>
          <button class="modal-close" id="share-close">✕</button>
        </div>
        <div class="modal-body">
          <p class="modal-subtitle">Control who can run this flow at its URL.</p>
          <div class="form-group">
            <label class="form-label share-public-label">
              <input type="checkbox" id="perm-public"${localPublic ? ' checked' : ''}>
              Public — anyone with the link can run this flow
            </label>
          </div>
          <div class="form-group">
            <label class="form-label">Shared with specific users</label>
            <div id="chips-list" class="chips-list">${renderChips()}</div>
            <div style="display:flex;gap:.5rem;margin-top:.5rem">
              <input class="form-control" id="add-user-input" placeholder="Enter a username">
              <button class="btn btn-ghost btn-sm" id="add-user-btn">Add</button>
            </div>
            <p class="field-hint">Users listed here can run this flow even if it is not public.</p>
          </div>
          <div id="share-error" class="alert alert-error hidden"></div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-ghost" id="share-cancel">Cancel</button>
          <button class="btn btn-primary" id="share-save">Save Changes</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; };
  root.querySelector('#share-close').addEventListener('click', close);
  root.querySelector('#share-cancel').addEventListener('click', close);
  root.querySelector('#share-overlay').addEventListener('click', (e) => { if (e.target === e.currentTarget) close(); });

  root.querySelector('#perm-public').addEventListener('change', (e) => {
    localPublic = e.target.checked;
  });

  root.querySelector('#chips-list').addEventListener('click', (e) => {
    const btn = e.target.closest('.chip-remove');
    if (!btn) return;
    localShared = localShared.filter(u => u !== btn.dataset.user);
    root.querySelector('#chips-list').innerHTML = renderChips();
  });

  const doAddUser = () => {
    const input    = root.querySelector('#add-user-input');
    const username = input.value.trim().toLowerCase();
    const errEl    = root.querySelector('#share-error');
    errEl.classList.add('hidden');
    if (!username) return;
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(username)) {
      errEl.textContent = 'Invalid username — only lowercase letters, digits, and hyphens.';
      errEl.classList.remove('hidden');
      return;
    }
    if (!localShared.includes(username)) {
      localShared.push(username);
      root.querySelector('#chips-list').innerHTML = renderChips();
    }
    input.value = '';
  };

  root.querySelector('#add-user-btn').addEventListener('click', doAddUser);
  root.querySelector('#add-user-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') doAddUser(); });

  root.querySelector('#share-save').addEventListener('click', async () => {
    const errEl = root.querySelector('#share-error');
    errEl.classList.add('hidden');
    try {
      await updatePermissions(flowId, { public: localPublic, shared_with: localShared });
      const resp = await getFlow(flowId);
      flowData  = resp.flow;
      chainData = resp.chain;
      close();
    } catch (err) {
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  });
}

// ── Add node modal ────────────────────────────────────────────────────────────
function showAddNodeModal(container, afterKey = null) {
  const typeOptions = Object.keys(schema).map(t =>
    `<option value="${esc(t)}">${esc(t.replace(/_/g, ' '))}</option>`
  ).join('');

  const subtitle = afterKey
    ? `New operation will be inserted after <strong>${esc(afterKey)}</strong>.`
    : `Choose a node ID and operation type. You can link it to other operations by editing
       the <code>next</code> / <code>on_success</code> / <code>on_failure</code> fields afterwards.`;

  const root = container.querySelector('#modal-root');
  root.innerHTML = `
    <div class="modal-overlay" id="add-overlay">
      <div class="modal">
        <div class="modal-header">
          <span class="modal-title">Add Operation</span>
          <button class="modal-close" id="add-close">✕</button>
        </div>
        <div class="modal-body">
          <p class="modal-subtitle">${subtitle}</p>
          <div class="form-group">
            <label class="form-label required">Node ID</label>
            <input class="form-control" id="add-key" placeholder="e.g. transform_step" pattern="[a-z0-9_\\-]+">
            <p class="field-hint">Lowercase letters, numbers, underscores and hyphens only.</p>
          </div>
          <div class="form-group">
            <label class="form-label required">Operation Type</label>
            <select class="form-control" id="add-type">
              <option value="">— select type —</option>
              ${typeOptions}
            </select>
          </div>
          <div id="add-fields"></div>
          <div id="add-error" class="alert alert-error hidden"></div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-ghost" id="add-cancel">Cancel</button>
          <button class="btn btn-primary" id="add-save">Add Operation</button>
        </div>
      </div>
    </div>
  `;

  const close = () => { root.innerHTML = ''; };
  root.querySelector('#add-close').addEventListener('click', close);
  root.querySelector('#add-cancel').addEventListener('click', close);
  root.querySelector('#add-overlay').addEventListener('click', (e) => { if (e.target === e.currentTarget) close(); });

  // Dynamically show fields when type changes
  root.querySelector('#add-type').addEventListener('change', (e) => {
    const type = e.target.value;
    const fieldsDiv = root.querySelector('#add-fields');
    if (!type || !schema[type]) { fieldsDiv.innerHTML = ''; return; }
    const cmdFields = Object.entries(schema[type].fields);
    fieldsDiv.innerHTML = cmdFields.map(([name, spec]) => `
      <div class="form-group">
        <label class="form-label${spec.required ? ' required' : ''}">
          ${esc(name)} <span class="field-type">${esc(spec.type)}</span>
        </label>
        ${spec.type === 'node_array'
          ? nodeArrayInput(name, [])
          : spec.type === 'object' || spec.type === 'array'
            ? `<textarea class="form-control" name="${esc(name)}" rows="3"></textarea>`
            : spec.type === 'integer'
              ? `<input class="form-control" type="number" name="${esc(name)}">`
              : `<input class="form-control" type="text" name="${esc(name)}">`
        }
        ${spec.description ? `<p class="field-hint">${esc(spec.description)}</p>` : ''}
      </div>
    `).join('');
    setupNodeArrayInputs(fieldsDiv);
  });

  root.querySelector('#add-save').addEventListener('click', async () => {
    const errEl  = root.querySelector('#add-error');
    const nodeId = root.querySelector('#add-key').value.trim();
    const type   = root.querySelector('#add-type').value;
    errEl.classList.add('hidden');

    if (!nodeId) { errEl.textContent = 'Node ID is required.'; errEl.classList.remove('hidden'); return; }
    if (!/^[a-z0-9_-]+$/.test(nodeId)) { errEl.textContent = 'Node ID may only contain lowercase letters, numbers, _ and -.'; errEl.classList.remove('hidden'); return; }
    if (!type) { errEl.textContent = 'Operation type is required.'; errEl.classList.remove('hidden'); return; }
    if (flowData[nodeId]) { errEl.textContent = `A node with ID "${nodeId}" already exists.`; errEl.classList.remove('hidden'); return; }

    const newNode = { type };
    const form = root.querySelector('#add-fields');
    if (form && schema[type]) {
      for (const [name, spec] of Object.entries(schema[type].fields)) {
        if (spec.type === 'node_array') {
          const val = readNodeArrayField(form, name);
          if (val !== undefined) newNode[name] = val;
          continue;
        }
        const el = form.querySelector(`[name="${name}"]`);
        if (!el) continue;
        const raw = el.value.trim();
        if (!raw) continue;
        if (spec.type === 'object' || spec.type === 'array') {
          try { newNode[name] = JSON.parse(raw); }
          catch { errEl.textContent = `"${name}" must be valid JSON.`; errEl.classList.remove('hidden'); return; }
        } else if (spec.type === 'integer') {
          newNode[name] = parseInt(raw, 10);
        } else {
          newNode[name] = raw;
        }
      }
    }

    flowData[nodeId] = newNode;

    // If triggered from a node's "+" button, insert into the chain:
    // new node inherits the source's current next, source points to new node.
    if (afterKey && flowData[afterKey]) {
      const oldNext = flowData[afterKey].next;
      if (oldNext) newNode.next = oldNext;
      flowData[afterKey] = { ...flowData[afterKey], next: nodeId };
    }

    try {
      await updateFlow(flowId, flowData);
      const resp  = await getFlow(flowId);
      flowData  = resp.flow;
      chainData = resp.chain;
      close();
      renderPage(container);
    } catch (err) {
      // Rollback both the new node and any source pointer change
      delete flowData[nodeId];
      if (afterKey && flowData[afterKey]) {
        const src = flowData[afterKey];
        if (src.next === nodeId) {
          src.next ? delete src.next : null;
          flowData[afterKey] = { ...src, next: newNode.next || undefined };
        }
      }
      errEl.textContent = err.message;
      errEl.classList.remove('hidden');
    }
  });
}

