import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/lyrics_job.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/browser_bookmarks.dart';
import '../../core/utils/web_audio.dart';
import '../../data/models/track.dart';
import '../../services/web/web_download_service.dart';

/// Скрипт: сообщает приложению адрес, когда на странице начинает играть
/// аудио (в том числе созданное через `new Audio()`).
const _hookScript = '''
(function () {
  if (window.__trollAudioHook) return;
  window.__trollAudioHook = true;
  var play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () {
    try {
      var src = this.currentSrc || this.src;
      if (src && src.indexOf('http') === 0) {
        TrollAudio.postMessage(JSON.stringify({
          src: src, tag: this.tagName, title: document.title
        }));
      }
    } catch (e) {}
    return play.apply(this, arguments);
  };
})();
''';

/// Скрипт «Найти аудио на странице»: медиаэлементы, их `<source>`, ссылки на
/// аудиофайлы и уже загруженные страницей аудиоресурсы (потоки плееров).
const _scanScript = '''
(function () {
  var out = [];
  function add(u, t, media) {
    try {
      if (!u) return;
      out.push({ src: new URL(u, location.href).href, title: t || '', media: !!media });
    } catch (e) {}
  }
  document.querySelectorAll('audio,video').forEach(function (m) {
    add(m.currentSrc || m.src, document.title, true);
    m.querySelectorAll('source').forEach(function (s) { add(s.src, document.title, true); });
  });
  document.querySelectorAll('a[href]').forEach(function (a) {
    add(a.href, (a.getAttribute('download') || a.textContent || '').trim(), false);
  });
  try {
    performance.getEntriesByType('resource').forEach(function (r) {
      if (r.initiatorType === 'audio' || r.initiatorType === 'media') add(r.name, document.title, true);
      else add(r.name, document.title, false);
    });
  } catch (e) {}
  TrollScan.postMessage(JSON.stringify({ page: location.href, items: out }));
})();
''';

class _Offer {
  const _Offer(this.url, this.title);
  final Uri url;
  final String? title;
}

/// Встроенный браузер: ищете трек на любом сайте, а когда он начинает играть
/// (или вы открываете прямую ссылку на аудиофайл), плеер предлагает его
/// скачать в медиатеку.
class WebBrowserScreen extends ConsumerStatefulWidget {
  const WebBrowserScreen({super.key});

  @override
  ConsumerState<WebBrowserScreen> createState() => _WebBrowserScreenState();
}

class _WebBrowserScreenState extends ConsumerState<WebBrowserScreen> {
  late final WebViewController _web;
  final _address = TextEditingController();
  final _focus = FocusNode();
  final _dismissed = <String>{};

  int _progress = 0;
  bool _canBack = false;
  String? _pageUrl;
  _Offer? _offer;
  bool _downloading = false;
  double? _downloadProgress;
  List<BrowserBookmark> _custom = const [];

  @override
  void initState() {
    super.initState();
    _custom = [
      for (final raw in ref.read(settingsProvider).browserBookmarks)
        if (decodeBookmark(raw) case final b?) b,
    ];
    // Чтобы звук сайта не накладывался на музыку приложения.
    ref.read(audioHandlerProvider).pause();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TrollAudio', onMessageReceived: _onAudio)
      ..addJavaScriptChannel('TrollScan', onMessageReceived: _onScan)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (url) {
            _web.runJavaScript(_hookScript);
            _onUrl(url);
          },
          onPageFinished: (url) {
            _web.runJavaScript(_hookScript);
            _onUrl(url);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _onUrl(url);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (request.isMainFrame && uri != null && looksLikeAudioUrl(uri)) {
              _suggest(uri, null);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(browserTarget(''));
  }

  @override
  void dispose() {
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onUrl(String url) {
    _pageUrl = url;
    if (!_focus.hasFocus) _address.text = url;
    _web.canGoBack().then((value) {
      if (mounted && value != _canBack) setState(() => _canBack = value);
    });
  }

  void _onAudio(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final uri = Uri.tryParse(data['src'] as String? ?? '');
      if (uri == null) return;
      final isAudio = data['tag'] == 'AUDIO' || looksLikeAudioUrl(uri);
      if (isAudio) _suggest(uri, data['title'] as String?);
    } catch (_) {}
  }

  void _suggest(Uri uri, String? title) {
    final key = uri.toString();
    if (!mounted || _downloading || _dismissed.contains(key)) return;
    setState(() => _offer = _Offer(uri, title));
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Скачивает и импортирует трек; ошибки пробрасывает вызывающему.
  Future<Track> _fetchAndImport(_Offer offer) async {
    final file = await WebDownloadService().download(
      offer.url,
      referer: _pageUrl,
      pageTitle: offer.title,
      onProgress: (value) {
        if (mounted) setState(() => _downloadProgress = value);
      },
    );
    final track = await ref.read(importProvider).importDownloaded(file);
    _dismissed.add(offer.url.toString());
    if (ref.read(settingsProvider).autoLyrics) {
      ref.read(lyricsJobProvider.notifier).run([track]);
    }
    return track;
  }

  Future<void> _download(_Offer offer) async {
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      final track = await _fetchAndImport(offer);
      _say('Добавлено в медиатеку: ${track.title}');
      if (mounted) setState(() => _offer = null);
    } catch (e) {
      _say('Не удалось скачать: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Скачивает несколько найденных на странице файлов подряд.
  Future<void> _downloadMany(List<FoundAudio> items) async {
    if (_downloading || items.isEmpty) return;
    setState(() {
      _downloading = true;
      _downloadProgress = null;
      _offer = null;
    });
    var ok = 0;
    String? lastError;
    for (final item in items) {
      try {
        await _fetchAndImport(_Offer(item.url, item.title));
        ok++;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
      }
    }
    if (mounted) setState(() => _downloading = false);
    _say(ok == items.length
        ? 'Добавлено в медиатеку: $ok'
        : 'Добавлено: $ok из ${items.length}${lastError == null ? '' : ' · $lastError'}');
  }

  /// Запускает поиск аудио на открытой странице; ответ придёт в [_onScan].
  Future<void> _scanPage() async {
    try {
      await _web.runJavaScript(_scanScript);
    } catch (_) {
      _say('Не удалось просмотреть страницу');
    }
  }

  void _onScan(JavaScriptMessage message) {
    if (!mounted) return;
    final found = parseFoundAudio(message.message);
    if (found.isEmpty) {
      _say('Аудио на странице не найдено. Включите трек: плеер предложит его скачать.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => _FoundSheet(
        items: found,
        onDownload: (items) {
          Navigator.pop(sheet);
          _downloadMany(items);
        },
      ),
    );
  }

  // ---- закладки ----

  void _open(String url) => _web.loadRequest(Uri.parse(url));

  Future<void> _addBookmark() async {
    final url = _pageUrl == null ? null : Uri.tryParse(_pageUrl!);
    if (url == null || url.host.isEmpty || url.scheme.startsWith('about')) {
      _say('Откройте страницу, чтобы добавить её в закладки');
      return;
    }
    final all = [...defaultBookmarks, ..._custom];
    if (all.any((b) => b.url == url.toString())) {
      _say('Эта страница уже в закладках');
      return;
    }
    String? pageTitle;
    try {
      pageTitle = await _web.getTitle();
    } catch (_) {}
    final bookmark = BrowserBookmark(bookmarkTitle(pageTitle, url), url.toString());
    setState(() => _custom = [..._custom, bookmark]);
    _saveBookmarks();
    _say('Закладка добавлена: ${bookmark.title}');
  }

  void _removeBookmark(BrowserBookmark b) {
    setState(() => _custom = [for (final c in _custom) if (c != b) c]);
    _saveBookmarks();
    _say('Закладка удалена: ${b.title}');
  }

  void _saveBookmarks() {
    ref.read(settingsProvider).browserBookmarks = [for (final b in _custom) encodeBookmark(b)];
  }

  void _decline(_Offer offer) {
    _dismissed.add(offer.url.toString());
    setState(() => _offer = null);
  }

  Future<void> _submit(String value) async {
    _focus.unfocus();
    await _web.loadRequest(browserTarget(value));
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;

    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _web.canGoBack()) await _web.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextField(
              controller: _address,
              focusNode: _focus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: _submit,
              onTap: () => _address.selection =
                  TextSelection(baseOffset: 0, extentOffset: _address.text.length),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Название трека или адрес сайта',
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceAlt,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Найти аудио на странице',
              icon: const Icon(Icons.library_music_outlined),
              onPressed: _downloading ? null : _scanPage,
            ),
            IconButton(
              tooltip: 'Добавить в закладки',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: _addBookmark,
            ),
            IconButton(
              tooltip: 'Обновить',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _web.reload,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress > 0 && _progress < 100
                ? LinearProgressIndicator(value: _progress / 100, minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
        body: Column(
          children: [
            _BookmarksBar(
              defaults: defaultBookmarks,
              custom: _custom,
              onOpen: _open,
              onRemove: _removeBookmark,
            ),
            Expanded(child: WebViewWidget(controller: _web)),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: offer == null
                  ? const SizedBox(width: double.infinity)
                  : _OfferPanel(
                      offer: offer,
                      downloading: _downloading,
                      progress: _downloadProgress,
                      onDownload: () => _download(offer),
                      onDecline: () => _decline(offer),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferPanel extends StatelessWidget {
  const _OfferPanel({
    required this.offer,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    required this.onDecline,
  });

  final _Offer offer;
  final bool downloading;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final name = downloadFileName(url: offer.url, pageTitle: offer.title);

    return Material(
      color: AppColors.surfaceAlt,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.audiotrack_rounded, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Скачать этот трек?',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (!downloading) ...[
                    TextButton(onPressed: onDecline, child: const Text('Нет')),
                    FilledButton(onPressed: onDownload, child: const Text('Скачать')),
                  ],
                ],
              ),
              if (downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: LinearProgressIndicator(value: progress),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоса закладок: готовые сайты и свои (долгое нажатие удаляет свою).
class _BookmarksBar extends StatelessWidget {
  const _BookmarksBar({
    required this.defaults,
    required this.custom,
    required this.onOpen,
    required this.onRemove,
  });

  final List<BrowserBookmark> defaults;
  final List<BrowserBookmark> custom;
  final void Function(String url) onOpen;
  final void Function(BrowserBookmark) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          for (final b in defaults)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: const Icon(Icons.public_rounded, size: 16),
                label: Text(b.title),
                visualDensity: VisualDensity.compact,
                onPressed: () => onOpen(b.url),
              ),
            ),
          for (final b in custom)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () => onRemove(b),
                child: ActionChip(
                  avatar: const Icon(Icons.bookmark_rounded, size: 16),
                  label: Text(b.title),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onOpen(b.url),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Список аудио, найденного на странице: скачать выбранные или все.
class _FoundSheet extends StatefulWidget {
  const _FoundSheet({required this.items, required this.onDownload});

  final List<FoundAudio> items;
  final void Function(List<FoundAudio> items) onDownload;

  @override
  State<_FoundSheet> createState() => _FoundSheetState();
}

class _FoundSheetState extends State<_FoundSheet> {
  late final Set<int> _picked = {for (var i = 0; i < widget.items.length; i++) i};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Найдено аудио: ${items.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return CheckboxListTile(
                  dense: true,
                  value: _picked.contains(i),
                  onChanged: (v) => setState(() {
                    if (v ?? false) {
                      _picked.add(i);
                    } else {
                      _picked.remove(i);
                    }
                  }),
                  title: Text(
                    downloadFileName(url: item.url, pageTitle: item.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.url.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _picked.isEmpty
                    ? null
                    : () => widget.onDownload([
                          for (var i = 0; i < items.length; i++)
                            if (_picked.contains(i)) items[i],
                        ]),
                icon: const Icon(Icons.download_rounded),
                label: Text('Скачать (${_picked.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
