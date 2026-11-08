// Gera imagens de referência de design (OpenAI) para a tela de pedidos do app do lojista.
// Uso: node design/gerar_propostas.mjs   (lê OPENAI_API_KEY do .env da raiz)
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const env = Object.fromEntries(readFileSync('.env', 'utf8').split(/\r?\n/).filter((l) => /^\w+=/.test(l))
  .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));

const base = `High-fidelity mobile app UI screenshot, Android phone portrait, flat screen design (no hands, no device frame, no perspective).
App for a small Brazilian snack bar owner to receive delivery orders. All interface text in Brazilian Portuguese.
Screen content, top to bottom:
- Header with store name "Lanche do Zé" and a large clear status control "Loja aberta" with a toggle.
- Segmented tabs: "Novos 2", "Preparo 1", "Entrega", "Concluídos".
- Order card #12 "Maria" "há 3 min", items "2x X-Bacon", "1x Coca-Cola 2L", total "R$ 58,90", "Pix na entrega", a big primary button "Aceitar pedido".
- Order card #11 "João" "há 8 min", items "1x X-Tudo", "1x Batata frita", total "R$ 42,00", "Dinheiro · troco p/ 50", big button "Aceitar pedido".
- Bottom navigation with 4 icons and labels: "Pedidos", "Cardápio", "Loja", "Ajustes".
Very easy to understand for non-technical users: big readable text, generous spacing, clear hierarchy, few elements, high contrast, professional and polished like a top-tier commercial app.`;

const estilos = {
  '1_limpo_profissional': `Style: clean, modern, minimal like premium delivery partner apps. White background, soft gray separators,
rounded cards with subtle shadow, one strong brand color (warm red-orange) used only for primary actions and the active tab,
green for "Loja aberta". Inter-like sans-serif typography.`,
  '2_escuro_balcao': `Style: dark mode for a kitchen counter tablet. Near-black background, dark charcoal cards, very large bold numbers,
vivid yellow-amber accent for new orders and primary buttons, green status, excellent contrast, calm and focused.`,
  '3_amigavel_colorido': `Style: friendly and warm, playful but tidy. Cream background, cards with colored left accent bar per status
(red new, orange preparing, purple delivery), rounded chunky buttons, friendly food icons, rounded sans-serif typography.`,
};

mkdirSync('design/propostas', { recursive: true });
await Promise.all(Object.entries(estilos).map(async ([nome, estilo]) => {
  const r = await fetch('https://api.openai.com/v1/images/generations', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'gpt-image-2', prompt: `${base}\n${estilo}`, size: '1024x1536', quality: 'medium', n: 1 }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${JSON.stringify(j.error ?? j)}`);
  writeFileSync(`design/propostas/${nome}.png`, Buffer.from(j.data[0].b64_json, 'base64'));
  console.log('ok', nome);
}));
