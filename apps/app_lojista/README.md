# App do lojista (Flutter)

Recebe os pedidos do cardápio online em tempo real e imprime na impressora térmica.

## Rodar

```bash
cp env.example.json env.json   # preencha SUPABASE_URL, SUPABASE_ANON_KEY e URL_CARDAPIO
flutter run --dart-define-from-file=env.json
```

## Gerar APK

```bash
flutter build apk --release --dart-define-from-file=env.json
```

## Estrutura

| Arquivo | O que faz |
|---|---|
| `lib/main.dart` | Inicializa Supabase, tela sempre ligada, login ou pedidos |
| `lib/servicos/pedidos_servico.dart` | Lista de pedidos, Realtime, alerta sonoro em loop, mudança de status, impressão automática |
| `lib/servicos/impressora_servico.dart` | Configuração da impressora (Bluetooth / rede), geração do cupom ESC/POS |
| `lib/telas/` | Login, pedidos por abas, detalhe do pedido, configurações |
| `assets/sons/alerta.wav` | Som de novo pedido |

## Impressora

- **Bluetooth:** pareie a impressora nas configurações do Android e escolha em Configurações → Impressora.
- **Rede/Wi-Fi:** informe o IP (porta padrão 9100).
- O cupom sai sem acentos de propósito: a maioria das térmicas baratas não imprime acentos corretamente.
