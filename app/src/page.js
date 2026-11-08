// Pure functions only, so the unit tests need no server.

// Colour per environment, so a screenshot shows at a glance which one you're on.
const ENV_COLOURS = {
  Development: '#2563eb',
  UAT: '#d97706',
  Production: '#16a34a',
};

export function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export function health({ environment, version }) {
  return { status: 'ok', environment: environment || 'unknown', version: version || 'unknown' };
}

export function renderPage({ environment, version, builtAt }) {
  const env = environment || 'unknown';
  const colour = ENV_COLOURS[env] || '#6b7280';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Approval pipeline demo - ${escapeHtml(env)}</title>
<style>
  body { margin: 0; font-family: system-ui, sans-serif; background: #f8fafc; color: #0f172a; }
  main { max-width: 40rem; margin: 15vh auto; padding: 2rem; background: #fff; border-radius: 12px; box-shadow: 0 1px 3px rgb(0 0 0 / .12); }
  .env { display: inline-block; padding: .25rem .75rem; border-radius: 999px; color: #fff; background: ${colour}; font-weight: 600; }
  code { background: #f1f5f9; padding: .1rem .35rem; border-radius: 4px; }
</style>
</head>
<body>
<main>
  <span class="env">${escapeHtml(env)}</span>
  <h1>Approval pipeline demo</h1>
  <p>Version <code>${escapeHtml(version || 'unknown')}</code>, built ${escapeHtml(builtAt || 'unknown')}.</p>
  <p>The same build artifact is promoted through Development, UAT and Production.</p>
</main>
</body>
</html>`;
}
