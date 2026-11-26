import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../app/settings_provider.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/read_along.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/read_along_text.dart';
import 'aurora_background.dart';

const _defaultAurora = Color(0xFF3A4570);

/// Открывает полноэкранный режим текстов: экран плавно выезжает снизу
/// и проявляется; закрывается стрелкой вниз, кнопкой «назад» или жестом
/// системы и возвращает в плеер.
void openLyricsScreen(BuildContext context, String trackId) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: AppMotion.slower,
      reverseTransitionDuration: AppMotion.base,
      pageBuilder: (_, __, ___) => LyricsScreen(trackId: trackId),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final _scrollController = ScrollController();
  final _keys = <int, GlobalKey>{};

  int _activeIndex = -1;
  int _offsetMs = 0;

  /// Пока пользователь листает текст сам, автопрокрутка не мешает; через
  /// несколько секунд после отпускания экран возвращается к текущей строке.
  bool _userScrolling = false;
  bool _positioned = false;
  Timer? _resumeTimer;

  Color _aurora = _defaultAurora;
  String? _colorSourceId;

  @override
  void initState() {
    super.initState();
    _offsetMs = ref.read(settingsProvider).lyricsOffsetMs(widget.trackId);
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveColor(Track track) async {
    if (_colorSourceId == track.id) return;
    _colorSourceId = track.id;

    ImageProvider? image;
    final local = track.artworkPath;

    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      image = FileImage(File(local));
    }

    if (image == null) return;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        image,
        size: const Size(96, 96),
      );

      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color;

      if (color != null && mounted) {
        setState(() => _aurora = color);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(libraryProvider).lyricsFor(widget.trackId);
    final lyrics = raw == null ? const Lyrics() : LrcParser.parse(raw);

    final track = ref.watch(currentTrackProvider).value;

    if (track != null) {
      _resolveColor(track);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад к плееру',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track?.title ?? 'Текст песни',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (track != null)
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          if (lyrics.synced) _offsetMenu(),
          _lyricsMenu(context, track, raw),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AuroraBackground(color: _aurora),
          ),
          Positioned.fill(
            child: _body(lyrics, raw),
          ),
        ],
      ),
    );
  }

  Widget _offsetMenu() {
    return PopupMenuButton<int>(
      color: AppColors.surfaceAlt,
      icon: const Icon(Icons.sync_alt, size: 20),
      tooltip: 'Сдвиг синхронизации',
      onSelected: (value) {
        setState(() => _offsetMs = value);

        ref
            .read(settingsProvider)
            .setLyricsOffsetMs(widget.trackId, value);
      },
      itemBuilder: (_) => [
        for (final shift in const [
          -2000,
          -1000,
          -500,
          0,
          500,
          1000,
          2000,
        ])
          PopupMenuItem(
            value: shift,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shift == 0
                        ? 'Без сдвига'
                        : '${shift > 0 ? '+' : ''}${shift / 1000} с',
                  ),
                ),
                if (shift == _offsetMs)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: AppColors.accent,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _lyricsMenu(
    BuildContext context,
    Track? track,
    String? raw,
  ) {
    const custom = 'custom';
    const auto = 'auto';
    const file = 'file';
    const remove = 'remove';
    const providers = {
      'lrclib': 'LRCLIB',
      'netease': 'NetEase (в том числе пословные)',
      'kugou': 'Kugou (пословные)',
      'qq': 'QQ Music',
      'ovh': 'Lyrics.ovh (без таймкодов)',
    };

    return PopupMenuButton<String>(
      color: AppColors.surfaceAlt,
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Текст песни',
      onSelected: (value) async {
        if (track == null) return;

        if (value == custom) {
          await _editOwn(context, raw);
          return;
        }

        if (value == file) {
          final updated =
              await ref.read(importProvider).importLyricsFromFile(track.id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(updated == null ? 'Файл не выбран' : 'Текст загружен'),
            ),
          );
          setState(() {});
          return;
        }

        if (value == remove) {
          await ref.read(libraryProvider).clearLyrics(track.id);
          if (mounted) setState(() {});
          return;
        }

        final result = await ref.read(importProvider).findLyricsOnline(
              track,
              provider: value == auto ? null : value,
            );

        if (!context.mounted) return;

        final kind = result.wordSynced
            ? 'по словам'
            : result.synced
                ? 'с таймкодами'
                : 'без таймкодов';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.found
                  ? 'Текст найден ($kind) · ${providers[result.source] ?? result.source}'
                  : 'Текст не найден',
            ),
          ),
        );

        setState(() {});
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: auto,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.search_rounded),
            title: Text('Найти автоматически'),
            subtitle: Text('Перебор всех источников'),
          ),
        ),
        for (final entry in providers.entries)
          PopupMenuItem(
            value: entry.key,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.library_books_outlined),
              title: Text(entry.value),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: file,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.upload_file_rounded),
            title: Text('Загрузить из файла'),
            subtitle: Text('.lrc, enhanced .lrc или .txt'),
          ),
        ),
        const PopupMenuItem(
          value: custom,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_note_rounded),
            title: Text('Свой текст'),
            subtitle: Text('Вставьте текст или LRC с таймкодами'),
          ),
        ),
        if (raw != null)
          const PopupMenuItem(
            value: remove,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Удалить текст'),
            ),
          ),
      ],
    );
  }

  /// Ввод своего текста, обычного LRC или Enhanced LRC.
  Future<void> _editOwn(
    BuildContext context,
    String? current,
  ) async {
    final controller = TextEditingController(text: current ?? '');

    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Свой текст',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Обычный LRC или Enhanced LRC с таймкодами слов',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 8,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Вставьте текст песни…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    sheet,
                    controller.text,
                  ),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    final text = saved?.trim();

    if (text == null || text.isEmpty) return;

    await ref
        .read(importProvider)
        .saveManualLyrics(widget.trackId, text);

    if (mounted) setState(() {});
  }

  /// Рассчитывает прогресс ReadAlongText с учётом реальных таймингов слов.
  ///
  /// ReadAlongText использует взвешенный прогресс по длине слов.
  /// Поэтому переводим временной прогресс Enhanced LRC в тот же формат.
  double _wordProgress(
    LyricLine line,
    Duration position,
    Duration lineEnd,
  ) {
    final words = line.words;

    if (words.isEmpty) return 0.0;

    final visualWords = splitWords(line.text);

    // Если количество слов не совпало, используем обычный прогресс строки.
    if (visualWords.length != words.length) {
      final span = (lineEnd - line.time).inMicroseconds;

      if (span <= 0) return 0.0;

      return ((position - line.time).inMicroseconds / span)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    var activeWord = -1;

    for (var i = 0; i < words.length; i++) {
      if (words[i].start <= position) {
        activeWord = i;
      } else {
        break;
      }
    }

    if (activeWord < 0) return 0.0;

    var completedWeight = 0.0;
    var totalWeight = 0.0;

    for (var i = 0; i < visualWords.length; i++) {
      final weight = wordDwell(visualWords[i].length);
      totalWeight += weight;

      if (i < activeWord) {
        completedWeight += weight;
      }
    }

    final currentStart = words[activeWord].start;

    final currentEnd = activeWord + 1 < words.length
        ? words[activeWord + 1].start
        : lineEnd;

    final duration = (currentEnd - currentStart).inMicroseconds;

    final fraction = duration > 0
        ? ((position - currentStart).inMicroseconds / duration)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;

    final currentWeight = wordDwell(
      visualWords[activeWord].length,
    );

    final progress = (
      completedWeight + currentWeight * fraction
    ) / totalWeight;

    return progress.clamp(0.0, 1.0).toDouble();
  }

  Widget _body(Lyrics lyrics, String? raw) {
    if (lyrics.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Текст не найден.\nОткройте меню ⋮ вверху: поиск в LRCLIB, NetEase, Kugou, QQ, загрузка .lrc или «Свой текст».',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    if (!lyrics.synced) return _plainBody(raw ?? lyrics.plainText);

    final positions = ref.watch(audioHandlerProvider).positionStream;

    Duration shifted(Duration position) {
      final value = position + Duration(milliseconds: _offsetMs);

      return value < Duration.zero
          ? Duration.zero
          : value;
    }

    final indexes = positions
        .map((p) => lyrics.indexAt(shifted(p)))
        .distinct();

    final screenHeight = MediaQuery.sizeOf(context).height;

    return StreamBuilder<int>(
      stream: indexes,
      initialData: -1,
      builder: (context, snapshot) {
        final index = snapshot.data ?? -1;

        if (index != _activeIndex) {
          _activeIndex = index;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_userScrolling) _ensureVisible(index);
          });
        }

        // Все строки лежат в Column, поэтому у каждой всегда есть контекст
        // для прокрутки, даже если она далеко за экраном (после перемотки).
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(24, 120, 24, screenHeight * 0.55),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lyrics.lines.length; i++)
                  _buildLine(lyrics, i, index, positions, shifted),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLine(
    Lyrics lyrics,
    int i,
    int index,
    Stream<Duration> positions,
    Duration Function(Duration) shifted,
  ) {
    final line = lyrics.lines[i];
    final distance = index < 0 ? 99 : i - index;

    Widget? active;

    if (i == index) {
      final lineEnd = i + 1 < lyrics.lines.length
          ? lyrics.lines[i + 1].time
          : line.time + const Duration(seconds: 5);

      active = StreamBuilder<Duration>(
        stream: positions,
        builder: (context, position) {
          final safe = shifted(position.data ?? Duration.zero);

          return ReadAlongText(
            text: line.text,
            progress: line.hasWordTiming
                ? _wordProgress(line, safe, lineEnd)
                : _lineProgress(line, safe, lineEnd),
            style: _LyricLine.style,
          );
        },
      );
    }

    return GestureDetector(
      key: _keys.putIfAbsent(i, () => GlobalKey()),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _resumeTimer?.cancel();
        _userScrolling = false;
        ref.read(audioHandlerProvider).seek(line.time);
      },
      child: RepaintBoundary(
        child: _LyricLine(
          text: line.text,
          distance: distance,
          active: active,
        ),
      ),
    );
  }

  /// Текст без таймкодов: обычное чтение с прокруткой, куплеты разделены
  /// отступами.
  Widget _plainBody(String raw) {
    final rows = LrcParser.plainLines(raw);

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 110, 24, 120),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];

        if (row.isEmpty) return const SizedBox(height: 22);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            row,
            style: _LyricLine.style.copyWith(
              fontSize: 22,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        );
      },
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _resumeTimer?.cancel();
      _userScrolling = true;
    } else if (n is ScrollEndNotification && _userScrolling) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        _userScrolling = false;
        _ensureVisible(_activeIndex);
      });
    }
    return false;
  }

  /// Прежняя синхронизация по времени всей строки для обычного LRC.
  double _lineProgress(
    LyricLine line,
    Duration position,
    Duration lineEnd,
  ) {
    final span = (lineEnd - line.time).inMilliseconds;

    if (span <= 0) return 0.0;

    return ((position - line.time).inMilliseconds / span)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _ensureVisible(int index) {
    if (index < 0) return;

    final ctx = _keys[index]?.currentContext;

    if (ctx == null) return;

    // Первое позиционирование (открытие экрана) — без анимации.
    final first = !_positioned;
    _positioned = true;

    Scrollable.ensureVisible(
      ctx,
      alignment: 0.32,
      duration: first ? Duration.zero : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Строка текста. Активная подсвечивается слева направо, пройденные
/// приглушены слабее, будущие сильнее. Смена состояния плавная: меняются
/// прозрачность и масштаб, а не сама строка.
class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.text,
    required this.distance,
    this.active,
  });

  final String text;

  /// Расстояние до текущей строки: 0 — текущая, меньше нуля — пройденные.
  final int distance;

  /// Виджет активной строки (с подсветкой по словам); у остальных `null`.
  final Widget? active;

  static const style = TextStyle(
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final label = text.trim().isEmpty ? '♪' : text;
    final isActive = distance == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: AnimatedOpacity(
        duration: AppMotion.slow,
        curve: AppMotion.enter,
        opacity: lyricLineOpacity(distance),
        child: AnimatedScale(
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          alignment: Alignment.centerLeft,
          scale: isActive ? 1.0 : 0.94,
          child: Align(
            alignment: Alignment.centerLeft,
            child: isActive && text.trim().isNotEmpty
                ? active ?? Text(label, style: style)
                : Text(label, style: style),
          ),
        ),
      ),
    );
  }
}

/// Яркость строки по расстоянию до текущей: текущая — полная, пройденные
/// ярче будущих, дальние постепенно тускнеют до нижней границы.
double lyricLineOpacity(int distance) {
  if (distance == 0) return 1.0;
  final far = distance.abs() - 1;
  if (distance < 0) return (0.55 - far * 0.04).clamp(0.3, 0.55).toDouble();
  return (0.38 - far * 0.02).clamp(0.24, 0.38).toDouble();
}
