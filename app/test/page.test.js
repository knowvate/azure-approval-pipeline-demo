import { test } from 'node:test';
import assert from 'node:assert/strict';
import { escapeHtml, health, renderPage } from '../src/page.js';

test('health reports the environment and version', () => {
  assert.deepEqual(health({ environment: 'UAT', version: 'abc123' }), {
    status: 'ok',
    environment: 'UAT',
    version: 'abc123',
  });
});

test('health falls back to unknown rather than undefined', () => {
  assert.deepEqual(health({}), { status: 'ok', environment: 'unknown', version: 'unknown' });
});

test('page shows the environment badge and version', () => {
  const html = renderPage({ environment: 'Production', version: 'abc123', builtAt: '2026-11-08' });
  assert.match(html, /<span class="env">Production<\/span>/);
  assert.match(html, /abc123/);
});

test('page escapes values it did not generate', () => {
  const html = renderPage({ environment: '<script>', version: '"x"' });
  assert.ok(!html.includes('<script>'));
  assert.equal(escapeHtml(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
});
