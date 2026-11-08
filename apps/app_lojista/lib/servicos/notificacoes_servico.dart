import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canal com som de alarme. O nome tem que bater com CANAL_PEDIDOS em supabase/functions/_compartilhado/fcm.ts.
/// (Android não deixa mudar o som de um canal já criado: para trocar o som, crie um id novo.)
const canalPedidos = AndroidNotificationChannel(
  'pedidos_alarme_v1',
  'Pedidos novos',
  description: 'Toca um alarme quando chega pedido, mesmo com o app fechado',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('alerta_longo'),
  enableVibration: true,
  enableLights: true,
);

/// Push do Firebase. Se o projeto ainda não tem o google-services.json,
/// tudo aqui é ignorado e o app continua funcionando (só sem aviso com o app fechado).
class NotificacoesServico {
  NotificacoesServico._();
  static final instancia = NotificacoesServico._();

  bool disponivel = false;
  String? _token;

  /// Chamado no main(), antes do runApp
  Future<void> iniciar() async {
    try {
      await Firebase.initializeApp();
      disponivel = true;
    } catch (e) {
      debugPrint('Firebase não configurado (sem push): $e');
      return;
    }
    final local = FlutterLocalNotificationsPlugin();
    await local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalPedidos);
    // com o app aberto, quem avisa é o alarme da tela de pedidos (não duplica)
    FirebaseMessaging.onMessage.listen((_) {});
  }

  /// Depois do login com loja: pede permissão e registra este celular na loja
  Future<void> registrar() async {
    if (!disponivel) return;
    try {
      final fcm = FirebaseMessaging.instance;
      final permissao = await fcm.requestPermission();
      if (permissao.authorizationStatus == AuthorizationStatus.denied) return;
      // getToken/onTokenRefresh: token de registro clássico, aceito pelo envio HTTP v1 (fcm.ts)
      // ignore: deprecated_member_use
      _token = await fcm.getToken();
      if (_token != null) await _enviar(_token!);
      // ignore: deprecated_member_use
      fcm.onTokenRefresh.listen((novo) {
        _token = novo;
        _enviar(novo);
      });
    } catch (e) {
      debugPrint('Falha ao registrar push: $e');
    }
  }

  Future<void> _enviar(String token) =>
      Supabase.instance.client.rpc('registrar_dispositivo', params: {'p_token': token, 'p_plataforma': 'android'});

  /// Ao sair da conta: este celular para de receber avisos da loja
  Future<void> remover() async {
    if (!disponivel) return;
    try {
      // ignore: deprecated_member_use
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await Supabase.instance.client.rpc('remover_dispositivo', params: {'p_token': token});
      }
    } catch (_) {}
  }

  /// A permissão de notificação foi negada? (para mostrar aviso em Ajustes)
  Future<bool> permitido() async {
    if (!disponivel) return false;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }
}
