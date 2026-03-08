// Hash-based SPA router
const routes = new Map();

function matchRoute(pattern, path) {
  const pp = pattern.split('/').filter(Boolean);
  const hp = path.split('/').filter(Boolean);
  if (pp.length !== hp.length) return null;
  const params = {};
  for (let i = 0; i < pp.length; i++) {
    if (pp[i].startsWith(':')) {
      params[pp[i].slice(1)] = decodeURIComponent(hp[i]);
    } else if (pp[i] !== hp[i]) {
      return null;
    }
  }
  return params;
}

function handle() {
  const hash = window.location.hash.slice(1) || '/login';
  for (const [pattern, handler] of routes) {
    const params = matchRoute(pattern, hash);
    if (params !== null) {
      handler(params);
      return;
    }
  }
  go('/login');
}

export function on(pattern, handler) {
  routes.set(pattern, handler);
}

export function go(path) {
  window.location.hash = '#' + path;
}

export function init() {
  window.addEventListener('hashchange', handle);
  handle();
}

