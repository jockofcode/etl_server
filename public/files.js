// ── Utilities ───────────────────────────────────────────────────────────────
function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function humanizeBytes(b) {
  if (!b) return '0 B';
  const u = ['B','KB','MB','GB','TB'];
  const e = Math.min(Math.floor(Math.log(b) / Math.log(1024)), u.length - 1);
  return (b / Math.pow(1024, e)).toFixed(1) + '\u202f' + u[e];
}
const IMAGE_EXTS = new Set(['jpg','jpeg','png','gif','webp','svg','bmp','ico','avif']);
function isImage(name) { return IMAGE_EXTS.has((name.split('.').pop() || '').toLowerCase()); }
function fileBadge(name) {
  const ext = (name.split('.').pop() || '').toLowerCase();
  const m = { pdf:['#dc2626','PDF'], doc:['#2563eb','DOC'], docx:['#2563eb','DOC'],
    xls:['#16a34a','XLS'], xlsx:['#16a34a','XLS'], csv:['#16a34a','XLS'],
    ppt:['#ea580c','PPT'], pptx:['#ea580c','PPT'],
    zip:['#7c3aed','ZIP'], tar:['#7c3aed','ZIP'], gz:['#7c3aed','ZIP'],
    rar:['#7c3aed','ZIP'], '7z':['#7c3aed','ZIP'], bz2:['#7c3aed','ZIP'],
    mp4:['#0891b2','VID'], mov:['#0891b2','VID'], avi:['#0891b2','VID'],
    mkv:['#0891b2','VID'], webm:['#0891b2','VID'], m4v:['#0891b2','VID'],
    mp3:['#db2777','AUD'], wav:['#db2777','AUD'], ogg:['#db2777','AUD'],
    flac:['#db2777','AUD'], m4a:['#db2777','AUD'], aac:['#db2777','AUD'],
    rb:['#1e293b','CODE'], py:['#1e293b','CODE'], js:['#1e293b','CODE'],
    ts:['#1e293b','CODE'], jsx:['#1e293b','CODE'], tsx:['#1e293b','CODE'],
    html:['#1e293b','CODE'], css:['#1e293b','CODE'], json:['#1e293b','CODE'],
    yml:['#1e293b','CODE'], yaml:['#1e293b','CODE'], sh:['#1e293b','CODE'],
    go:['#1e293b','CODE'], rs:['#1e293b','CODE'], swift:['#1e293b','CODE'],
    txt:['#6b7280','TXT'], md:['#6b7280','TXT'], log:['#6b7280','TXT'] };
  const [color, label] = m[ext] || ['#9ca3af', ext.toUpperCase().slice(0,4) || 'FILE'];
  return `<span class="file-badge" style="background:${color}">${label}</span>`;
}

// ── Window Manager ───────────────────────────────────────────────────────────
const windows = new Map();   // id → { id, type, path, el, selectedPaths, lastSelected }
let topZ = 100;
let activeWinId = null;
let winSeq = 0;
const isMac = /Mac|iPhone|iPad|iPod/.test(navigator.platform);

function genWinId() { return 'w' + (++winSeq); }

function openOrFocusWindow(type, path, title) {
  for (const [id, ws] of windows) {
    if (ws.type === type) { focusWindow(id); if (path !== ws.path) loadWindow(id, path); return; }
  }
  openWindow(type, path, title);
}

function openWindow(type, path, title) {
  const id   = genWinId();
  const icon = type === 'nas' ? '🖥' : '🏠';
  const ws   = { id, type, path, title, el: null, selectedPaths: new Set(), lastSelected: null };
  windows.set(id, ws);

  const el = document.createElement('div');
  el.className = 'win';
  el.id = id;
  const offset = (winSeq - 1) % 9;
  el.style.cssText = `left:${200 + offset * 26}px;top:${20 + offset * 24}px;width:720px;height:470px;z-index:${++topZ}`;

  el.innerHTML = `
    <div class="win-bar" onmousedown="startWinDrag(event,'${id}')">
      <div class="win-controls">
        <button class="win-btn win-close"  onclick="closeWindow('${id}')" title="Close"></button>
        <button class="win-btn win-min"    title="Minimise"></button>
        <button class="win-btn win-max"    title="Maximise"></button>
      </div>
      <span class="win-title" id="${id}-title">${esc(title)}</span>
      <span class="win-icon" style="width:18px">${icon}</span>
    </div>
    <nav class="win-nav" id="${id}-nav"><span style="color:#9ca3af;font-size:.75rem">Loading\u2026</span></nav>
    <div class="win-toolbar" id="${id}-toolbar">
      <label class="toolbar-btn">&#8679; Upload<input type="file" multiple onchange="winUpload('${id}',this)"></label>
      <button class="toolbar-btn" onclick="openWinCreateDir('${id}')">&#128193; New Folder</button>
    </div>
    <div class="win-body" id="${id}-body"
         onclick="winBodyClick(event,'${id}')"
         ondragover="winDragOver(event,'${id}')"
         ondrop="winDrop(event,'${id}')"
         ondragleave="winDragLeave(event,'${id}')"
         oncontextmenu="winContextMenu(event,'${id}')">
      <div class="win-loading">Loading\u2026</div>
    </div>`;

  ws.el = el;
  el.addEventListener('mousedown', () => focusWindow(id));
  document.getElementById('desktop').appendChild(el);
  focusWindow(id);
  loadWindow(id, path);
  return id;
}

function focusWindow(id) {
  if (!windows.has(id)) return;
  topZ++;
  windows.get(id).el.style.zIndex = topZ;
  for (const [wid, w] of windows) w.el.classList.toggle('win-focused', wid === id);
  activeWinId = id;
  // Highlight sidebar item
  document.querySelectorAll('.sidebar-item').forEach(s => s.classList.remove('sb-active'));
  const ws = windows.get(id);
  document.getElementById(ws.type === 'nas' ? 'nasSidebarBtn' : 'homeBtn')?.classList.add('sb-active');
}

function closeWindow(id) {
  windows.get(id)?.el.remove();
  windows.delete(id);
  if (activeWinId === id) { activeWinId = null; document.querySelectorAll('.sidebar-item').forEach(s => s.classList.remove('sb-active')); }
}

// ── Window title-bar drag ────────────────────────────────────────────────────
let winDragState = null;
function startWinDrag(e, id) {
  if (e.target.closest('.win-controls') || e.target.tagName === 'INPUT') return;
  focusWindow(id);
  const rect = windows.get(id).el.getBoundingClientRect();
  winDragState = { id, sx: e.clientX, sy: e.clientY, ol: rect.left, ot: rect.top };
  document.addEventListener('mousemove', onWinDrag);
  document.addEventListener('mouseup', stopWinDrag, { once: true });
  e.preventDefault();
}
function onWinDrag(e) {
  if (!winDragState) return;
  const ws = windows.get(winDragState.id);
  ws.el.style.left = Math.max(0, winDragState.ol + e.clientX - winDragState.sx) + 'px';
  ws.el.style.top  = Math.max(0, winDragState.ot + e.clientY - winDragState.sy) + 'px';
}
function stopWinDrag() { winDragState = null; document.removeEventListener('mousemove', onWinDrag); }

// ── Content loading ──────────────────────────────────────────────────────────
async function loadWindow(id, path) {
  const ws = windows.get(id);
  if (!ws) return;
  ws.path = path;
  const body = document.getElementById(id + '-body');
  body.innerHTML = '<div class="win-loading">Loading\u2026</div>';
  try {
    const url = ws.type === 'local'
      ? '/list?path=' + encodeURIComponent(path)
      : '/nas/browse?path=' + encodeURIComponent(path);
    const r = await fetch(url);
    const d = await r.json();
    if (!r.ok) { body.innerHTML = `<div class="win-error">${esc(d.error || 'Error')}</div>`; return; }
    renderWindowContent(id, d.items, path);
  } catch { body.innerHTML = '<div class="win-error">Network error</div>'; }
}

function renderWindowContent(id, items, path) {
  const ws = windows.get(id);
  if (!ws) return;
  ws.path = path;
  ws.selectedPaths.clear();
  ws.lastSelected = null;
  renderWinNav(id, path);
  const body = document.getElementById(id + '-body');
  if (!items || !items.length) { body.innerHTML = '<div class="win-empty">&#128194; This folder is empty</div>'; return; }
  const grid = document.createElement('div');
  grid.className = 'file-grid';
  items.forEach((item, idx) => grid.appendChild(createTile(id, item, idx, path)));
  body.innerHTML = '';
  body.appendChild(grid);
}

function renderWinNav(id, path) {
  const ws  = windows.get(id);
  const nav = document.getElementById(id + '-nav');
  const rootLabel = ws.type === 'nas' ? (nasUsername || 'NAS') : 'Home';
  let html = `<span class="nav-crumb" onclick="loadWindow('${id}','')">` + esc(rootLabel) + '</span>';
  const parts = path.split('/').filter(Boolean);
  parts.forEach((p, i) => {
    const sub = parts.slice(0, i + 1).join('/');
    html += `<span class="nav-sep">&#8250;</span><span class="nav-crumb" onclick="loadWindow('${id}','${esc(sub)}')">${esc(p)}</span>`;
  });
  nav.innerHTML = html;
  const titleEl = document.getElementById(id + '-title');
  if (titleEl) titleEl.textContent = parts.length ? parts[parts.length - 1] : (ws.type === 'nas' ? (nasUsername || 'NAS') : 'Home');
}

// ── Tile creation ────────────────────────────────────────────────────────────
function createTile(winId, item, idx, currentPath) {
  const ws = windows.get(winId);
  const itemPath = currentPath ? currentPath + '/' + item.name : item.name;
  const div = document.createElement('div');
  div.className = 'tile';
  Object.assign(div.dataset, { name: item.name, path: itemPath, type: item.type,
    size: humanizeBytes(item.size), mtime: item.mtime || '', idx, winId });
  if (item.type === 'file') div.draggable = true;

  let preview;
  if (item.type === 'dir') {
    preview = '<span class="folder-icon">&#128193;</span>';
  } else if (ws.type === 'local' && isImage(item.name)) {
    preview = `<img src="/download/${encodeURIComponent(itemPath)}" alt="${esc(item.name)}" loading="lazy">`;
  } else {
    preview = fileBadge(item.name);
  }
  div.innerHTML = `<div class="tile-preview">${preview}</div>
    <div class="tile-info"><div class="tile-name" title="${esc(item.name)}">${esc(item.name)}</div>
    <div class="tile-size">${humanizeBytes(item.size)}</div></div>`;

  div.addEventListener('click',     e => handleTileClick(e, div, winId));
  div.addEventListener('dblclick',  () => handleTileDblClick(div, winId));
  div.addEventListener('dragstart', e => tileDragStart(e, div, winId));
  div.addEventListener('dragend',   () => document.querySelectorAll('.win-body.drop-target').forEach(b => b.classList.remove('drop-target')));
  return div;
}

// ── Tile interaction ─────────────────────────────────────────────────────────
function handleTileClick(e, tile, winId) {
  if (e.detail === 2) return;
  focusWindow(winId);
  const ws = windows.get(winId);
  const useMeta = isMac ? e.metaKey : e.ctrlKey;
  const bodyTiles = () => Array.from(document.getElementById(winId + '-body').querySelectorAll('.tile'));
  if (e.shiftKey && ws.lastSelected) {
    const a = parseInt(ws.lastSelected.dataset.idx), b = parseInt(tile.dataset.idx);
    const [lo, hi] = a <= b ? [a, b] : [b, a];
    if (!useMeta) clearWinSel(winId);
    bodyTiles().filter(t => { const i = parseInt(t.dataset.idx); return i >= lo && i <= hi; })
      .forEach(t => { t.classList.add('selected'); ws.selectedPaths.add(t.dataset.path); });
  } else if (useMeta) {
    tile.classList.toggle('selected');
    tile.classList.contains('selected') ? ws.selectedPaths.add(tile.dataset.path) : ws.selectedPaths.delete(tile.dataset.path);
    ws.lastSelected = tile;
  } else {
    clearWinSel(winId);
    tile.classList.add('selected');
    ws.selectedPaths.add(tile.dataset.path);
    ws.lastSelected = tile;
  }
}

function handleTileDblClick(tile, winId) {
  focusWindow(winId);
  if (tile.dataset.type === 'dir') loadWindow(winId, tile.dataset.path);
}

function clearWinSel(winId) {
  const ws = windows.get(winId);
  if (!ws) return;
  ws.selectedPaths.clear(); ws.lastSelected = null;
  document.getElementById(winId + '-body')?.querySelectorAll('.tile.selected').forEach(t => t.classList.remove('selected'));
}
function winBodyClick(e, winId) { if (!e.target.closest('.tile')) clearWinSel(winId); }

// ── Inter-window drag & drop ─────────────────────────────────────────────────
function tileDragStart(e, tile, winId) {
  const ws = windows.get(winId);
  e.dataTransfer.effectAllowed = 'copy';
  e.dataTransfer.setData('application/x-etl-file', JSON.stringify({
    winId, winType: ws.type, path: tile.dataset.path, name: tile.dataset.name
  }));
}

function winDragOver(e, winId) {
  e.preventDefault();
  const hasInternal = e.dataTransfer.types.includes('application/x-etl-file');
  const hasFiles    = e.dataTransfer.types.includes('Files');
  if (hasInternal || hasFiles) {
    e.dataTransfer.dropEffect = 'copy';
    e.currentTarget.classList.add('drop-target');
  }
}
function winDragLeave(e, winId) {
  if (!e.currentTarget.contains(e.relatedTarget)) e.currentTarget.classList.remove('drop-target');
}
async function winDrop(e, destWinId) {
  e.preventDefault();
  e.currentTarget.classList.remove('drop-target');
  const raw = e.dataTransfer.getData('application/x-etl-file');
  if (raw) { await handleInternalDrop(JSON.parse(raw), destWinId); return; }
  if (e.dataTransfer.files.length) winUploadFiles(destWinId, Array.from(e.dataTransfer.files));
}

async function handleInternalDrop(src, destWinId) {
  if (src.winId === destWinId) return;
  const dest = windows.get(destWinId);
  if (!dest) return;
  if (src.winType === 'local' && dest.type === 'nas') {
    if (!nasConnected) { alert('Connect to NAS first.'); return; }
    const r = await fetch('/nas/copy', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ local_path: src.path, nas_path: dest.path }) });
    if (r.ok) startTransferPolling();
    else { const d = await r.json(); alert('Error: ' + (d.error || 'Copy failed')); }
  } else if (src.winType === 'nas' && dest.type === 'local') {
    const r = await fetch('/nas/copy-from-nas', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nas_path: src.path, local_path: dest.path }) });
    const d = await r.json();
    if (r.ok) loadWindow(destWinId, dest.path);
    else alert('Error: ' + (d.error || 'Copy failed'));
  } else if (src.winType === 'local' && dest.type === 'local') {
    const r = await fetch('/move', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ items: [src.path], destination: dest.path }) });
    if (r.ok) {
      const srcWin = windows.get(src.winId);
      if (srcWin) loadWindow(src.winId, srcWin.path);
      loadWindow(destWinId, dest.path);
    }
  }
}

// ── Context menus ────────────────────────────────────────────────────────────
let ctxWinId = null, ctxTargetTile = null;
const bgCtx = document.getElementById('bgCtx'), itemCtx = document.getElementById('itemCtx');
function hideCtx() { bgCtx.classList.remove('visible'); itemCtx.classList.remove('visible'); }
function positionCtx(menu, e) {
  menu.style.left = Math.min(e.clientX, window.innerWidth  - menu.offsetWidth  - 8) + 'px';
  menu.style.top  = Math.min(e.clientY, window.innerHeight - menu.offsetHeight - 8) + 'px';
}
document.addEventListener('click', e => { if (!e.target.closest('.ctx')) hideCtx(); });

function winContextMenu(e, winId) {
  e.preventDefault(); e.stopPropagation();
  focusWindow(winId);
  ctxWinId = winId;
  hideCtx();
  const ws   = windows.get(winId);
  const tile = e.target.closest('.tile');
  if (tile) {
    if (!tile.classList.contains('selected')) { clearWinSel(winId); tile.classList.add('selected'); ws.selectedPaths.add(tile.dataset.path); ws.lastSelected = tile; }
    ctxTargetTile = tile;
    const multi  = ws.selectedPaths.size > 1;
    const isFile = tile.dataset.type === 'file';
    const local  = ws.type === 'local';
    document.getElementById('ctxDownloadBtn').style.display  = (!multi && isFile && local) ? '' : 'none';
    document.getElementById('ctxNasDlBtn').style.display     = (!multi && isFile && ws.type === 'nas') ? '' : 'none';
    document.getElementById('ctxMoveBtn').style.display      = local ? '' : 'none';
    document.getElementById('ctxNasCopyBtn').style.display   = (isFile && local) ? '' : 'none';
    document.getElementById('ctxInfoBtn').style.display      = (!multi && local) ? '' : 'none';
    document.getElementById('ctxDeleteBtn').style.display    = local ? '' : 'none';
    itemCtx.style.cssText = 'left:-9999px;top:-9999px'; itemCtx.classList.add('visible'); positionCtx(itemCtx, e);
  } else {
    document.getElementById('bgCtxInfo').style.display = ws.type === 'local' ? '' : 'none';
    bgCtx.style.cssText = 'left:-9999px;top:-9999px'; bgCtx.classList.add('visible'); positionCtx(bgCtx, e);
  }
}

function ctxDownload() {
  hideCtx();
  if (!ctxTargetTile) return;
  const ws = windows.get(ctxWinId);
  const a = document.createElement('a');
  a.href     = (ws?.type === 'nas' ? '/nas/download/' : '/download/') + encodeURIComponent(ctxTargetTile.dataset.path);
  a.download = ctxTargetTile.dataset.name;
  document.body.appendChild(a); a.click(); a.remove();
}
function ctxDelete() {
  hideCtx();
  const ws = windows.get(ctxWinId);
  if (!ws) return;
  const items = Array.from(ws.selectedPaths);
  if (!items.length) return;
  const label = items.length === 1 ? '"' + items[0].split('/').pop() + '"' : items.length + ' items';
  if (!confirm('Delete ' + label + '?')) return;
  Promise.all(items.map(p => fetch('/delete/' + encodeURIComponent(p), { method: 'DELETE' })))
    .then(() => loadWindow(ctxWinId, ws.path));
}
function ctxInfo()    { hideCtx(); openInfo(ctxTargetTile, ctxWinId); }
function ctxMove()    { hideCtx(); openMoveModal(ctxWinId); }
function ctxNasCopy() {
  hideCtx();
  const ws = windows.get(ctxWinId);
  if (!ws) return;
  const fp = Array.from(ws.selectedPaths).filter(p => document.querySelector(`.tile[data-path="${CSS.escape(p)}"][data-type="file"]`));
  if (!fp.length) return;
  nasCopySource = fp[0];
  document.getElementById('nasCopyTitle').textContent = 'Copy \u201c' + nasCopySource.split('/').pop() + '\u201d to NAS';
  if (!nasConnected) { alert('Connect to NAS first.'); return; }
  loadNasCopyDirs('');
  document.getElementById('nasCopyModal').removeAttribute('hidden');
}
function bgCtxNewFolder() { hideCtx(); openWinCreateDir(ctxWinId); }

// ── Upload ───────────────────────────────────────────────────────────────────
const toast = document.getElementById('toast'), toastText = document.getElementById('toastText'), toastFill = document.getElementById('toastFill');
function winUpload(winId, input) { if (input.files.length) winUploadFiles(winId, Array.from(input.files)); input.value = ''; }
function winUploadFiles(winId, files) {
  const ws = windows.get(winId);
  if (!ws || ws.type !== 'local') return;
  let i = 0;
  toast.classList.add('visible');
  function next() {
    if (i >= files.length) { toast.classList.remove('visible'); loadWindow(winId, ws.path); return; }
    const file = files[i];
    toastText.textContent = file.name + ' (' + (i + 1) + '\u202f/\u202f' + files.length + ')';
    toastFill.style.width = '0%';
    const form = new FormData();
    form.append('file', file);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload?path=' + encodeURIComponent(ws.path));
    xhr.upload.onprogress = ev => { if (ev.lengthComputable) toastFill.style.width = (ev.loaded / ev.total * 100) + '%'; };
    xhr.onloadend = () => { i++; next(); };
    xhr.send(form);
  }
  next();
}

// ── Create folder ────────────────────────────────────────────────────────────
let activeCreateDirWinId = null;
function openWinCreateDir(winId) {
  activeCreateDirWinId = winId;
  document.getElementById('newDirName').value = '';
  document.getElementById('createDirModal').removeAttribute('hidden');
  setTimeout(() => document.getElementById('newDirName').focus(), 50);
}
function confirmCreateDir() {
  const name = document.getElementById('newDirName').value.trim();
  if (!name || /[\\/]/.test(name) || name.startsWith('.')) { alert('Invalid folder name'); return; }
  const ws = windows.get(activeCreateDirWinId);
  if (!ws) return;
  const fullPath = ws.path ? ws.path + '/' + name : name;
  const url = ws.type === 'nas' ? '/nas/mkdir' : '/mkdir';
  fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: fullPath }) })
    .then(r => { if (r.ok) { closeModal('createDirModal'); loadWindow(activeCreateDirWinId, ws.path); } else r.json().then(d => alert(d.error || 'Error')); });
}

// ── Info modal ───────────────────────────────────────────────────────────────
function openInfo(tile, winId) {
  const ws = windows.get(winId);
  if (!ws || ws.type !== 'local') return;
  const path = tile ? tile.dataset.path : ws.path;
  document.getElementById('infoTitle').textContent = tile ? tile.dataset.name : (ws.path.split('/').pop() || 'Home');
  document.getElementById('infoContent').innerHTML = '<p style="color:#9ca3af;font-size:.8rem">Loading\u2026</p>';
  document.getElementById('infoModal').removeAttribute('hidden');
  if (tile?.dataset.type === 'file') {
    const mtime = tile.dataset.mtime ? new Date(tile.dataset.mtime).toLocaleString() : '\u2014';
    document.getElementById('infoContent').innerHTML =
      '<table class="info-table"><tr><td>Kind</td><td>File</td></tr><tr><td>Size</td><td>' + esc(tile.dataset.size) +
      '</td></tr><tr><td>Modified</td><td>' + mtime + '</td></tr></table>';
  } else {
    fetch('/info?path=' + encodeURIComponent(path)).then(r => r.json()).then(d => {
      document.getElementById('infoContent').innerHTML =
        '<table class="info-table"><tr><td>Kind</td><td>Folder</td></tr><tr><td>Files</td><td>' + d.files +
        '</td></tr><tr><td>Subfolders</td><td>' + d.dirs + '</td></tr><tr><td>Total size</td><td>' + humanizeBytes(d.size) + '</td></tr></table>';
    });
  }
}

// ── Move modal ───────────────────────────────────────────────────────────────
let selectedDest = null, moveWinId = null;
function openMoveModal(winId) {
  moveWinId = winId;
  const ws = windows.get(winId);
  const count = ws?.selectedPaths.size || 0;
  document.getElementById('moveTitle').textContent =
    'Move ' + (count === 1 ? '\u201c' + Array.from(ws.selectedPaths)[0].split('/').pop() + '\u201d' : count + ' items') + ' to\u2026';
  document.getElementById('dirList').innerHTML = '<div class="dir-list-loading">Loading\u2026</div>';
  document.getElementById('confirmMoveBtn').disabled = true;
  selectedDest = null;
  document.getElementById('moveModal').removeAttribute('hidden');
  fetch('/dirs').then(r => r.json()).then(dirs => {
    const html = dirs.map(d => {
      const pad = 0.75 + d.depth * 1.1;
      const icon = d.depth === 0 ? '&#127968;' : '&#128193;';
      const cur  = d.path === ws?.path;
      return '<div class="dir-item' + (cur ? ' selected-dest' : '') + '" data-path="' + esc(d.path) +
        '" style="padding-left:' + pad + 'rem" onclick="pickDestDir(this)">' + icon + ' ' + esc(d.name) +
        (cur ? ' <span style="font-size:.7rem;color:#6b7280">(current)</span>' : '') + '</div>';
    }).join('');
    document.getElementById('dirList').innerHTML = html || '<div class="dir-list-loading">No folders</div>';
    const pre = document.querySelector('.dir-item.selected-dest');
    if (pre) { selectedDest = pre.dataset.path; document.getElementById('confirmMoveBtn').disabled = false; }
  });
}
function pickDestDir(el) {
  document.querySelectorAll('.dir-item').forEach(d => d.classList.remove('selected-dest'));
  el.classList.add('selected-dest'); selectedDest = el.dataset.path;
  document.getElementById('confirmMoveBtn').disabled = false;
}
function confirmMove() {
  if (selectedDest === null) return;
  const ws = windows.get(moveWinId);
  if (!ws) return;
  fetch('/move', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ items: Array.from(ws.selectedPaths), destination: selectedDest }) })
    .then(() => { closeModal('moveModal'); loadWindow(moveWinId, ws.path); });
}

// ── Modals ───────────────────────────────────────────────────────────────────
function closeModal(id) { document.getElementById(id).setAttribute('hidden', ''); }
document.querySelectorAll('.overlay').forEach(o => o.addEventListener('click', e => { if (e.target === o) o.setAttribute('hidden', ''); }));
document.getElementById('newDirName').addEventListener('keydown', e => { if (e.key === 'Enter') confirmCreateDir(); if (e.key === 'Escape') closeModal('createDirModal'); });

// ── Keyboard ─────────────────────────────────────────────────────────────────
document.addEventListener('keydown', e => {
  if (e.target.matches('input,textarea')) return;
  if (e.key === 'Escape') {
    hideCtx();
    ['infoModal','createDirModal','moveModal','nasCredModal','nasCopyModal'].forEach(closeModal);
  }
  if ((e.key === 'Delete' || e.key === 'Backspace') && activeWinId) {
    const ws = windows.get(activeWinId);
    if (ws?.type === 'local' && ws.selectedPaths.size) { e.preventDefault(); ctxWinId = activeWinId; ctxDelete(); }
  }
  if (e.key === 'a' && (isMac ? e.metaKey : e.ctrlKey) && activeWinId) {
    e.preventDefault();
    const ws = windows.get(activeWinId);
    document.getElementById(activeWinId + '-body')?.querySelectorAll('.tile').forEach(t => { t.classList.add('selected'); ws?.selectedPaths.add(t.dataset.path); });
  }
});

// ── NAS ──────────────────────────────────────────────────────────────────────
let nasConnected = false, nasUsername = '', nasCopySource = null, nasCopyDest = '';

fetch('/nas/status').then(r => r.json()).then(d => {
  nasConnected = d.connected; nasUsername = d.username || ''; updateNasSidebar();
}).catch(() => {});

function updateNasSidebar() {
  const existing = document.getElementById('nasSidebarBtn');
  const locs     = document.getElementById('sidebarLocations');
  if (nasConnected && nasUsername) {
    if (existing) { existing.querySelector('.nas-label').textContent = nasUsername; }
    else {
      const btn = document.createElement('button');
      btn.className = 'sidebar-item'; btn.id = 'nasSidebarBtn';
      btn.onclick = () => openOrFocusWindow('nas', '', nasUsername);
      btn.innerHTML = '<span class="sb-icon">&#128421;</span><span class="nas-label">' + esc(nasUsername) + '</span>';
      locs.appendChild(btn);
    }
    document.getElementById('nasConnectBtn').innerHTML = '<span class="sb-icon">&#9881;</span><span>NAS Settings</span>';
  } else {
    existing?.remove();
    document.getElementById('nasConnectBtn').innerHTML = '<span class="sb-icon">&#128268;</span><span>Connect NAS</span>';
  }
}

function openNasCredentials() {
  const changing = nasConnected && nasUsername;
  document.getElementById('nasCredTitle').textContent = changing ? '\uD83D\uDDAB Change NAS Password' : '\uD83D\uDDAB Connect to NAS';
  document.getElementById('nasCredDesc').textContent  = changing
    ? 'Enter a new password for your NAS account. Username is pre-filled.'
    : 'Enter your TrueNAS username (your first name) and password to link your NAS share.';
  document.getElementById('nasUsernameInput').value    = changing ? nasUsername : '';
  document.getElementById('nasUsernameLabel').textContent = changing ? 'Username (read-only)' : 'Username';
  document.getElementById('nasUsernameInput').readOnly = changing;
  document.getElementById('nasPasswordInput').value   = '';
  document.getElementById('nasCredError').hidden = true;
  document.getElementById('nasCredSaveBtn').textContent = changing ? 'Update Password' : 'Connect';
  document.getElementById('nasCredModal').removeAttribute('hidden');
  setTimeout(() => document.getElementById(changing ? 'nasPasswordInput' : 'nasUsernameInput').focus(), 50);
}

async function saveNasCredentials() {
  const username = document.getElementById('nasUsernameInput').value.trim();
  const password = document.getElementById('nasPasswordInput').value;
  const errEl    = document.getElementById('nasCredError');
  const btn      = document.getElementById('nasCredSaveBtn');
  if (!username || !password) { errEl.textContent = 'Username and password required'; errEl.hidden = false; return; }
  btn.textContent = 'Connecting\u2026'; btn.disabled = true;
  try {
    const r = await fetch('/nas/credentials', { method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }) });
    const d = await r.json();
    if (r.ok) { nasConnected = true; nasUsername = username; closeModal('nasCredModal'); updateNasSidebar(); openOrFocusWindow('nas', '', username); }
    else { errEl.textContent = d.error || 'Connection failed'; errEl.hidden = false; }
  } finally { btn.textContent = nasConnected ? 'Update Password' : 'Connect'; btn.disabled = false; }
}
document.getElementById('nasPasswordInput').addEventListener('keydown', e => { if (e.key === 'Enter') saveNasCredentials(); });

// ── NAS Copy modal ────────────────────────────────────────────────────────────
async function loadNasCopyDirs(path) {
  nasCopyDest = path;
  document.getElementById('nasCopyDirList').innerHTML = '<div class="dir-list-loading">Loading\u2026</div>';
  const r = await fetch('/nas/browse?path=' + encodeURIComponent(path));
  const d = await r.json();
  if (!r.ok) { document.getElementById('nasCopyDirList').innerHTML = '<div class="dir-list-loading" style="color:#dc2626">' + esc(d.error || 'Error') + '</div>'; return; }
  const dirs   = (d.items || []).filter(i => i.type === 'dir');
  const parent = path.split('/').filter(Boolean).slice(0, -1).join('/');
  let html = path ? `<div class="dir-item" onclick="loadNasCopyDirs('${esc(parent)}')">&#8617; Up</div>` : '';
  html += `<div class="dir-item selected-dest">&#128194; ${esc(path || 'NAS root')} <span style="font-size:.7rem">(copy here)</span></div>`;
  html += dirs.map(dir => { const dp = path ? path + '/' + dir.name : dir.name; return `<div class="dir-item" onclick="loadNasCopyDirs('${esc(dp)}')">&#128193; ${esc(dir.name)}</div>`; }).join('');
  document.getElementById('nasCopyDirList').innerHTML = html;
}
async function confirmNasCopy() {
  if (!nasCopySource) return;
  const btn = document.getElementById('nasCopyConfirmBtn');
  btn.textContent = 'Queuing\u2026'; btn.disabled = true;
  try {
    const r = await fetch('/nas/copy', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ local_path: nasCopySource, nas_path: nasCopyDest }) });
    const d = await r.json();
    if (r.ok && d.queued) { closeModal('nasCopyModal'); startTransferPolling(); }
    else alert('Error: ' + (d.error || 'Failed'));
  } finally { btn.textContent = 'Copy Here'; btn.disabled = false; }
}
async function createNasCopyFolder() {
  const input = document.getElementById('nasCopyNewFolder');
  const name  = input.value.trim();
  if (!name || /["\\\/\x00]/.test(name)) { alert('Invalid folder name'); return; }
  const fullPath = nasCopyDest ? nasCopyDest + '/' + name : name;
  const r = await fetch('/nas/mkdir', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: fullPath }) });
  const d = await r.json();
  if (d.ok) { input.value = ''; loadNasCopyDirs(fullPath); }
  else alert('Error: ' + (d.error || 'Failed'));
}

// ── Transfers panel ───────────────────────────────────────────────────────────
let transferPollTimer = null;
function startTransferPolling() { document.getElementById('transfersPanel').removeAttribute('hidden'); pollTransfers(); }
function dismissTransfers() { document.getElementById('transfersPanel').setAttribute('hidden', ''); if (transferPollTimer) { clearTimeout(transferPollTimer); transferPollTimer = null; } }
async function pollTransfers() {
  transferPollTimer = null;
  try {
    const r = await fetch('/nas/transfers');
    if (!r.ok) return;
    const d = await r.json();
    renderTransfers(d.transfers || []);
    if ((d.transfers || []).some(t => t.status === 'queued')) transferPollTimer = setTimeout(pollTransfers, 3000);
    else { for (const [id, ws] of windows) { if (ws.type === 'nas') loadWindow(id, ws.path); } }
  } catch { transferPollTimer = setTimeout(pollTransfers, 5000); }
}
function renderTransfers(transfers) {
  if (!transfers.length) { document.getElementById('transfersPanel').setAttribute('hidden', ''); return; }
  const html = transfers.map(t => {
    const icon = t.status === 'done' ? '&#10003;' : t.status === 'failed' ? '&#10007;' : '<span class="spinner">&#8987;</span>';
    const dest = t.nas_path ? t.nas_path + '/' + t.nas_filename : t.nas_filename;
    const sub  = t.status === 'failed'
      ? `<div class="transfer-sub error">${esc(t.error || 'Failed')}</div>`
      : t.status === 'done' ? `<div class="transfer-sub">\u2192 ${esc(dest || '')}</div>`
      : '<div class="transfer-sub">Copying\u2026</div>';
    return `<div class="transfer-item"><div class="transfer-icon">${icon}</div><div class="transfer-info"><div class="transfer-name">${esc(t.filename)}</div>${sub}</div></div>`;
  }).join('');
  document.getElementById('transfersList').innerHTML = html;
}

// ── Init ─────────────────────────────────────────────────────────────────────
openWindow('local', '', 'Home');
