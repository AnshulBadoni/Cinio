import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';

/// Trailer-source preferences. CloudStream provider responses are deliberately
/// not involved here; the optional alternate source is selected app-side.
class TrailersSettingsScreen extends StatefulWidget {
  const TrailersSettingsScreen({super.key});

  @override
  State<TrailersSettingsScreen> createState() => _TrailersSettingsScreenState();
}

class _TrailersSettingsScreenState extends State<TrailersSettingsScreen> {
  PlaybackPrefs get _prefs => sl<PlaybackPrefs>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Trailers'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.explicit_outlined,
                title: 'NSFW trailers',
                subtitle:
                    'Allow the optional alternate NSFW trailer source for eligible content',
                subtitleMaxLines: null,
                trailing: Switch.adaptive(
                  value: _prefs.nsfwTrailers,
                  activeThumbColor: AppColors.accent,
                  onChanged: (value) async {
                    await _prefs.setNsfwTrailers(value);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () async {
                  await _prefs.setNsfwTrailers(!_prefs.nsfwTrailers);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Movies and TV continue to use the normal TMDB trailer lookup. '
              'This option only permits an alternate source to be considered; '
              'the source and matching rules are configured separately.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
