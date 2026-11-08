/**
 * Regras puras da IA de pedidos (sem rede, sem banco): fáceis de testar.
 * - texto do cardápio para o prompt
 * - transcrição da conversa
 * - esquema JSON da resposta
 * - validação do que a IA devolveu contra o cardápio real
 */

// ---------- Cardápio (formato de obter_cardapio) ----------
export interface Opcao { id: number; nome_opcao: string; preco_adicional: number }
export interface Grupo {
  id: number;
  nome_grupo: string;
  minimo_selecao: number;
  maximo_selecao: number;
  opcoes: Opcao[];
}
export interface Produto {
  id: number;
  nome_produto: string;
  descricao_produto: string | null;
  preco_produto: number;
  grupos: Grupo[];
}
export interface Cardapio {
  empresa: { nome_empresa: string; pedido_minimo: number };
  bairros: { id: number; nome_bairro: string; taxa_entrega: number }[];
  categorias: { nome_categoria: string; produtos: Produto[] }[];
}

const reais = (v: number) => `R$ ${Number(v).toFixed(2).replace(".", ",")}`;

function regraGrupo(g: Grupo): string {
  if (g.minimo_selecao === 0) return `opcional, até ${g.maximo_selecao}`;
  if (g.minimo_selecao === g.maximo_selecao) return `obrigatório, escolher ${g.minimo_selecao}`;
  return `obrigatório, de ${g.minimo_selecao} a ${g.maximo_selecao}`;
}

/** Texto estável (mesma ordem sempre) para o cache do prompt funcionar */
export function textoCardapio(c: Cardapio): string {
  const linhas: string[] = [`LOJA: ${c.empresa.nome_empresa}`, "", "CARDÁPIO (use apenas estes IDs):"];
  for (const cat of c.categorias) {
    linhas.push(`\n## ${cat.nome_categoria}`);
    for (const p of cat.produtos) {
      linhas.push(
        `[produto ${p.id}] ${p.nome_produto} — ${reais(p.preco_produto)}` +
          (p.descricao_produto ? ` (${p.descricao_produto})` : ""),
      );
      for (const g of p.grupos) {
        const opcoes = g.opcoes
          .map((o) => `[opcao ${o.id}] ${o.nome_opcao}${Number(o.preco_adicional) > 0 ? ` +${reais(o.preco_adicional)}` : ""}`)
          .join("; ");
        linhas.push(`    grupo "${g.nome_grupo}" (${regraGrupo(g)}): ${opcoes}`);
      }
    }
  }
  linhas.push("", "BAIRROS ATENDIDOS (taxa de entrega):");
  for (const b of c.bairros) linhas.push(`[bairro ${b.id}] ${b.nome_bairro} — ${reais(b.taxa_entrega)}`);
  return linhas.join("\n");
}

// ---------- Conversa ----------
export interface MensagemConversa {
  enviada_pela_loja: boolean;
  tipo_mensagem: string;
  texto_mensagem: string | null;
  transcricao_audio: string | null;
  enviada_em: string;
}

export function textoConversa(mensagens: MensagemConversa[], fusoHorario = "America/Sao_Paulo"): string {
  const hora = new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: fusoHorario });
  return mensagens
    .map((m) => {
      const quem = m.enviada_pela_loja ? "LOJA" : "CLIENTE";
      let conteudo = m.texto_mensagem?.trim() ?? "";
      if (m.tipo_mensagem === "audio") {
        conteudo = m.transcricao_audio ? `(áudio) ${m.transcricao_audio}` : "(áudio sem transcrição)";
      } else if (!conteudo) {
        conteudo = `(${m.tipo_mensagem})`;
      }
      return `[${hora.format(new Date(m.enviada_em))}] ${quem}: ${conteudo}`;
    })
    .join("\n");
}

// ---------- Resposta da IA ----------
export interface ItemIa {
  id_produto: number;
  quantidade: number;
  observacao_item: string;
  opcoes: { id_opcao: number; quantidade: number }[];
}

export interface RespostaIa {
  e_pedido: boolean;
  pedido_fechado: boolean;
  resumo: string;
  pendencias: string[];
  itens: ItemIa[];
  nome_cliente: string | null;
  logradouro: string | null;
  numero_endereco: string | null;
  complemento: string | null;
  ponto_referencia: string | null;
  id_bairro_entrega: number | null;
  forma_pagamento: "dinheiro" | "cartao" | "pix" | null;
  troco_para: number | null;
  observacao_pedido: string | null;
}

const textoOuNulo = { type: ["string", "null"] };

/** JSON Schema da saída estruturada (output_config.format) */
export const esquemaResposta = {
  type: "object",
  additionalProperties: false,
  required: [
    "e_pedido", "pedido_fechado", "resumo", "pendencias", "itens", "nome_cliente", "logradouro",
    "numero_endereco", "complemento", "ponto_referencia", "id_bairro_entrega", "forma_pagamento",
    "troco_para", "observacao_pedido",
  ],
  properties: {
    e_pedido: { type: "boolean", description: "A conversa é um pedido de comida/entrega?" },
    pedido_fechado: {
      type: "boolean",
      description: "Cliente e loja já fecharam o pedido (cliente terminou de pedir e/ou a loja confirmou)?",
    },
    resumo: { type: "string", description: "Resumo curto do pedido em uma frase, para o lojista." },
    pendencias: {
      type: "array",
      items: { type: "string" },
      description: "O que ainda falta definir, em frases curtas. Ex.: 'Falta o bairro', 'X-Burger: falta escolher o pão'.",
    },
    itens: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id_produto", "quantidade", "observacao_item", "opcoes"],
        properties: {
          id_produto: { type: "integer" },
          quantidade: { type: "integer" },
          observacao_item: { type: "string", description: "Ex.: 'sem cebola'. Vazio se não houver." },
          opcoes: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["id_opcao", "quantidade"],
              properties: { id_opcao: { type: "integer" }, quantidade: { type: "integer" } },
            },
          },
        },
      },
    },
    nome_cliente: textoOuNulo,
    logradouro: textoOuNulo,
    numero_endereco: textoOuNulo,
    complemento: textoOuNulo,
    ponto_referencia: textoOuNulo,
    id_bairro_entrega: { type: ["integer", "null"] },
    forma_pagamento: { type: ["string", "null"], enum: ["dinheiro", "cartao", "pix", null] },
    troco_para: { type: ["number", "null"] },
    observacao_pedido: textoOuNulo,
  },
} as const;

export const INSTRUCOES_IA = `Você acompanha conversas de WhatsApp entre uma lanchonete (LOJA) e um CLIENTE e monta o pedido para o lojista revisar.

Regras:
- Use somente produtos, opções e bairros do cardápio abaixo, sempre pelos IDs entre colchetes. Nunca invente IDs.
- Associe o que o cliente escreveu ao item mais parecido do cardápio (ex.: "xbacon" = X-Bacon, "coca" = Refrigerante lata se for o único refrigerante). Se houver dúvida real entre dois itens, não escolha: coloque em pendencias.
- O que o cliente pedir e não existir no cardápio vai para pendencias (ex.: "Cliente pediu açaí, que não está no cardápio").
- Falas da LOJA valem como confirmação ou correção do pedido (ex.: "anotado, 2 x-bacon", "acabou o ovo").
- Considere mudanças de ideia: o estado final da conversa é o que vale.
- Em grupos obrigatórios, só preencha a opção se o cliente (ou a loja) disse qual é; caso contrário, registre a pendência.
- Endereço e nome: só preencha o que foi dito na conversa ou o que o cliente confirmou do endereço salvo. Não invente.
- Bairro: escolha o bairro atendido correspondente ao endereço; se o bairro não for atendido, deixe null e registre a pendência.
- Pagamento: dinheiro, cartao (débito/crédito/maquininha) ou pix. troco_para só quando o cliente disser "troco para X".
- pedido_fechado = true quando o cliente terminou de pedir (ex.: "só isso", "pode mandar") ou a loja confirmou o pedido.
- Se a conversa não é sobre fazer um pedido (dúvida, reclamação, conversa pessoal, fornecedor), responda e_pedido = false e itens vazio.
- Escreva resumo e pendencias em português, curtos e diretos.`;

// ---------- Validação contra o cardápio ----------
export interface ResultadoValidacao {
  itens: ItemIa[];
  pendencias: string[];
  valorEstimado: number;
  idBairro: number | null;
}

/** Remove IDs inválidos, corrige quantidades e confere grupos obrigatórios */
export function validarResposta(r: RespostaIa, c: Cardapio): ResultadoValidacao {
  const produtos = new Map<number, Produto>();
  for (const cat of c.categorias) for (const p of cat.produtos) produtos.set(p.id, p);
  const pendencias = [...(r.pendencias ?? [])];
  const itens: ItemIa[] = [];
  let valor = 0;

  for (const item of r.itens ?? []) {
    const produto = produtos.get(Number(item.id_produto));
    if (!produto) {
      pendencias.push("A IA citou um produto que não está no cardápio; confira a conversa.");
      continue;
    }
    const quantidade = Math.min(99, Math.max(1, Math.round(Number(item.quantidade) || 1)));
    const opcoes: ItemIa["opcoes"] = [];
    let precoUnit = Number(produto.preco_produto);
    const somaPorGrupo = new Map<number, number>();

    for (const o of item.opcoes ?? []) {
      const grupo = produto.grupos.find((g) => g.opcoes.some((x) => x.id === Number(o.id_opcao)));
      if (!grupo) continue; // opção que não pertence ao produto: ignora
      const opcao = grupo.opcoes.find((x) => x.id === Number(o.id_opcao))!;
      const qtd = Math.min(20, Math.max(1, Math.round(Number(o.quantidade) || 1)));
      opcoes.push({ id_opcao: opcao.id, quantidade: qtd });
      precoUnit += Number(opcao.preco_adicional) * qtd;
      somaPorGrupo.set(grupo.id, (somaPorGrupo.get(grupo.id) ?? 0) + qtd);
    }

    for (const g of produto.grupos) {
      const soma = somaPorGrupo.get(g.id) ?? 0;
      if (soma < g.minimo_selecao) {
        const texto = `${produto.nome_produto}: falta escolher "${g.nome_grupo}"`;
        if (!pendencias.some((p) => p.toLowerCase() === texto.toLowerCase())) pendencias.push(texto);
      }
      if (soma > g.maximo_selecao) {
        pendencias.push(`${produto.nome_produto}: mais opções do que o permitido em "${g.nome_grupo}"`);
      }
    }

    itens.push({ id_produto: produto.id, quantidade, observacao_item: (item.observacao_item ?? "").trim(), opcoes });
    valor += precoUnit * quantidade;
  }

  const bairro = c.bairros.find((b) => b.id === Number(r.id_bairro_entrega));
  if (bairro) valor += Number(bairro.taxa_entrega);

  if (r.e_pedido && itens.length > 0) {
    if (!r.nome_cliente) adicionarSeFaltar(pendencias, "nome", "Falta o nome do cliente");
    if (!r.logradouro || !r.numero_endereco) adicionarSeFaltar(pendencias, "endereço", "Falta o endereço completo");
    if (!bairro) adicionarSeFaltar(pendencias, "bairro", "Falta o bairro (ou não é atendido)");
    if (!r.forma_pagamento) adicionarSeFaltar(pendencias, "pagamento", "Falta a forma de pagamento");
  }

  return { itens, pendencias, valorEstimado: Math.round(valor * 100) / 100, idBairro: bairro?.id ?? null };
}

/** Evita repetir uma pendência que a IA já escreveu com outras palavras */
function adicionarSeFaltar(lista: string[], palavraChave: string, texto: string) {
  if (!lista.some((p) => p.toLowerCase().includes(palavraChave))) lista.push(texto);
}
