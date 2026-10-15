import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'common/services/language_service.dart';
import 'internal/internal_app.dart';

class OmneasApp extends StatelessWidget {
  const OmneasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService().localeNotifier,
      builder: (context, locale, child) {
        return MaterialApp(
          title: 'Omneas Posorder',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            primaryColor: const Color(0xFF2563EB),
            scaffoldBackgroundColor: const Color(0xFFF5F7FA),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
              surface: const Color(0xFFF5F7FA),
            ),
            cardTheme: CardTheme(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: Colors.white,
            ),
          ),
          home: InternalApp(),
        );
      },
    );
  }
}
