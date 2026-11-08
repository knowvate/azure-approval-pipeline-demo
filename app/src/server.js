import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { health, renderPage } from './page.js';

// build-info.json is written by scripts/build.js. The version travels inside
// the artifact, so every environment reports the commit it is really running.
function loadBuildInfo() {
  try {
    return JSON.parse(readFileSync(new URL('../build-info.json', import.meta.url), 'utf8'));
  } catch {
    return { version: 'local', builtAt: 'not built' };
  }
}

const build = loadBuildInfo();
// APP_ENVIRONMENT is an app setting set by Terraform per environment
// (infra/envs/*.tfvars): the one thing that differs between them.
const environment = process.env.APP_ENVIRONMENT;

const server = createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(health({ environment, version: build.version })));
    return;
  }
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(renderPage({ environment, version: build.version, builtAt: build.builtAt }));
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('Not found');
});

const port = Number(process.env.PORT) || 8080;
server.listen(port, () => console.log(`Listening on ${port} (${environment || 'no environment set'})`));
