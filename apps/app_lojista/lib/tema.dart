import 'package:flutter/material.dart';

/// Cores do app. Fundo neutro (claro e limpo), vermelho de comida como cor
/// principal e verde só para ações "positivas" (aceitar, aberta, à venda).
abstract final class Cores {
  static const primaria = Color(0xFFE5421E); // laranja-avermelhado (ações principais)
  static const primariaClara = Color(0xFFFFF1EC);
  static const primariaBorda = Color(0xFFFBC4B4);
  static const sucesso = Color(0xFF15803D); // verde aceitar/aberta
  static const sucessoClaro = Color(0xFFDCFCE7);
  static const alerta = Color(0xFFB45309); // âmbar (texto)
  static const alertaClaro = Color(0xFFFEF3C7);
  static const fundo = Color(0xFFF7F7F8);
  static const superficie = Colors.white;
  static const borda = Color(0xFFE6E6EA);
  static const texto = Color(0xFF16161A);
  static const textoSuave = Color(0xFF5B5B66); // contraste 6:1 no branco
}

/// Espaçamentos (múltiplos de 4)
abstract final class Esp {
  static const p = 8.0;
  static const m = 16.0;
  static const g = 24.0;
}

ThemeData criarTema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.primaria,
    brightness: Brightness.light,
  ).copyWith(
    primary: Cores.primaria,
    onPrimary: Colors.white,
    primaryContainer: Cores.primariaClara,
    onPrimaryContainer: const Color(0xFF9A2A0E),
    secondary: Cores.sucesso,
    onSecondary: Colors.white,
    surface: Cores.superficie,
    onSurface: Cores.texto,
    onSurfaceVariant: Cores.textoSuave,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFFAFAF9),
    surfaceContainer: const Color(0xFFF5F5F4),
    surfaceContainerHigh: const Color(0xFFF0EFEE),
    surfaceContainerHighest: const Color(0xFFEAE8E6),
    outline: const Color(0xFF8A8580),
    outlineVariant: Cores.borda,
    error: const Color(0xFFB91C1C),
  );

  final arredondado = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const textoBotao = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  final base = ThemeData(colorScheme: esquema, useMaterial3: true, scaffoldBackgroundColor: Cores.fundo);
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700, color: Cores.texto),
      titleLarge: base.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700, color: Cores.texto),
      titleMedium: base.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600, color: Cores.texto),
      bodyLarge: base.textTheme.bodyLarge!.copyWith(fontSize: 16, color: Cores.texto),
      bodyMedium: base.textTheme.bodyMedium!.copyWith(fontSize: 15, color: Cores.texto),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Cores.texto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Cores.texto),
    ),
    cardTheme: CardThemeData(
      color: Cores.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Cores.borda),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: arredondado, textStyle: textoBotao),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: arredondado,
        textStyle: textoBotao,
        side: const BorderSide(color: Cores.borda, width: 1.5),
        foregroundColor: Cores.texto,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: textoBotao),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Cores.borda, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Cores.primaria, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Cores.sucesso : const Color(0xFFC9C5C1)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      shadowColor: Colors.black,
      elevation: 8,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 13,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Cores.primaria : Cores.textoSuave,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 28,
            color: s.contains(WidgetState.selected) ? Cores.primaria : Cores.textoSuave,
          )),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Cores.primaria,
      unselectedLabelColor: Cores.textoSuave,
      indicatorColor: Cores.primaria,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      labelPadding: EdgeInsets.symmetric(horizontal: 4),
      dividerColor: Cores.borda,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Cores.textoSuave,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Cores.texto),
      subtitleTextStyle: TextStyle(fontSize: 14, color: Cores.textoSuave),
    ),
    dividerTheme: const DividerThemeData(color: Cores.borda, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(color: Colors.white, surfaceTintColor: Colors.transparent),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: Cores.borda),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Cores.texto),
    ),
  );
}
