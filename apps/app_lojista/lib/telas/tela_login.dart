import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/formatar.dart';

/// Entrar ou criar conta (sem confirmação de e-mail: já entra direto)
class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _cadastrar = false;
  bool _verSenha = false;
  bool _enviando = false;
  String? _erro;

  Future<void> _enviar() async {
    final email = _email.text.trim();
    final senha = _senha.text;
    if (!email.contains('@')) return setState(() => _erro = 'Informe um e-mail válido.');
    if (senha.length < 6) return setState(() => _erro = 'A senha precisa ter pelo menos 6 caracteres.');

    setState(() {
      _enviando = true;
      _erro = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_cadastrar) {
        final r = await auth.signUp(email: email, password: senha);
        // Se o projeto ainda exigir confirmação, não vem sessão
        if (r.session == null && mounted) {
          setState(() => _erro = 'Conta criada. Confirme pelo link enviado ao seu e-mail e depois entre.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: senha);
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErro(e));
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.storefront, size: 56, color: tema.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(_cadastrar ? 'Criar conta da loja' : 'Entrar na sua loja',
                        textAlign: TextAlign.center, style: tema.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      _cadastrar
                          ? 'Cadastre o cardápio, receba e imprima pedidos, tudo pelo celular.'
                          : 'Receba os pedidos e gerencie seu cardápio.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _senha,
                      obscureText: !_verSenha,
                      autofillHints: [_cadastrar ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _enviar(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        helperText: _cadastrar ? 'Mínimo de 6 caracteres' : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility),
                          tooltip: _verSenha ? 'Esconder senha' : 'Mostrar senha',
                          onPressed: () => setState(() => _verSenha = !_verSenha),
                        ),
                      ),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!, style: TextStyle(color: tema.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _enviando ? null : _enviar,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(_enviando ? 'Aguarde...' : (_cadastrar ? 'Criar conta' : 'Entrar')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _enviando
                          ? null
                          : () => setState(() {
                                _cadastrar = !_cadastrar;
                                _erro = null;
                              }),
                      child: Text(_cadastrar ? 'Já tenho conta: entrar' : 'Não tem conta? Criar agora'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
