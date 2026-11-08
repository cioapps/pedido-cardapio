import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'config.dart';
import 'servicos/impressora_servico.dart';
import 'servicos/notificacoes_servico.dart';
import 'tema.dart';
import 'telas/tela_login.dart';
import 'telas/tela_inicio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.configurado) {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  }
  await ImpressoraServico.instancia.iniciar();
  await NotificacoesServico.instancia.iniciar();
  // celular/tablet fica no balcão: tela sempre ligada
  WakelockPlus.enable();
  runApp(const AppLojista());
}

class AppLojista extends StatelessWidget {
  const AppLojista({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardápio',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: criarTema(),
      home: Config.configurado ? const PortaoAutenticacao() : const _SemConfiguracao(),
    );
  }
}

/// Sem sessão: login. Com sessão: carrega a loja (ou cria) e abre o app.
class PortaoAutenticacao extends StatelessWidget {
  const PortaoAutenticacao({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final sessao = auth.currentSession;
        if (sessao == null) return const TelaLogin();
        return const TelaInicio();
      },
    );
  }
}

class _SemConfiguracao extends StatelessWidget {
  const _SemConfiguracao();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'App sem configuração.\nRode com: flutter run --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
