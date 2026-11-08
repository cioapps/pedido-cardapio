import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos/pedido.dart';
import '../util/formatar.dart';

enum TipoImpressora { nenhuma, bluetooth, rede }

enum ImpressaoAutomatica { desligada, aoChegar, aoAceitar }

/// Preferências de impressão salvas no aparelho
class ConfigImpressora {
  TipoImpressora tipo;
  String enderecoBluetooth; // MAC
  String nomeBluetooth;
  String ipRede;
  int portaRede;
  bool papel58mm;
  int vias;
  ImpressaoAutomatica automatica;

  ConfigImpressora({
    this.tipo = TipoImpressora.nenhuma,
    this.enderecoBluetooth = '',
    this.nomeBluetooth = '',
    this.ipRede = '',
    this.portaRede = 9100,
    this.papel58mm = true,
    this.vias = 1,
    this.automatica = ImpressaoAutomatica.aoAceitar,
  });

  static Future<ConfigImpressora> carregar() async {
    final p = await SharedPreferences.getInstance();
    return ConfigImpressora(
      tipo: TipoImpressora.values[p.getInt('imp_tipo') ?? 0],
      enderecoBluetooth: p.getString('imp_bt_mac') ?? '',
      nomeBluetooth: p.getString('imp_bt_nome') ?? '',
      ipRede: p.getString('imp_ip') ?? '',
      portaRede: p.getInt('imp_porta') ?? 9100,
      papel58mm: p.getBool('imp_58mm') ?? true,
      vias: p.getInt('imp_vias') ?? 1,
      automatica: ImpressaoAutomatica.values[p.getInt('imp_auto') ?? 2],
    );
  }

  Future<void> salvar() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('imp_tipo', tipo.index);
    await p.setString('imp_bt_mac', enderecoBluetooth);
    await p.setString('imp_bt_nome', nomeBluetooth);
    await p.setString('imp_ip', ipRede);
    await p.setInt('imp_porta', portaRede);
    await p.setBool('imp_58mm', papel58mm);
    await p.setInt('imp_vias', vias);
    await p.setInt('imp_auto', automatica.index);
  }
}

class ImpressoraServico {
  ImpressoraServico._();
  static final instancia = ImpressoraServico._();

  ConfigImpressora config = ConfigImpressora();

  Future<void> iniciar() async => config = await ConfigImpressora.carregar();

  bool get configurada =>
      (config.tipo == TipoImpressora.bluetooth && config.enderecoBluetooth.isNotEmpty) ||
      (config.tipo == TipoImpressora.rede && config.ipRede.isNotEmpty);

  /// Android 12+: sem a permissão "Dispositivos próximos" o plugin trava sem responder.
  /// Por isso pedimos aqui antes de qualquer chamada Bluetooth.
  Future<void> _garantirBluetooth() async {
    if (!Platform.isAndroid) return;
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    final conectar = r[Permission.bluetoothConnect];
    if (conectar != null && !conectar.isGranted) {
      if (conectar.isPermanentlyDenied) await openAppSettings();
      throw Exception('Permita "Dispositivos próximos" para o app imprimir pelo Bluetooth');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw Exception('Ligue o Bluetooth do celular');
  }

  Future<List<BluetoothInfo>> listarPareadas() async {
    await _garantirBluetooth();
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> imprimirPedido(Pedido pedido, String nomeEmpresa) async {
    final bytes = await gerarCupom(pedido, nomeEmpresa);
    final todas = <int>[];
    for (var i = 0; i < config.vias.clamp(1, 5); i++) {
      todas.addAll(bytes);
    }
    await _enviar(todas);
  }

  Future<void> imprimirTeste(String nomeEmpresa) async {
    final g = await _gerador();
    final b = <int>[
      ...g.reset(),
      ...g.text(semAcentos(nomeEmpresa), styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...g.text('Teste de impressao OK', styles: const PosStyles(align: PosAlign.center)),
      ...g.text(formatarDataHora(DateTime.now()), styles: const PosStyles(align: PosAlign.center)),
      // régua: deve caber numa linha só (32 colunas no 58 mm, 48 no 80 mm)
      ...g.text(config.papel58mm ? '1234567890' * 3 + '12' : '1234567890' * 4 + '12345678'),
      ...g.text('PEDIDO #123', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
      ...g.feed(3),
      ...g.cut(),
    ];
    await _enviar(b);
  }

  Future<Generator> _gerador() async {
    final perfil = await CapabilityProfile.load();
    return Generator(config.papel58mm ? PaperSize.mm58 : PaperSize.mm80, perfil);
  }

  /// Cupom da cozinha: número grande, itens em destaque, observações e entrega
  Future<List<int>> gerarCupom(Pedido p, String nomeEmpresa) async {
    final g = await _gerador();
    String t(String s) => semAcentos(s);
    const centro = PosStyles(align: PosAlign.center);
    const grande = PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
    const itemEstilo = PosStyles(bold: true, height: PosTextSize.size2);
    final linha = config.papel58mm ? '-' * 32 : '-' * 48;

    final b = <int>[
      ...g.reset(),
      ...g.text(t(nomeEmpresa), styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...g.text('PEDIDO #${p.numeroPedido}', styles: grande),
      ...g.text(formatarDataHora(p.criadoEm), styles: centro),
      ...g.text(linha),
    ];

    for (final item in p.itens) {
      b.addAll(g.text(t('${item.quantidade}x ${item.nomeProduto}'), styles: itemEstilo));
      for (final o in item.opcoes) {
        b.addAll(g.text(t('   ${o.nomeGrupo}: ${o.descricao}')));
      }
      if (item.observacaoItem != null && item.observacaoItem!.isNotEmpty) {
        b.addAll(g.text(t('   OBS: ${item.observacaoItem}'), styles: const PosStyles(bold: true)));
      }
      b.addAll(g.text(formatarMoedaSimples(item.valorTotalItem), styles: const PosStyles(align: PosAlign.right)));
    }

    if (p.observacaoPedido != null && p.observacaoPedido!.isNotEmpty) {
      b.addAll(g.text(linha));
      b.addAll(g.text(t('OBS DO PEDIDO: ${p.observacaoPedido}'), styles: const PosStyles(bold: true)));
    }

    b.addAll([
      ...g.text(linha),
      ...g.text(t('Cliente: ${p.nomeCliente}'), styles: const PosStyles(bold: true)),
      ...g.text('Tel: ${formatarTelefone(p.telefoneCliente)}'),
      ...g.text(t(p.enderecoCompleto)),
      ...g.text(t('Bairro: ${p.nomeBairro}'), styles: const PosStyles(bold: true)),
      if (p.pontoReferencia != null && p.pontoReferencia!.isNotEmpty) ...g.text(t('Ref: ${p.pontoReferencia}')),
      ...g.text(linha),
      ..._linhaValor(g, 'Subtotal', p.subtotal),
      ..._linhaValor(g, 'Entrega', p.taxaEntrega),
      ..._linhaValor(g, 'TOTAL', p.valorTotal, negrito: true),
      ...g.text(t('Pagamento: ${nomesPagamento[p.formaPagamento] ?? p.formaPagamento}'),
          styles: const PosStyles(bold: true)),
      if (p.trocoPara != null) ...[
        ...g.text('Troco para: ${formatarMoedaSimples(p.trocoPara!)}'),
        ...g.text('Levar troco: ${formatarMoedaSimples(p.trocoPara! - p.valorTotal)}',
            styles: const PosStyles(bold: true)),
      ],
      ...g.feed(3),
      ...g.cut(),
    ]);
    return b;
  }

  List<int> _linhaValor(Generator g, String rotulo, double valor, {bool negrito = false}) => g.row([
        PosColumn(text: rotulo, width: 6, styles: PosStyles(bold: negrito)),
        PosColumn(
          text: formatarMoedaSimples(valor),
          width: 6,
          styles: PosStyles(align: PosAlign.right, bold: negrito),
        ),
      ]);

  Future<void> _enviar(List<int> bytes) async {
    switch (config.tipo) {
      case TipoImpressora.bluetooth:
        if (config.enderecoBluetooth.isEmpty) throw Exception('Escolha a impressora Bluetooth');
        await _enviarBluetooth(bytes);
      case TipoImpressora.rede:
        if (config.ipRede.isEmpty) throw Exception('Informe o IP da impressora');
        final socket = await Socket.connect(config.ipRede, config.portaRede, timeout: const Duration(seconds: 5));
        socket.add(Uint8List.fromList(bytes));
        await socket.flush();
        await socket.close();
      case TipoImpressora.nenhuma:
        throw Exception('Nenhuma impressora configurada');
    }
  }
}

extension on ImpressoraServico {
  /// Impressoras portáteis desligam sozinhas para poupar bateria: a conexão antiga
  /// fica "morta". Tenta, reconecta e tenta de novo uma vez.
  Future<void> _enviarBluetooth(List<int> bytes) async {
    await _garantirBluetooth();
    for (var tentativa = 1; tentativa <= 2; tentativa++) {
      var conectado = await PrintBluetoothThermal.connectionStatus;
      if (!conectado) {
        conectado = await PrintBluetoothThermal.connect(macPrinterAddress: config.enderecoBluetooth)
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      }
      if (conectado && await PrintBluetoothThermal.writeBytes(bytes)) return;
      await PrintBluetoothThermal.disconnect;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('Não conectou na impressora ${config.nomeBluetooth}. Ela está ligada e com bateria?');
  }
}

/// "R$ 12,50" sem o espaço especial do intl (impressora não entende)
String formatarMoedaSimples(double v) => semAcentos(formatarMoeda(v).replaceAll(' ', ' '));
