import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/settings.dart';
import '../services/lyrics/lyrics_service.dart';

final settingsProvider = Provider<Settings>((ref) => throw UnimplementedError());

final lyricsServiceProvider = Provider<LyricsService>((ref) => LyricsService());
