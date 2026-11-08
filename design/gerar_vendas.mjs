// Rascunho de design da aba Vendas (OpenAI). Uso: node design/gerar_vendas.mjs
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const env = Object.fromEntries(readFileSync('.env', 'utf8').split(/\r?\n/).filter((l) => /^\w+=/.test(l))
  .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));

const estilo = `High-fidelity Android app UI screenshot, portrait, flat screen design (no device frame, no hands, no perspective).
Clean, modern, minimal style like premium delivery partner apps: light gray page background (#F7F7F8), white rounded cards
with soft 1px gray border, one brand color warm red-orange (#E5421E) used for the selected filter, highlights and chart bars,
green (#15803D) for positive growth. Inter-like sans-serif, big readable numbers, generous spacing, very simple for
non-technical snack bar owners. All text in Brazilian Portuguese. Bottom navigation with 5 items: Pedidos, Vendas (selected,
red-orange), Cardápio, Loja, Ajustes, simple outline icons.`;

const telas = {
  vendas_1_tela: `${estilo}
Screen "Vendas", top to bottom:
- Title "Vendas".
- A large tappable period selector card: calendar icon, text "1 a 8 de novembro" and small caption "Este mês", a chevron down on the right.
- Row of quick filter chips (horizontally scrollable): "Hoje", "Ontem", "7 dias", "Este mês" (selected, red-orange outline and light tint), "Mês passado".
- Big white card "Faturamento" with value "R$ 4.820,50" very large and below a green pill "↑ 12% vs. outubro (1 a 8)".
- Two side-by-side small cards: "Pedidos 96" and "Ticket médio R$ 50,21".
- Card "Vendas por dia" with a clean bar chart of 8 bars (days 1 to 8), one bar highlighted with tooltip "Sáb 7 · R$ 812,00".
- Card "Mais vendidos" list: 1 X-Bacon 54 un. R$ 1.512,00; 2 X-Tudo 38 un.; 3 Batata frita 31 un. (rank numbers in small circles).
Scrolled so the top of the screen is visible.`,
  vendas_2_periodo: `${estilo}
A bottom sheet (modal sheet sliding from the bottom, over a dimmed "Vendas" screen) titled "Escolher período":
- Grid of 6 rounded option buttons in 2 columns: "Hoje", "Ontem", "Últimos 7 dias", "Últimos 30 dias", "Este mês", "Mês passado".
- Divider text "ou escolha as datas".
- Two fields side by side: "De  01/10/2026" and "Até  31/10/2026" with calendar icons.
- A month calendar of "Outubro 2026" with arrows ‹ › to change month, days 1 to 31 with the full range 1–31 highlighted in light red-orange and the start/end days as solid red-orange circles.
- Big full-width red-orange button at the bottom "Ver vendas".`,
};

mkdirSync('design/propostas', { recursive: true });
await Promise.all(Object.entries(telas).map(async ([nome, prompt]) => {
  const r = await fetch('https://api.openai.com/v1/images/generations', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-image-2', prompt, size: '1024x1536', quality: 'medium', n: 1 }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${JSON.stringify(j.error ?? j)}`);
  writeFileSync(`design/propostas/${nome}.png`, Buffer.from(j.data[0].b64_json, 'base64'));
  console.log('ok', nome);
}));
