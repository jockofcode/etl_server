import { login } from '../api.js';
import { go } from '../router.js';

export function mount(container) {
  container.innerHTML = `
    <div class="login-page">
      <div class="login-card">
        <h1 class="login-title">⚙ ETL Flow Editor</h1>
        <p class="login-subtitle">Sign in to manage your ETL flows</p>
        <form id="login-form" novalidate>
          <div class="form-group">
            <label class="form-label" for="email">Email</label>
            <input
              class="form-control" type="email" id="email" name="email"
              placeholder="you@example.com" required autocomplete="username"
            >
          </div>
          <div class="form-group">
            <label class="form-label" for="password">Password</label>
            <input
              class="form-control" type="password" id="password" name="password"
              placeholder="••••••••" required autocomplete="current-password"
            >
          </div>
          <div id="login-error" class="alert alert-error hidden"></div>
          <button type="submit" class="btn btn-primary btn-full" id="login-btn">
            Sign In
          </button>
        </form>
      </div>
    </div>
  `;

  const form     = container.querySelector('#login-form');
  const errorEl  = container.querySelector('#login-error');
  const btn      = container.querySelector('#login-btn');

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email    = form.email.value.trim();
    const password = form.password.value;

    btn.disabled    = true;
    btn.textContent = 'Signing in…';
    errorEl.classList.add('hidden');

    try {
      await login(email, password);
      const redirect = new URLSearchParams(window.location.search).get('redirect');
      if (redirect) {
        window.location.href = redirect;
      } else {
        go('/flows');
      }
    } catch (err) {
      errorEl.textContent = err.message;
      errorEl.classList.remove('hidden');
      btn.disabled    = false;
      btn.textContent = 'Sign In';
    }
  });
}

