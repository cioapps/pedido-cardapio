// Publica o cardápio web no Cloudflare Pages (projeto define-cardapio).
// Carrega CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID do .env da raiz e roda o build + deploy.
// Uso: npm run deploy:web
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

if (existsSync('.env')) {
  for (const linha of readFileSync('.env', 'utf8').split(/\r?\n/)) {
    const m = linha.match(/^(\w+)=(.*)$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2];
  }
}
for (const nome of ['CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID']) {
  if (!process.env[nome]) {
    console.error(`Falta ${nome} no .env da raiz`);
    process.exit(1);
  }
}

const r = spawnSync('npm', ['run', 'deploy', '-w', '@cardapio/web'], { stdio: 'inherit', shell: true });
process.exit(r.status ?? 1);
