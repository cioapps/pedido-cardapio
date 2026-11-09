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
      ..._final(g),
    ];
    await _enviar(b);
  }

  Future<Generator> _gerador() async {
    final perfil = await CapabilityProfile.load();
    return Generator(config.papel58mm ? PaperSize.mm58 : PaperSize.mm80, perfil);
  }

  /// Fim do cupom. As portáteis de 58 mm não têm guilhotina: só avança o papel até a serrilha.
  /// (g.cut() já avança 5 linhas sozinho; somar feed + cut desperdiçava papel.)
  List<int> _final(Generator g) => config.papel58mm ? g.feed(2) : g.cut();

  /// Cupom pensado para o motoboy e a cozinha (pedido do 1º cliente real):
  /// endereço logo no topo, observação do cliente em destaque e troco já calculado.
  Future<List<int>> gerarCupom(Pedido p, String nomeEmpresa) async {
    final g = await _gerador();
    String t(String s) => semAcentos(s).trim();
    final colunas = config.papel58mm ? 32 : 48;
    final linha = g.text('-' * colunas);
    const centro = PosStyles(align: PosAlign.center);
    const negrito = PosStyles(bold: true);
    const titulo = PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
    const tituloCentro = PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2);
    const alto = PosStyles(bold: true, height: PosTextSize.size2);
    bool tem(String? v) => v != null && v.trim().isNotEmpty;

    final b = <int>[
      ...g.reset(),
      ...g.text(t(nomeEmpresa).toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...g.text('PEDIDO #${p.numeroPedido}', styles: tituloCentro),
      ...g.text('${formatarDataHora(p.criadoEm)}${p.origemPedido == 'whatsapp' ? ' - WhatsApp' : ''}', styles: centro),
      ...linha,

      // ---- ENTREGA (primeiro, para o motoboy) ----
      ...g.text('ENTREGA', styles: titulo),
      ...g.text(t('${p.logradouro}, ${p.numeroEndereco}'), styles: alto),
      if (tem(p.complemento)) ...g.text(t('Comp: ${p.complemento}'), styles: negrito),
      ...g.text(t('Bairro: ${p.nomeBairro}'), styles: negrito),
      if (tem(p.pontoReferencia)) ...g.text(t('Ref: ${p.pontoReferencia}')),
      ...g.text(t('Cliente: ${p.nomeCliente}'), styles: negrito),
      ...g.text('Tel: ${formatarTelefone(p.telefoneCliente)}'),
    ];

    // ---- OBSERVAÇÃO DO CLIENTE (simples, em negrito) ----
    if (tem(p.observacaoPedido)) {
      b.addAll(g.text(t('OBS: ${p.observacaoPedido}'), styles: negrito));
    }

    // ---- ITENS ----
    b.addAll([...linha, ...g.text('ITENS', styles: titulo)]);
    for (final item in p.itens) {
      b.addAll(g.row([
        PosColumn(text: t('${item.quantidade}x ${item.nomeProduto}'), width: 8, styles: negrito),
        PosColumn(text: formatarMoedaSimples(item.valorTotalItem), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]));
      for (final o in item.opcoes) {
        b.addAll(g.text(t('  + ${o.descricao}${o.nomeGrupo.isEmpty ? '' : ' (${o.nomeGrupo})'}')));
      }
      if (tem(item.observacaoItem)) {
        b.addAll(g.text(t('  OBS: ${item.observacaoItem}'), styles: negrito));
      }
    }

    // ---- VALORES ----
    b.addAll([
      ...linha,
      ..._linhaValor(g, 'Subtotal', p.subtotal),
      ..._linhaValor(g, 'Entrega', p.taxaEntrega),
      ...g.row([
        PosColumn(text: 'TOTAL', width: 5, styles: alto),
        PosColumn(text: formatarMoedaSimples(p.valorTotal), width: 7, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
      ]),
      ...linha,
    ]);

    // ---- PAGAMENTO (o que o motoboy precisa fazer) ----
    switch (p.formaPagamento) {
      case 'dinheiro':
        b.addAll(g.text('PAGAMENTO: DINHEIRO', styles: negrito));
        if (p.trocoPara != null && p.trocoPara! > p.valorTotal) {
          b.addAll([
            ..._linhaValor(g, 'Cliente paga com', p.trocoPara!),
            ...g.text('LEVAR DE TROCO:', styles: negrito),
            ...g.text(formatarMoedaSimples(p.trocoPara! - p.valorTotal), styles: tituloCentro),
          ]);
        } else {
          b.addAll(g.text('Sem troco', styles: negrito));
        }
      case 'cartao':
        b.addAll([
          ...g.text('PAGAMENTO: CARTAO', styles: negrito),
          ...g.text('LEVAR MAQUININHA', styles: tituloCentro),
        ]);
      default:
        b.addAll([
          ...g.text(t('PAGAMENTO: ${(nomesPagamento[p.formaPagamento] ?? p.formaPagamento).toUpperCase()}'), styles: negrito),
          ...g.text('Cobrar ${formatarMoedaSimples(p.valorTotal)} na entrega'),
        ]);
    }

    b.addAll([...linha, ...g.text('Pedido #${p.numeroPedido}', styles: centro), ..._final(g)]);
    return b;
  }

  List<int> _linhaValor(Generator g, String rotulo, double valor, {bool negrito = false}) => g.row([
        PosColumn(text: rotulo, width: 7, styles: PosStyles(bold: negrito)),
        PosColumn(
          text: formatarMoedaSimples(valor),
          width: 5,
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
