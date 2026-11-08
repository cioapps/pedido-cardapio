/// Período da aba Vendas (datas locais, dia inteiro de início a fim)
class Periodo {
  final DateTime inicio;
  final DateTime fim;

  /// Nome do atalho ("Este mês") ou null quando o lojista escolheu as datas
  final String? atalho;

  Periodo(DateTime inicio, DateTime fim, {this.atalho}) : inicio = _dia(inicio), fim = _dia(fim);

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime get hoje => _dia(DateTime.now());

  int get dias => fim.difference(inicio).inDays + 1;
  bool get umDia => dias == 1;

  /// Período anterior de mesmo tamanho (é o que o banco usa para comparar)
  Periodo get anterior => Periodo(inicio.subtract(Duration(days: dias)), inicio.subtract(const Duration(days: 1)));

  bool mesmoQue(Periodo o) => inicio == o.inicio && fim == o.fim;

  static List<Periodo> atalhos() {
    final h = hoje;
    final ontem = h.subtract(const Duration(days: 1));
    final inicioMes = DateTime(h.year, h.month, 1);
    final inicioMesPassado = DateTime(h.year, h.month - 1, 1);
    return [
      Periodo(h, h, atalho: 'Hoje'),
      Periodo(ontem, ontem, atalho: 'Ontem'),
      Periodo(h.subtract(const Duration(days: 6)), h, atalho: '7 dias'),
      Periodo(h.subtract(const Duration(days: 29)), h, atalho: '30 dias'),
      Periodo(inicioMes, h, atalho: 'Este mês'),
      Periodo(inicioMesPassado, inicioMes.subtract(const Duration(days: 1)), atalho: 'Mês passado'),
    ];
  }

  /// "Hoje, 8 de novembro" / "1 a 8 de novembro" / "28 de out. a 3 de nov." / "1 de dez. de 2025 a 8 de jan."
  String get titulo {
    final h = hoje;
    if (umDia) {
      final base = '${inicio.day} de ${meses[inicio.month - 1]}${inicio.year != h.year ? ' de ${inicio.year}' : ''}';
      if (inicio == h) return 'Hoje, $base';
      if (inicio == h.subtract(const Duration(days: 1))) return 'Ontem, $base';
      return base;
    }
    final ano = fim.year != h.year || inicio.year != fim.year;
    if (inicio.year == fim.year && inicio.month == fim.month) {
      return '${inicio.day} a ${fim.day} de ${meses[fim.month - 1]}${ano ? ' de ${fim.year}' : ''}';
    }
    String curta(DateTime d, bool comAno) => '${d.day} de ${mesesCurtos[d.month - 1]}${comAno ? ' de ${d.year}' : ''}';
    return '${curta(inicio, inicio.year != fim.year)} a ${curta(fim, ano)}';
  }

  String get subtitulo => atalho ?? '$dias dias';

  /// Texto curto para a comparação: "outubro (1 a 8)" / "ontem" / "24/10 a 31/10"
  String get rotuloAnterior {
    final a = anterior;
    if (atalho == 'Hoje') return 'ontem';
    if (atalho == 'Ontem') return 'anteontem';
    if (atalho == 'Este mês' || (a.inicio.day == 1 && a.inicio.month == a.fim.month)) {
      return '${meses[a.inicio.month - 1]} (${a.inicio.day} a ${a.fim.day})';
    }
    String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
    return a.umDia ? d(a.inicio) : '${d(a.inicio)} a ${d(a.fim)}';
  }
}

const meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];
const mesesCurtos = ['jan.', 'fev.', 'mar.', 'abr.', 'maio', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];
const diasSemanaCurtos = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

String dataCurta(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
