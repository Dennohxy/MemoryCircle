enum AppLanguage {
  en('en', 'English'),
  ja('ja', '日本語');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  static AppLanguage fromCode(String? code) {
    final normalized = code?.toLowerCase();
    return AppLanguage.values.firstWhere(
      (language) => language.code == normalized,
      orElse: () => AppLanguage.en,
    );
  }

  static bool isSupported(String? code) =>
      AppLanguage.values.any((language) => language.code == code);
}
