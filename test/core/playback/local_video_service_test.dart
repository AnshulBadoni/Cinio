import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/local_video_service.dart';

void main() {
  group('LocalVideoService.cleanFilename', () {
    test('extracts clean title, year, season, and episode from typical movie and TV filenames', () {
      final t1 = LocalVideoService.cleanFilename('Oppenheimer.2023.2160p.UHD.BluRay.x265-GROUP.mkv');
      expect(t1.cleanTitle, equals('Oppenheimer'));
      expect(t1.year, equals('2023'));
      expect(t1.season, isNull);
      expect(t1.episode, isNull);

      final t2 = LocalVideoService.cleanFilename('Stranger.Things.S04E07.1080p.NF.WEB-DL.DDP5.1.Atmos.x264.mkv');
      expect(t2.cleanTitle, equals('Stranger Things'));
      expect(t2.season, equals(4));
      expect(t2.episode, equals(7));

      final t3 = LocalVideoService.cleanFilename('Breaking Bad - 1x01 - Pilot.mp4');
      expect(t3.cleanTitle, equals('Breaking Bad'));
      expect(t3.season, equals(1));
      expect(t3.episode, equals(1));

      final t4 = LocalVideoService.cleanFilename('The_Dark_Knight_2008_1080p_BluRay.mp4');
      expect(t4.cleanTitle, equals('The Dark Knight'));
      expect(t4.year, equals('2008'));
    });
  });
}
