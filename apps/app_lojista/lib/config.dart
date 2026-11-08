/// Configuração vinda do build:
/// flutter run --dart-define-from-file=env.json
/// (veja env.example.json)
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const urlCardapio = String.fromEnvironment(
    'URL_CARDAPIO',
    defaultValue: 'https://define.ia.br',
  );

  /// WhatsApp do suporte/vendas (só dígitos, com DDD). Aparece na tela de assinatura bloqueada.
  static const whatsappSuporte = String.fromEnvironment('WHATSAPP_SUPORTE');

  static bool get configurado => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
