import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/util/title_matcher.dart';

void main() {
  group('TitleMatcher - Roman numerals and canonicalization', () {
    test('converts roman numerals to digits', () {
      expect(TitleMatcher.convertRomanNumerals('Fantasy Vol X'), 'Fantasy Vol 10');
      expect(TitleMatcher.convertRomanNumerals('Part II'), 'Part 2');
      expect(TitleMatcher.convertRomanNumerals('Season IV'), 'Season 4');
      expect(TitleMatcher.convertRomanNumerals('Episode III'), 'Episode 3');
    });

    test('canonicalizes volume/part noise words', () {
      expect(TitleMatcher.canonicalize('Fantasy Vol. 10'), 'fantasy 10');
      expect(TitleMatcher.canonicalize('Fantasy Volume 10'), 'fantasy 10');
      expect(TitleMatcher.canonicalize('Fantasy - Vol 10'), 'fantasy 10');
      expect(TitleMatcher.canonicalize('Fantasy: Part 2'), 'fantasy 2');
      expect(TitleMatcher.canonicalize('Fantasy 10'), 'fantasy 10');
    });
  });

  group('TitleMatcher - isMatch scenarios', () {
    test('matches exact titles', () {
      expect(TitleMatcher.isMatch('Fantasy', 'Fantasy'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy Vol. 10', 'Fantasy Vol. 10'), isTrue);
    });

    test('matches "Fantasy Vol 10" with "Fantasy 10"', () {
      expect(TitleMatcher.isMatch('Fantasy Vol 10', 'Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy Vol. 10', 'Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy Volume X', 'Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy Vol X', 'Fantasy Vol 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy: Part 2', 'Fantasy 2'), isTrue);
    });

    test('matches minor typos with fuzzy matching', () {
      expect(TitleMatcher.isMatch('Fantay 10', 'Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantay Vol 10', 'Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Super Fantasy', 'Super Fantay'), isTrue);
    });

    test('matches titles with studio prefix/suffix', () {
      expect(TitleMatcher.isMatch('Fantasy Vol 10', 'Brazzers - Fantasy 10'), isTrue);
      expect(TitleMatcher.isMatch('Fantasy Vol 10', 'Fantasy 10 (2023)'), isTrue);
    });

    test('matches wanted title when provider has studio and performer info', () {
      expect(TitleMatcher.isMatch('In Loving Memory', 'Sweet Sinner - In Loving Memory - Maya Kendrick'), isTrue);
      expect(TitleMatcher.isMatch('In Loving Memory', 'SpeedPorn - In Loving Memory'), isTrue);
      expect(TitleMatcher.isMatch('In Loving Memory', 'Blacked: In Loving Memory (Kendra Lust)'), isTrue);
      expect(TitleMatcher.matchScore('In Loving Memory', 'SpeedPorn - In Loving Memory'), greaterThanOrEqualTo(0.90));
    });

    test('matches ampersand & and word synonyms', () {
      expect(TitleMatcher.isMatch('Friends & Family', 'Friends and Family'), isTrue);
      expect(TitleMatcher.isMatch('Friends and Family', 'Friends & Family'), isTrue);
      expect(TitleMatcher.isMatch('Fast & Furious', 'Fast and Furious'), isTrue);
      expect(TitleMatcher.matchScore('Friends & Family', 'Friends and Family'), equals(1.0));
      expect(TitleMatcher.matchScore('Friends & Family', 'Himeros - Friends and Family'), greaterThanOrEqualTo(0.95));
    });

    test('does NOT match different volume numbers', () {
      expect(TitleMatcher.isMatch('Fantasy Vol 10', 'Fantasy Vol 1'), isFalse);
      expect(TitleMatcher.isMatch('Fantasy Vol 10', 'Fantasy 1'), isFalse);
      expect(TitleMatcher.isMatch('Fantasy Vol 2', 'Fantasy Vol 3'), isFalse);
    });

    test('does NOT match unnumbered title with numbered sequel', () {
      expect(TitleMatcher.isMatch('Friends & Family', 'Friends and Family 2'), isFalse);
      expect(TitleMatcher.isMatch('Friends & Family', 'Friends & Family Vol 2'), isFalse);
      expect(TitleMatcher.isMatch('Friends and Family', 'Friends and Family 3'), isFalse);
    });

    test('does NOT match unrelated titles or partial sub-words or distinct sequels', () {
      expect(TitleMatcher.isMatch('Fantasy 10', 'Doctor Who 10'), isFalse);
      expect(TitleMatcher.isMatch('Alien', 'Alien vs Predator'), isFalse);
      expect(TitleMatcher.isMatch('Love', 'Glove'), isFalse);
      expect(TitleMatcher.isMatch('Her', 'Father'), isFalse);
      expect(TitleMatcher.isMatch('Dune', 'Dune Part Two'), isFalse);
    });
    test('matches volume numbering variations like Young Housewives Vol.3 with Vol 3 / 3', () {
      expect(TitleMatcher.isMatch('Young Housewives Vol.3', 'Young Housewives Vol. 3'), isTrue);
      expect(TitleMatcher.isMatch('young housewives vol.3', 'Young Housewives Vol 3'), isTrue);
      expect(TitleMatcher.isMatch('young housewives vol.3', 'Young Housewives Volume 3'), isTrue);
      expect(TitleMatcher.isMatch('young housewives vol.3', 'Young Housewives 3'), isTrue);
      expect(TitleMatcher.matchScore('young housewives vol.3', 'Young Housewives Vol. 3'), equals(1.0));
    });
  });

  group('TitleMatcher - searchQueries generation', () {
    test('generates cleaned and base fallback search queries', () {
      final queries = TitleMatcher.searchQueries('Fantasy Vol. 10');
      expect(queries, contains('Fantasy Vol. 10'));
      expect(queries, contains('fantasy 10'));
      expect(queries, contains('Fantasy'));
    });

    test('generates volume variation search queries for vol.3', () {
      final queries = TitleMatcher.searchQueries('young housewives vol.3');
      expect(queries, contains('young housewives 3'));
      expect(queries, contains('young housewives vol.3'));
      expect(queries, contains('young housewives Vol 3'));
      expect(queries, contains('young housewives Vol. 3'));
      expect(queries, contains('young housewives Volume 3'));
      expect(queries, contains('young housewives'));
    });

    test('generates stripped studio prefix queries', () {
      final queries = TitleMatcher.searchQueries('Brazzers - Fantasy 10');
      expect(queries, contains('Brazzers - Fantasy 10'));
      expect(queries, contains('Fantasy 10'));
    });
  });

  group('TitleMatcher - findBestMatch', () {
    test('finds best matching MediaItem among provider results', () {
      final results = [
        const MediaItem(
          id: '1',
          title: 'Fantasy 1',
          url: 'url1',
          type: ProviderType.movie,
          sourceId: 'prov',
        ),
        const MediaItem(
          id: '2',
          title: 'Fantasy 10',
          url: 'url2',
          type: ProviderType.movie,
          sourceId: 'prov',
        ),
        const MediaItem(
          id: '3',
          title: 'Unrelated 10',
          url: 'url3',
          type: ProviderType.movie,
          sourceId: 'prov',
        ),
      ];

      final match = TitleMatcher.findBestMatch(results, 'Fantasy Vol. 10');
      expect(match, isNotNull);
      expect(match!.id, '2');
      expect(match.title, 'Fantasy 10');
    });
  });
}
