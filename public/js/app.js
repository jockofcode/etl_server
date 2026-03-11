import { isLoggedIn } from './api.js';
import { on, go, init } from './router.js';
import { mount as mountLogin }      from './pages/login.js';
import { mount as mountFlows }      from './pages/flows.js';
import { mount as mountFlowDetail } from './pages/flow-detail.js';
import { mount as mountAccount }    from './pages/account.js';
import { mount as mountAdmin }      from './pages/admin.js';

const app = document.getElementById('app');

on('/login', () => {
  // If already logged in with no pending redirect, skip the login page.
  // If there's a ?redirect= param, show the form anyway so the user
  // re-authenticates and gets a fresh session cookie for the subdomain.
  const hasRedirect = new URLSearchParams(window.location.search).has('redirect');
  if (isLoggedIn() && !hasRedirect) { go('/flows'); return; }
  mountLogin(app);
});

on('/flows', () => {
  if (!isLoggedIn()) { go('/login'); return; }
  mountFlows(app);
});

on('/flows/:id', ({ id }) => {
  if (!isLoggedIn()) { go('/login'); return; }
  mountFlowDetail(app, id);
});

on('/account', () => {
  if (!isLoggedIn()) { go('/login'); return; }
  mountAccount(app);
});

on('/admin', () => {
  if (!isLoggedIn()) { go('/login'); return; }
  mountAdmin(app);
});

init();

