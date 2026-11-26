import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/appearance_controller.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics.dart';
import '../../shared/widgets/press_scale.dart';
import '../lyrics/lyrics_screen.dart';

/// Текущая строка текста под обложкой. Нажатие открывает полноэкранный
/// режим текстов. Строка показывается только для текстов с таймкодами; для
/// остальных (и при выключенной строке) вместо неё компактная кнопка
/// «Текст песни», чтобы вход в текст не пропадал.
///
/// Единственное, что слушает позицию воспроизведения: через `select`
/// виджет перестраивается только при смене строки, а не на каждый тик.
class LyricPreview extends ConsumerStatefulWidget {
  const LyricPreview({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<LyricPreview> createState() => _LyricPreviewState();
}

class _LyricPreviewState extends ConsumerState<LyricPreview> {
  String? _raw;
  Lyrics _lyrics = const Lyrics();
  int _offsetMs = 0;
  String? _offsetFor;

  /// Разбор текста кэшируется: пока сырая строка не изменилась, повторно
  /// не парсим.
  Lyrics _parsed(String? raw) {
    if (raw != _raw) {
      _raw = raw;
      _lyrics = raw == null ? const Lyrics() : LrcParser.parse(raw);
    }
    return _lyrics;
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : null;
    openLyricsScreen(context, widget.trackId, origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      appearanceProvider.select((a) => a.showLyricPreview),
    );
    final raw = ref.watch(libraryProvider).lyricsFor(widget.trackId);
    final lyrics = _parsed(raw);

    if (!enabled || !lyrics.synced || lyrics.lines.isEmpty) {
      return _OpenPill(
        found: raw != null && raw.trim().isNotEmpty,
        onOpen: _open,
      );
    }

    if (_offsetFor != widget.trackId) {
      _offsetFor = widget.trackId;
      _offsetMs = ref.read(settingsProvider).lyricsOffsetMs(widget.trackId);
    }

    final index = ref.watch(
      positionProvider.select((position) {
        final shifted =
            (position.value ?? Duration.zero) + Duration(milliseconds: _offsetMs);
        return lyrics.indexAt(shifted < Duration.zero ? Duration.zero : shifted);
      }),
    );

    final text = index < 0 ? '' : lyrics.lines[index].text.trim();
    final label = text.isEmpty ? '♪' : text;

    return PressScale(
      scale: 0.985,
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Center(
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                label,
                key: ValueKey('$index:$label'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактная кнопка входа в текст, когда строки под обложкой нет.
class _OpenPill extends StatelessWidget {
  const _OpenPill({required this.found, required this.onOpen});

  final bool found;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: PressScale(
        scale: 0.96,
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                found ? 'Текст песни' : 'Текст не найден',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
