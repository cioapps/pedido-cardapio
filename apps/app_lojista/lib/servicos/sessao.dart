import 'package:supabase_flutter/supabase_flutter.dart';

import 'gestao_servico.dart';
import 'notificacoes_servico.dart';
import 'pedidos_servico.dart';
import 'whatsapp_servico.dart';

/// Para tudo (realtime, alarme) e sai da conta
Future<void> sairDaConta() async {
  await NotificacoesServico.instancia.remover();
  await PedidosServico.instancia.encerrar();
  await WhatsappServico.instancia.encerrar();
  GestaoServico.instancia.limpar();
  await Supabase.instance.client.auth.signOut();
}
