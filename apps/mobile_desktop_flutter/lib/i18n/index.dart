import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import 'translations.dart';
import 'types.dart';

const languageStorageKey = 'omoidenowa-language';

class I18nController extends ChangeNotifier {
  I18nController();

  AppLanguage _language = AppLanguage.en;
  bool _ready = false;

  AppLanguage get language => _language;
  bool get ready => _ready;
  List<AppLanguage> get supportedLanguages => AppLanguage.values;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(languageStorageKey);
    _language = AppLanguage.isSupported(saved)
        ? AppLanguage.fromCode(saved)
        : _detectBrowserLanguage();
    _ready = true;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language && _ready) return;
    _language = language;
    _ready = true;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(languageStorageKey, language.code);
  }

  String t(String key, {Map<String, Object?> values = const {}}) {
    final localized = _read(translations[_language], key);
    final fallback = _read(translations[AppLanguage.en], key);
    var text = localized ?? fallback ?? '';
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return text;
  }

  AppLanguage _detectBrowserLanguage() {
    final locales = PlatformDispatcher.instance.locales;
    final hasJapanesePreference = locales.any(
      (locale) => locale.languageCode.toLowerCase().startsWith('ja'),
    );
    return hasJapanesePreference ? AppLanguage.ja : AppLanguage.en;
  }

  String? _read(TranslationMap? root, String key) {
    Object? value = root;
    for (final segment in key.split('.')) {
      if (value is! Map<String, Object> || !value.containsKey(segment)) {
        return null;
      }
      value = value[segment];
    }
    return value is String ? value : null;
  }
}

class I18nScope extends InheritedNotifier<I18nController> {
  const I18nScope({
    super.key,
    required I18nController controller,
    required super.child,
  }) : super(notifier: controller);

  static I18nController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(scope != null, 'No I18nScope found in context.');
    return scope!.notifier!;
  }
}

extension I18nContext on BuildContext {
  I18nController get i18n => I18nScope.of(this);

  String t(String key, {Map<String, Object?> values = const {}}) =>
      I18nScope.of(this).t(key, values: values);
}

extension LocalizedCircleRole on CircleRole {
  String localizedLabel(BuildContext context) => switch (this) {
        CircleRole.owner => context.t('roles.owner'),
        CircleRole.approver => context.t('roles.approver'),
        CircleRole.contributor => context.t('roles.contributor'),
        CircleRole.viewer => context.t('roles.viewer'),
      };

  String localizedDescription(BuildContext context) => switch (this) {
        CircleRole.owner => context.t('roles.ownerDescription'),
        CircleRole.approver => context.t('roles.approverDescription'),
        CircleRole.contributor => context.t('roles.contributorDescription'),
        CircleRole.viewer => context.t('roles.viewerDescription'),
      };
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final label = context.t('common.selectLanguage');
    return Semantics(
      label: label,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: i18n.language,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.language, size: 18),
          onChanged: (language) {
            if (language != null) i18n.setLanguage(language);
          },
          items: [
            for (final language in i18n.supportedLanguages)
              DropdownMenuItem(
                value: language,
                child: Text(
                    compact ? language.code.toUpperCase() : language.label),
              ),
          ],
        ),
      ),
    );
  }
}
