import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/lyrics_job.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/web_audio.dart';
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

  @override
  void initState() {
    super.initState();
    // Чтобы звук сайта не накладывался на музыку приложения.
    ref.read(audioHandlerProvider).pause();

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TrollAudio', onMessageReceived: _onAudio)
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

  Future<void> _download(_Offer offer) async {
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
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
      _say('Добавлено в медиатеку: ${track.title}');
      if (mounted) setState(() => _offer = null);
    } catch (e) {
      _say('Не удалось скачать: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
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
