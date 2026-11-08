import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final _hora = DateFormat('HH:mm');
final _dataHora = DateFormat('dd/MM/yyyy HH:mm');

String formatarMoeda(num? valor) => _moeda.format(valor ?? 0);
String formatarHora(DateTime d) => _hora.format(d.toLocal());
String formatarDataHora(DateTime d) => _dataHora.format(d.toLocal());

String formatarTelefone(String tel) {
  var d = tel.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && (d.length == 12 || d.length == 13)) d = d.substring(2);
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return tel;
}

/// Impressoras térmicas baratas não lidam bem com acento: imprime sem.
String semAcentos(String texto) {
  const de = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÇçÑñ';
  const para = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn';
  final buffer = StringBuffer();
  for (final c in texto.split('')) {
    final i = de.indexOf(c);
    if (i >= 0) {
      buffer.write(para[i]);
    } else if (c.codeUnitAt(0) < 128) {
      buffer.write(c);
    } else if (c == '–' || c == '—') {
      buffer.write('-');
    }
  }
  return buffer.toString();
}

const nomesPagamento = {
  'dinheiro': 'Dinheiro',
  'cartao': 'Cartão (maquininha)',
  'pix': 'Pix na entrega',
};

const nomesStatus = {
  'novo': 'Novo',
  'aceito': 'Aceito',
  'em_preparo': 'Em preparo',
  'saiu_entrega': 'Saiu p/ entrega',
  'entregue': 'Entregue',
  'cancelado': 'Cancelado',
};

/// Aceita "12,50", "12.50" ou "1.234,50". Inválido vira 0.
double lerNumero(String texto) {
  var t = texto.trim().replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t) ?? 0;
}

/// 12.5 -> "12,50" (para preencher campos de preço)
String numeroParaCampo(num? valor) => (valor ?? 0).toStringAsFixed(2).replaceAll('.', ',');

/// "Lanche do Zé" -> "lanche-do-ze" (link do cardápio)
String gerarSlug(String texto) {
  const de = 'àáâãäåèéêëìíîïòóôõöùúûüçñ';
  const para = 'aaaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final c in texto.toLowerCase().split('')) {
    final i = de.indexOf(c);
    buffer.write(i >= 0 ? para[i] : c);
  }
  var s = buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 60) s = s.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
  return s;
}

String apenasDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

/// Traduz os erros mais comuns do Supabase para o lojista
String mensagemErro(Object e) {
  final texto = switch (e) {
    AuthException(:final message) => message,
    PostgrestException(:final message) => message,
    StorageException(:final message) => message,
    _ => '$e',
  };
  if (texto.contains('Invalid login credentials')) return 'E-mail ou senha incorretos.';
  if (texto.contains('User already registered')) return 'Este e-mail já tem conta. Use "Entrar".';
  if (texto.contains('Password should be')) return 'A senha precisa ter pelo menos 6 caracteres.';
  if (texto.contains('Email not confirmed')) return 'Confirme seu e-mail antes de entrar.';
  if (texto.contains('valid email') || texto.contains('invalid format')) return 'E-mail inválido.';
  if (texto.contains('slug_empresa_nao_reservado')) return 'Esse link é reservado. Escolha outro.';
  if (texto.contains('SocketException') || texto.contains('Failed host lookup') || texto.contains('ClientException')) {
    return 'Sem conexão. Verifique a internet.';
  }
  return texto.replaceFirst('Exception: ', '');
}
