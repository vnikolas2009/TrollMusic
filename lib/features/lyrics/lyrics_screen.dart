import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../app/appearance_controller.dart';
import '../../app/lyrics_style_provider.dart';
import '../../app/settings_provider.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/loop_range.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/lyric_style.dart';
import '../../core/utils/read_along.dart';
import '../../data/models/lyrics.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/read_along_text.dart';
import 'aurora_background.dart';
import 'lyrics_settings_sheet.dart';

const _defaultAurora = Color(0xFF3A4570);

/// Открывает полноэкранный режим текстов: экран раскрывается кругом из
/// точки [origin] (центр нажатой кнопки), содержимое при этом чуть
/// увеличивается и проявляется. Закрывается стрелкой вниз, кнопкой «назад»
/// или жестом системы — круг схлопывается обратно.
void openLyricsScreen(
  BuildContext context,
  String trackId, {
  Offset? origin,
}) {
  final size = MediaQuery.sizeOf(context);
  final center = origin ?? Offset(size.width / 2, size.height * 0.6);

  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: AppMotion.slower,
      reverseTransitionDuration: AppMotion.base,
      pageBuilder: (_, __, ___) => LyricsScreen(trackId: trackId),
      transitionsBuilder: (_, animation, __, child) {
        final reveal = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.exit,
        );
        final content = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
          reverseCurve: const Interval(0, 0.6, curve: Curves.easeIn),
        );
        return AnimatedBuilder(
          animation: reveal,
          builder: (_, __) => ClipPath(
            clipper: CircleRevealClipper(
              center: center,
              fraction: reveal.value.clamp(0.0, 1.0),
            ),
            child: FadeTransition(
              opacity: content,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.06, end: 1).animate(content),
                child: child,
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Круглое окно с центром в [center]; при [fraction] = 1 перекрывает весь
/// экран.
class CircleRevealClipper extends CustomClipper<Path> {
  const CircleRevealClipper({required this.center, required this.fraction});

  final Offset center;
  final double fraction;

  @override
  Path getClip(Size size) {
    final farthest = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - center).distance).reduce((a, b) => a > b ? a : b);

    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: farthest * fraction));
  }

  @override
  bool shouldReclip(CircleRevealClipper old) =>
      old.fraction != fraction || old.center != center;
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
          IconButton(
            tooltip: 'Настройки текста',
            icon: const Icon(Icons.text_fields_rounded, size: 22),
            onPressed: () => showLyricsSettings(context),
          ),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
            child: Center(
              child: ValueListenableBuilder<LoopRange?>(
                valueListenable: ref.read(audioHandlerProvider).loop,
                builder: (context, range, _) => AnimatedSwitcher(
                  duration: AppMotion.base,
                  child: range == null
                      ? const SizedBox.shrink()
                      : _LoopChip(
                          onClear: ref.read(audioHandlerProvider).clearLoop,
                        ),
                ),
              ),
            ),
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
            'Текст не найден.\nОткройте меню ⋮ вверху: поиск в LRCLIB, Kugou, QQ, загрузка .lrc или «Свой текст».',
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
    final style = ref.watch(lyricsStyleProvider);
    final fontScale = ref.watch(appearanceProvider).lyricsScale;

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
                  _buildLine(lyrics, i, index, positions, shifted, style, fontScale),
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
    LyricsStyle style,
    double fontScale,
  ) {
    final line = lyrics.lines[i];
    final distance = index < 0 ? 99 : i - index;
    final look = style.look;

    Widget? active;

    // Подсветка по словам нужна только стилю с wordHighlight; у остальных
    // текущая строка — обычный текст, и позицию слушать не надо.
    if (i == index && look.wordHighlight) {
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
            style: look.textStyle(
              active: true,
              accent: AppColors.accent,
              scale: fontScale,
            ),
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
        ref.read(audioHandlerProvider).seek(_audioTime(line.time));
      },
      onLongPress: () => _loopLine(lyrics, i),
      child: RepaintBoundary(
        child: _LyricLine(
          text: line.text,
          distance: distance,
          lyricsStyle: style,
          fontScale: fontScale,
          active: active,
        ),
      ),
    );
  }

  /// Время строки в аудио: время текста минус сдвиг (подсветка считается как
  /// позиция + сдвиг).
  Duration _audioTime(Duration lyricTime) {
    final value = lyricTime - Duration(milliseconds: _offsetMs);
    return value < Duration.zero ? Duration.zero : value;
  }

  /// Долгое нажатие: повторять эту строку, пока повтор не отменят.
  void _loopLine(Lyrics lyrics, int i) {
    final handler = ref.read(audioHandlerProvider);
    final range = loopRangeForLine(
      lineTime: lyrics.lines[i].time,
      nextLineTime:
          i + 1 < lyrics.lines.length ? lyrics.lines[i + 1].time : null,
      offsetMs: _offsetMs,
      trackDuration: handler.player.duration,
    );
    if (range == null) return;

    HapticFeedback.mediumImpact();
    _resumeTimer?.cancel();
    _userScrolling = false;
    handler.setLoop(range);
  }

  /// Текст без таймкодов: обычное чтение с прокруткой, куплеты разделены
  /// отступами.
  Widget _plainBody(String raw) {
    final rows = LrcParser.plainLines(raw);
    // Провайдеры читаем здесь, а не в itemBuilder: ref.watch допустим в build.
    final rowStyle = ref
        .watch(lyricsStyleProvider)
        .look
        .textStyle(active: false, accent: AppColors.accent)
        .copyWith(
          fontSize: 22 * ref.watch(appearanceProvider).lyricsScale,
          color: Colors.white.withValues(alpha: 0.92),
        );

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
          child: Text(row, style: rowStyle),
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

/// Строка текста. Вид зависит от выбранного [LyricsStyle]: в Spotify-like
/// активная строка подсвечивается слева направо, пройденные приглушены
/// слабее будущих. Смена состояния плавная: меняются прозрачность, масштаб
/// и начертание, а не сама строка.
class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.text,
    required this.distance,
    required this.lyricsStyle,
    required this.fontScale,
    this.active,
  });

  final String text;

  /// Расстояние до текущей строки: 0 — текущая, меньше нуля — пройденные.
  final int distance;

  final LyricsStyle lyricsStyle;

  /// Масштаб текста песен из настроек.
  final double fontScale;

  /// Виджет активной строки (с подсветкой по словам); у остальных `null`.
  final Widget? active;

  @override
  Widget build(BuildContext context) {
    final look = lyricsStyle.look;
    final label = text.trim().isEmpty ? '♪' : text;
    final isActive = distance == 0;
    final style = look.textStyle(
      active: isActive,
      accent: AppColors.accent,
      scale: fontScale,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: look.verticalPadding),
      child: AnimatedOpacity(
        duration: AppMotion.slow,
        curve: AppMotion.enter,
        opacity: lyricsStyle.opacity(distance),
        child: AnimatedScale(
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
          alignment: Alignment.centerLeft,
          scale: isActive ? 1.0 : look.inactiveScale,
          child: Align(
            alignment: Alignment.centerLeft,
            child: isActive && active != null && text.trim().isNotEmpty
                ? active
                : AnimatedDefaultTextStyle(
                    duration: AppMotion.base,
                    style: style,
                    child: Text(label),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Плашка «Повтор строки» с отменой по нажатию.
class _LoopChip extends StatelessWidget {
  const _LoopChip({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onClear,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.repeat_one_rounded, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Повтор строки',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.close_rounded, size: 18, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
