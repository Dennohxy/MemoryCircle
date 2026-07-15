import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memory_circle/api/api_client.dart';
import 'package:memory_circle/api/models.dart';
import 'package:memory_circle/widgets/album_page_view.dart';
import 'package:memory_circle/widgets/scrapbook_decor.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, height: 480, child: child),
          ),
        ),
      );

  testWidgets('scrapbook page renders photo prints without layout errors',
      (tester) async {
    final api = ApiClient();
    const page = AlbumPage(
      id: 7,
      pageNumber: 2,
      layout: {
        'template': 'two_photo_story',
        'memories': [
          {
            'caption': 'Beach day',
            'story_preview': 'Sun and sand.',
            'display_url': '',
            'thumbnail_url': '',
          },
          {
            'caption': 'Sunset',
            'display_url': '',
            'thumbnail_url': '',
          },
        ],
      },
    );

    await tester.pumpWidget(wrap(AlbumPageView(api: api, page: page)));
    await tester.pump();

    expect(find.byType(FramedPhoto), findsNWidgets(2));
    expect(find.text('Beach day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title page renders the dense scrapbook decor', (tester) async {
    final api = ApiClient();
    const page = AlbumPage(
      id: 3,
      pageNumber: 1,
      layout: {
        'template': 'event_title',
        'title': 'Family Highlights',
        'description': 'Our year together.',
      },
    );

    await tester.pumpWidget(wrap(AlbumPageView(api: api, page: page)));
    await tester.pump();

    expect(find.text('Family Highlights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schema v2 yearbook cover uses the themed renderer',
      (tester) async {
    final api = ApiClient();
    const page = AlbumPage(
      id: 21,
      pageNumber: 1,
      layout: {
        'schema_version': 2,
        'template': 'graduation_cover',
        'title': 'Engineering Graduation',
        'university': 'GRIPS',
        'faculty': 'Policy Studies',
        'cohort': 'Class of 2026',
        'graduation_date': 'July 2026',
        'theme': {
          'colors': {
            'primary': '#123A63',
            'secondary': '#E8EEF3',
            'accent': '#C9A227',
            'text': '#17202A',
            'background': '#FFFFFF',
          },
          'typography': {'preset': 'classic_serif'},
        },
        'footer': {'text': 'Memory Circle'},
      },
    );

    await tester.pumpWidget(wrap(AlbumPageView(api: api, page: page)));
    await tester.pump();

    expect(find.text('Engineering Graduation'), findsOneWidget);
    expect(find.text('GRIPS'), findsOneWidget);
    expect(find.text('Class of 2026'), findsOneWidget);
    expect(find.byType(FramedPhoto), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schema v2 graduate profile renders structured fields',
      (tester) async {
    final api = ApiClient();
    const page = AlbumPage(
      id: 22,
      pageNumber: 3,
      layout: {
        'schema_version': 2,
        'template': 'graduate_profile_single',
        'theme': {
          'colors': {
            'primary': '#123A63',
            'secondary': '#E8EEF3',
            'accent': '#C9A227',
            'text': '#17202A',
            'background': '#FFFFFF',
          },
        },
        'header': {'section_title': 'Class of 2026'},
        'footer': {'text': 'Memory Circle'},
        'profiles': [
          {
            'full_name': 'Amina Kamau',
            'programme': 'BSc Computer Science',
            'honours': 'First Class Honours',
            'quote': 'Build with care.',
            'future_plans': 'Graduate software engineer',
          }
        ],
      },
    );

    await tester.pumpWidget(wrap(AlbumPageView(api: api, page: page)));
    await tester.pump();

    expect(find.text('CLASS OF 2026'), findsOneWidget);
    expect(find.text('Amina Kamau'), findsOneWidget);
    expect(find.text('BSc Computer Science'), findsOneWidget);
    expect(find.text('First Class Honours'), findsOneWidget);
    expect(find.text('“Build with care.”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four photo grid lays out all prints', (tester) async {
    final api = ApiClient();
    final page = AlbumPage(
      id: 11,
      pageNumber: 4,
      layout: {
        'template': 'four_photo_grid',
        'memories': [
          for (var i = 0; i < 4; i++)
            {
              'caption': 'Photo $i',
              'display_url': '',
              'thumbnail_url': '',
            },
        ],
      },
    );

    await tester.pumpWidget(wrap(AlbumPageView(api: api, page: page)));
    await tester.pump();

    expect(find.byType(FramedPhoto), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
