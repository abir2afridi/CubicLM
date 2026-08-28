import 'package:flutter/material.dart';

class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final Locale locale;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    required this.locale,
  });

  static const List<AppLanguage> supported = [
    AppLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      flag: '🇺🇸',
      locale: Locale('en'),
    ),
    AppLanguage(
      code: 'bn',
      name: 'Bangla',
      nativeName: 'বাংলা',
      flag: '🇧🇩',
      locale: Locale('bn'),
    ),
    AppLanguage(
      code: 'hi',
      name: 'Hindi',
      nativeName: 'हिन्दी',
      flag: '🇮🇳',
      locale: Locale('hi'),
    ),
    AppLanguage(
      code: 'ar',
      name: 'Arabic',
      nativeName: 'العربية',
      flag: '🇸🇦',
      locale: Locale('ar'),
    ),
    AppLanguage(
      code: 'zh',
      name: 'Chinese',
      nativeName: '中文',
      flag: '🇨🇳',
      locale: Locale('zh'),
    ),
    AppLanguage(
      code: 'es',
      name: 'Spanish',
      nativeName: 'Español',
      flag: '🇪🇸',
      locale: Locale('es'),
    ),
    AppLanguage(
      code: 'fr',
      name: 'French',
      nativeName: 'Français',
      flag: '🇫🇷',
      locale: Locale('fr'),
    ),
    AppLanguage(
      code: 'ja',
      name: 'Japanese',
      nativeName: '日本語',
      flag: '🇯🇵',
      locale: Locale('ja'),
    ),
    AppLanguage(
      code: 'ko',
      name: 'Korean',
      nativeName: '한국어',
      flag: '🇰🇷',
      locale: Locale('ko'),
    ),
    AppLanguage(
      code: 'pt',
      name: 'Portuguese',
      nativeName: 'Português',
      flag: '🇧🇷',
      locale: Locale('pt'),
    ),
    AppLanguage(
      code: 'de',
      name: 'German',
      nativeName: 'Deutsch',
      flag: '🇩🇪',
      locale: Locale('de'),
    ),
    AppLanguage(
      code: 'tr',
      name: 'Turkish',
      nativeName: 'Türkçe',
      flag: '🇹🇷',
      locale: Locale('tr'),
    ),
    AppLanguage(
      code: 'id',
      name: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
      flag: '🇮🇩',
      locale: Locale('id'),
    ),
    AppLanguage(
      code: 'ru',
      name: 'Russian',
      nativeName: 'Русский',
      flag: '🇷🇺',
      locale: Locale('ru'),
    ),
    AppLanguage(
      code: 'ur',
      name: 'Urdu',
      nativeName: 'اردو',
      flag: '🇵🇰',
      locale: Locale('ur'),
    ),
  ];

  static AppLanguage fromCode(String code) {
    return supported.firstWhere(
      (l) => l.code == code,
      orElse: () => supported.first,
    );
  }

  static Locale localeFromCode(String code) => fromCode(code).locale;
}
