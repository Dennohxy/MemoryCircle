import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'album_page_view.dart';
import 'authed_image.dart';

/// Renders one themed yearbook page (layout schema_version 2). Each page's
/// layout_json carries its own theme tokens, so this renderer is stateless:
/// colors, typography preset, header, and footer all come from the page.
///
/// Templates: graduation_cover, official_message, graduate_profile_single,
/// graduate_profile_pair, photo_mosaic, dedication_grid,
/// typed_signature_grid, acknowledgements, graduation_back_cover.
class YearbookPageView extends StatelessWidget {
  const YearbookPageView({
    super.key,
    required this.api,
    required this.page,
    this.showPageNumber = true,
  });

  final ApiClient api;
  final AlbumPage page;
  final bool showPageNumber;

  @override
  Widget build(BuildContext context) {
    final layout = page.layout;
    final theme = _YearbookTheme.fromTokens(
        layout['theme'] as Map<String, dynamic>? ?? const {});
    final template = layout['template'] as String? ?? '';
    final isCover =
        template == 'graduation_cover' || template == 'graduation_back_cover';
    return Container(
      decoration: BoxDecoration(
        color: isCover ? theme.primary : theme.background,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
        child: Column(
          children: [
            if (!isCover) _header(context, theme, layout),
            Expanded(child: _body(context, theme, layout, template)),
            _footer(context, theme, layout, isCover),
          ],
        ),
      ),
    );
  }

  Widget _header(
      BuildContext context, _YearbookTheme theme, Map<String, dynamic> layout) {
    final title = (layout['header'] as Map<String, dynamic>?)?['section_title']
            as String? ??
        '';
    if (title.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.label.copyWith(letterSpacing: 2.5),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Container(width: 48, height: 2, color: theme.accent),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, _YearbookTheme theme,
      Map<String, dynamic> layout, bool isCover) {
    final footer = layout['footer'] as Map<String, dynamic>? ?? const {};
    final text = footer['text'] as String? ?? '';
    final showNumber =
        showPageNumber && footer['show_page_number'] != false && !isCover;
    if (text.isEmpty && !showNumber) return const SizedBox.shrink();
    final color = isCover ? theme.onPrimaryFaded : theme.faded;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (text.isNotEmpty)
            Flexible(
              child: Text(text,
                  style: theme.small.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          if (text.isNotEmpty && showNumber)
            Text('  ·  ', style: theme.small.copyWith(color: color)),
          if (showNumber)
            Text('${page.pageNumber}',
                style: theme.small.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, _YearbookTheme theme,
      Map<String, dynamic> layout, String template) {
    switch (template) {
      case 'graduation_cover':
        return _Cover(api: api, theme: theme, layout: layout);
      case 'graduation_back_cover':
        return _BackCover(api: api, theme: theme, layout: layout);
      case 'official_message':
        return _OfficialMessage(theme: theme, layout: layout);
      case 'graduate_profile_single':
      case 'graduate_profile_pair':
        return _Profiles(api: api, theme: theme, layout: layout);
      case 'photo_mosaic':
        return MosaicRowsView(
            api: api, rows: layout['rows'] as List<dynamic>? ?? const []);
      case 'dedication_grid':
        return _Dedications(theme: theme, layout: layout);
      case 'typed_signature_grid':
        return _Signatures(theme: theme, layout: layout);
      case 'acknowledgements':
        return _Acknowledgements(theme: theme, layout: layout);
      default:
        return Center(
          child: Text('This page needs a newer app version.',
              style: theme.body.copyWith(color: theme.faded)),
        );
    }
  }
}

/// Parsed theme tokens with safe fallbacks and the typography preset applied.
class _YearbookTheme {
  const _YearbookTheme({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.text,
    required this.background,
    required this.serif,
  });

  factory _YearbookTheme.fromTokens(Map<String, dynamic> tokens) {
    final colors = tokens['colors'] as Map<String, dynamic>? ?? const {};
    Color parse(String key, int fallback) {
      final value = colors[key] as String? ?? '';
      if (value.length == 7 && value.startsWith('#')) {
        final parsed = int.tryParse(value.substring(1), radix: 16);
        if (parsed != null) return Color(0xFF000000 | parsed);
      }
      return Color(fallback);
    }

    final typography =
        tokens['typography'] as Map<String, dynamic>? ?? const {};
    return _YearbookTheme(
      primary: parse('primary', 0xFF123A63),
      secondary: parse('secondary', 0xFFE8EEF3),
      accent: parse('accent', 0xFFC9A227),
      text: parse('text', 0xFF17202A),
      background: parse('background', 0xFFFFFFFF),
      serif: typography['preset'] != 'modern_sans',
    );
  }

  final Color primary;
  final Color secondary;
  final Color accent;
  final Color text;
  final Color background;
  final bool serif;

  Color get faded => text.withValues(alpha: 0.55);
  Color get onPrimary => Colors.white;
  Color get onPrimaryFaded => Colors.white.withValues(alpha: 0.7);

  String? get _family => serif ? 'Georgia' : null;
  List<String> get _fallback => serif
      ? const ['Times New Roman', 'serif']
      : const ['Arial', 'sans-serif'];

  TextStyle _style(double size,
          {FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? text,
        fontFamily: _family,
        fontFamilyFallback: _fallback,
        height: 1.35,
      );

  TextStyle get display => _style(30, weight: FontWeight.w700);
  TextStyle get headline => _style(20, weight: FontWeight.w600);
  TextStyle get title => _style(16, weight: FontWeight.w600);
  TextStyle get body => _style(14);
  TextStyle get small => _style(11.5);
  TextStyle get label => _style(11, weight: FontWeight.w600, color: accent);
}

class _Cover extends StatelessWidget {
  const _Cover({required this.api, required this.theme, required this.layout});

  final ApiClient api;
  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final logoUrl = layout['logo_url'] as String? ?? '';
    final university = layout['university'] as String? ?? '';
    final faculty = layout['faculty'] as String? ?? '';
    final cohort = layout['cohort'] as String? ?? '';
    final date = layout['graduation_date'] as String? ?? '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (logoUrl.isNotEmpty)
          SizedBox(
            width: 96,
            height: 96,
            child: AuthedImage(api: api, path: logoUrl, fit: BoxFit.contain),
          ),
        const SizedBox(height: 22),
        if (university.isNotEmpty)
          Text(university.toUpperCase(),
              style: theme.small
                  .copyWith(color: theme.onPrimaryFaded, letterSpacing: 3),
              textAlign: TextAlign.center),
        if (faculty.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(faculty,
              style: theme.small.copyWith(color: theme.onPrimaryFaded),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 14),
        Text(layout['title'] as String? ?? '',
            style: theme.display.copyWith(color: theme.onPrimary),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 14),
        Container(width: 64, height: 2, color: theme.accent),
        if (cohort.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(cohort,
              style: theme.title.copyWith(color: theme.onPrimary),
              textAlign: TextAlign.center),
        ],
        if (date.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(date,
              style: theme.small.copyWith(color: theme.onPrimaryFaded),
              textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _BackCover extends StatelessWidget {
  const _BackCover(
      {required this.api, required this.theme, required this.layout});

  final ApiClient api;
  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final logoUrl = layout['logo_url'] as String? ?? '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (logoUrl.isNotEmpty)
          SizedBox(
            width: 64,
            height: 64,
            child: AuthedImage(api: api, path: logoUrl, fit: BoxFit.contain),
          ),
        const SizedBox(height: 18),
        Text(layout['cohort'] as String? ?? '',
            style: theme.title.copyWith(color: theme.onPrimary),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text('Made together on Omoide no Wa',
            style: theme.small.copyWith(color: theme.onPrimaryFaded),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class _OfficialMessage extends StatelessWidget {
  const _OfficialMessage({required this.theme, required this.layout});

  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final message = layout['message'] as Map<String, dynamic>? ?? const {};
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            if ((message['title'] as String? ?? '').isNotEmpty) ...[
              Text(message['title'] as String,
                  style: theme.headline, textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            Text(message['message'] as String? ?? '',
                style: theme.body, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            if ((message['author_name'] as String? ?? '').isNotEmpty)
              Text(message['author_name'] as String,
                  style: theme.title, textAlign: TextAlign.center),
            if ((message['author_role'] as String? ?? '').isNotEmpty)
              Text(message['author_role'] as String,
                  style: theme.small.copyWith(color: theme.faded),
                  textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Profiles extends StatelessWidget {
  const _Profiles(
      {required this.api, required this.theme, required this.layout});

  final ApiClient api;
  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final profiles = [
      for (final item in layout['profiles'] as List<dynamic>? ?? const [])
        item as Map<String, dynamic>,
    ];
    if (profiles.length == 1) {
      return _ProfileCard(
          api: api, theme: theme, profile: profiles.first, large: true);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < profiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          Expanded(
            child: _ProfileCard(
                api: api, theme: theme, profile: profiles[i], large: false),
          ),
        ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.api,
    required this.theme,
    required this.profile,
    required this.large,
  });

  final ApiClient api;
  final _YearbookTheme theme;
  final Map<String, dynamic> profile;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final photo = profile['photo'] as Map<String, dynamic>?;
    final quote = profile['quote'] as String? ?? '';
    final honours = profile['honours'] as String? ?? '';
    final plans = profile['future_plans'] as String? ?? '';
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.secondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo == null
                ? Center(
                    child: Icon(Icons.school_outlined,
                        size: large ? 64 : 44, color: theme.faded))
                : AuthedImage(
                    api: api,
                    path: photo['display_url'] as String? ?? '',
                    fit: BoxFit.cover,
                    cacheWidth: large ? 900 : 500,
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(profile['full_name'] as String? ?? '',
            style: large ? theme.headline : theme.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if ((profile['programme'] as String? ?? '').isNotEmpty)
          Text(profile['programme'] as String,
              style: theme.small.copyWith(color: theme.faded),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        if (honours.isNotEmpty)
          Text(honours,
              style: theme.small.copyWith(color: theme.accent),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        if (quote.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('“$quote”',
              style: theme.body.copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
              maxLines: large ? 3 : 2,
              overflow: TextOverflow.ellipsis),
        ],
        if (large && plans.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(plans,
              style: theme.small.copyWith(color: theme.faded),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

class _Dedications extends StatelessWidget {
  const _Dedications({required this.theme, required this.layout});

  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final dedications = [
      for (final item in layout['dedications'] as List<dynamic>? ?? const [])
        item as Map<String, dynamic>,
    ];
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final dedication in dedications)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(dedication['message'] as String? ?? '',
                        style: theme.body.copyWith(fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Text(
                      [
                        if ((dedication['from_name'] as String? ?? '')
                            .isNotEmpty)
                          '— ${dedication['from_name']}',
                        if ((dedication['recipient_label'] as String? ?? '')
                            .isNotEmpty)
                          'to ${dedication['recipient_label']}',
                      ].join('  '),
                      style: theme.small.copyWith(color: theme.faded),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Signatures extends StatelessWidget {
  const _Signatures({required this.theme, required this.layout});

  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  TextStyle _signatureStyle(String style) {
    switch (style) {
      case 'serif_caps':
        return TextStyle(
          fontSize: 15,
          letterSpacing: 2.5,
          fontWeight: FontWeight.w600,
          color: theme.text,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
        );
      case 'modern_sans':
        return TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: theme.text,
          fontFamilyFallback: const ['Arial', 'sans-serif'],
        );
      default: // clean_script
        return TextStyle(
          fontSize: 18,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          color: theme.text,
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['Times New Roman', 'serif'],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signatures = [
      for (final item in layout['signatures'] as List<dynamic>? ?? const [])
        item as Map<String, dynamic>,
    ];
    return Center(
      child: SingleChildScrollView(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 26,
          runSpacing: 22,
          children: [
            for (final signature in signatures)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(signature['text'] as String? ?? '',
                      style: _signatureStyle(
                          signature['style'] as String? ?? 'clean_script')),
                  const SizedBox(height: 3),
                  Container(
                      width: 72,
                      height: 1,
                      color: theme.accent.withValues(alpha: 0.6)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Acknowledgements extends StatelessWidget {
  const _Acknowledgements({required this.theme, required this.layout});

  final _YearbookTheme theme;
  final Map<String, dynamic> layout;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final item in layout['items'] as List<dynamic>? ?? const [])
        item as Map<String, dynamic>,
    ];
    return Center(
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final item in items) ...[
              Text(item['message'] as String? ?? '',
                  style: theme.body, textAlign: TextAlign.center),
              if ((item['from_name'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('— ${item['from_name']}',
                    style: theme.small.copyWith(color: theme.faded)),
              ],
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
