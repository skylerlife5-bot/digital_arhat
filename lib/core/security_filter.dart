class SecurityFilter {
  static final RegExp _digitRun = RegExp(r'\d(?:[\s\-()]*\d){6,}');

  static final RegExp _socialWords = RegExp(
    r'\b(fb|facebook|insta|instagram|ig|snapchat|sc|tiktok|tik\s*tok|follow|id\s*:?)\b|@',
    caseSensitive: false,
  );

  static final RegExp _contactWords = RegExp(
    r'\b(whatsapp|wa|number|contact|call|mail|email|direct|dm)\b',
    caseSensitive: false,
  );

  static final RegExp _whatsAppFuzzy = RegExp(
    r'w\W*h\W*a\W*t\W*s\W*a\W*p\W*p',
    caseSensitive: false,
  );

  static String maskAll(String text) {
    if (text.trim().isEmpty) return text;

    var output = text;

    output = output.replaceAllMapped(_digitRun, (_) => '[PROTECTED]');
    output = output.replaceAllMapped(_whatsAppFuzzy, (_) => '[PROTECTED]');
    output = output.replaceAllMapped(_socialWords, (_) => '[PROTECTED]');
    output = output.replaceAllMapped(_contactWords, (_) => '[PROTECTED]');

    return output;
  }
}
