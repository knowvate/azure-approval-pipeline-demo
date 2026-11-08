// Produces dist/: the exact files that get zipped and promoted through every
// environment. Built once per commit - UAT and Production never rebuild.
import { cpSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';

const dist = new URL('../dist/', import.meta.url);
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist);
cpSync(new URL('../src/', import.meta.url), new URL('src/', dist), { recursive: true });
cpSync(new URL('../package.json', import.meta.url), new URL('package.json', dist));
writeFileSync(
  new URL('build-info.json', dist),
  JSON.stringify({ version: process.env.BUILD_VERSION || 'local', builtAt: new Date().toISOString() }, null, 2),
);
console.log('Built dist/');
