import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../services/storage/storage_service.dart';

class StorageMeterData {
  const StorageMeterData({
    required this.totalBytes,
    required this.categories,
  });

  final int totalBytes;
  final List<StorageCategory> categories;

  static Future<StorageMeterData> load(StorageService storage) async {
    final total = await storage.usedBytes();

    final audio = await _directorySize(storage.audioDir);
    final artwork = await _directorySize(storage.artworkDir);
    final lyrics = await _directorySize(storage.lyricsDir);

    final categorized = audio + artwork + lyrics;
    final other = total > categorized ? total - categorized : 0;

    return StorageMeterData(
      totalBytes: total,
      categories: [
        StorageCategory(
          title: 'Аудиофайлы',
          description: 'Скачанные и импортированные музыкальные файлы.',
          bytes: audio,
          color: Colors.blue,
          icon: Icons.music_note_rounded,
        ),
        StorageCategory(
          title: 'Обложки',
          description: 'Изображения альбомов и обложки треков.',
          bytes: artwork,
          color: Colors.deepPurpleAccent,
          icon: Icons.image_rounded,
        ),
        StorageCategory(
          title: 'Тексты песен',
          description: 'Сохранённые тексты и файлы синхронизации.',
          bytes: lyrics,
          color: Colors.orange,
          icon: Icons.lyrics_rounded,
        ),
        StorageCategory(
          title: 'Другое',
          description: 'Остальные файлы приложения.',
          bytes: other,
          color: Colors.teal,
          icon: Icons.folder_rounded,
        ),
      ],
    );
  }

  static Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;

    var total = 0;

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            // Пропускаем файл, который уже удалён или недоступен.
          }
        }
      }
    } on FileSystemException {
      return total;
    }

    return total;
  }
}

class StorageCategory {
  const StorageCategory({
    required this.title,
    required this.description,
    required this.bytes,
    required this.color,
    required this.icon,
  });

  final String title;
  final String description;
  final int bytes;
  final Color color;
  final IconData icon;
}

class StorageMeter extends StatelessWidget {
  const StorageMeter({
    super.key,
    required this.data,
    required this.loading,
    required this.onRefresh,
  });

  final StorageMeterData? data;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final total = data?.totalBytes ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage_rounded, size: 20),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Хранилище TrollMusic',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Обновить',
                    visualDensity: VisualDensity.compact,
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: loading
                    ? const Align(
                        key: ValueKey('loading'),
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        ),
                      )
                    : Column(
                        key: const ValueKey('loaded'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatBytes(total),
                            style: const TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Занято файлами приложения',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _StorageBar(data: data),
                          const SizedBox(height: 14),
                          for (final category in data?.categories ?? [])
                            _CategoryTile(
                              category: category,
                              totalBytes: total,
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Учитываются файлы TrollMusic, а не всё '
                            'хранилище устройства.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.data});

  final StorageMeterData? data;

  @override
  Widget build(BuildContext context) {
    final categories = data?.categories
            .where((category) => category.bytes > 0)
            .toList() ??
        [];

    final total = data?.totalBytes ?? 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 13,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (total <= 0 || categories.isEmpty) {
              return Container(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.35),
              );
            }

            return Stack(
              children: [
                Container(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.2),
                ),
                Row(
                  children: [
                    for (final category in categories)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth *
                            category.bytes /
                            total,
                        height: 13,
                        color: category.color,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.totalBytes,
  });

  final StorageCategory category;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final percent = totalBytes > 0
        ? category.bytes / totalBytes * 100
        : 0.0;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(
          left: 40,
          right: 4,
          bottom: 12,
        ),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: category.color,
            shape: BoxShape.circle,
          ),
        ),
        title: Text(
          category.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${formatBytes(category.bytes)} · ${percent.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              category.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
