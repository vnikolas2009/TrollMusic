import 'dart:io';

import '../../data/models/track.dart';

/// У трека нет обложки: путь не задан или файл пропал.
/// [exists] можно подменить в тестах.
bool lacksArtwork(Track track, {bool Function(String path)? exists}) {
  final path = track.artworkPath;
  if (path == null || path.isEmpty) return true;
  return !(exists ?? (p) => File(p).existsSync())(path);
}
