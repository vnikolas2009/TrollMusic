import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../services/download/download_service.dart';
import '../shared/widgets/splash_gate.dart';
import 'providers.dart';
import 'theme_controller.dart';

class TrollMusicApp extends ConsumerStatefulWidget {
  const TrollMusicApp({super.key});

  @override
  ConsumerState<TrollMusicApp> createState() => _TrollMusicAppState();
}

class _TrollMusicAppState extends ConsumerState<TrollMusicApp>
    with WidgetsBindingObserver {
  int _applied = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (ref.read(themeControllerProvider).mode == ThemeMode.system) {
      setState(() {});
    }
  }

  AppPalette _palette(ThemeState s, Brightness system) {
    final brightness = switch (s.mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => system,
    };

    return AppPalette.build(
      brightness: brightness,
      accent: s.accent,
      amoled: s.amoled,
      gradient: s.gradient,
    );
  }

  /// Цвета читаются через статические геттеры, поэтому при смене палитры
  /// принудительно пересобираем всё дерево (один раз после кадра).
  void _rebuildAll() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(themeControllerProvider);
    final system = MediaQuery.maybePlatformBrightnessOf(context) ??
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    final palette = _palette(state, system);

    final changed = palette.signature != _applied;
    AppPalette.current = palette;

    if (changed) {
      final first = _applied == 0;
      _applied = palette.signature;

      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _rebuildAll();
        });
      }
    }

    final theme = AppTheme.build(palette);

    return MaterialApp(
      title: 'TrollMusic',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: palette.isDark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return _DownloadProgressOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashGate(),
    );
  }
}

/// Глобальная панель прогресса. Работает на всех экранах приложения.
class _DownloadProgressOverlay extends ConsumerWidget {
  const _DownloadProgressOverlay({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);

    return ValueListenableBuilder<DownloadBatchProgress?>(
      valueListenable: downloads.batchProgress,
      builder: (context, progress, _) {
        return Column(
          children: [
            if (progress != null)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: _DownloadProgressBanner(
                    progress: progress,
                    onClose: downloads.dismissBatchProgress,
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _DownloadProgressBanner extends StatelessWidget {
  const _DownloadProgressBanner({
    required this.progress,
    required this.onClose,
  });

  final DownloadBatchProgress progress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isRunning = progress.isRunning;

    final status = progress.canceled
        ? 'Загрузка остановлена'
        : isRunning
            ? 'Скачивание треков'
            : progress.failed > 0
                ? 'Завершено с ошибками'
                : 'Все треки скачаны';

    final currentText = progress.currentTitles.isEmpty
        ? isRunning
            ? 'Подготовка загрузки...'
            : progress.canceled
                ? 'Осталось: ${progress.remaining}'
                : 'Загрузка завершена'
        : progress.currentTitles.length == 1
            ? 'Сейчас: ${progress.currentTitles.first}'
            : 'Сейчас скачиваются ${progress.currentTitles.length} трека';

    return Material(
      color: AppColors.surfaceAlt,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    progress.canceled
                        ? Icons.pause_rounded
                        : isRunning
                            ? Icons.downloading_rounded
                            : progress.failed > 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_rounded,
                    color: AppColors.accent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Скачано ${progress.succeeded} из ${progress.total}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${progress.percent}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Скрыть',
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 5,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  progress.canceled
                      ? 'Отменено'
                      : isRunning
                          ? 'Осталось: ${progress.remaining}'
                          : 'Ошибок: ${progress.failed}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (progress.failed > 0) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Не удалось скачать: ${progress.failed}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
