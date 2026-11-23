import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../core/network/diagnostics.dart';
import '../../core/theme/app_colors.dart';

/// Проверяет, какие серверы приложение видит из вашей сети (с VPN и без).
class NetworkDiagnosticsScreen extends ConsumerStatefulWidget {
  const NetworkDiagnosticsScreen({super.key});

  @override
  ConsumerState<NetworkDiagnosticsScreen> createState() =>
      _NetworkDiagnosticsScreenState();
}

class _NetworkDiagnosticsScreenState
    extends ConsumerState<NetworkDiagnosticsScreen> {
  late final List<DiagTarget> _targets;
  final Map<String, DiagResult> _results = {};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _targets = diagnosticTargets(ref.read(settingsProvider).apiBaseUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    final dio = ref.read(dioProvider);
    await Future.wait([
      for (final target in _targets)
        probe(dio, target).then((result) {
          if (mounted) setState(() => _results[target.name] = result);
        }),
    ]);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _copy() async {
    final ordered = [
      for (final t in _targets)
        if (_results[t.name] != null) _results[t.name]!,
    ];
    await Clipboard.setData(ClipboardData(text: formatReport(ordered)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Отчёт скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Диагностика сети'),
        actions: [
          IconButton(
            tooltip: 'Скопировать отчёт',
            onPressed: _results.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'Проверить снова',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Запустите проверку без VPN и с VPN и пришлите отчёт: так видно, '
            'какой именно сервер блокируется.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final target in _targets) _row(target),
        ],
      ),
    );
  }

  Widget _row(DiagTarget target) {
    final result = _results[target.name];
    final Widget leading;
    String subtitle = target.purpose;
    if (result == null) {
      leading = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (result.reachable) {
      leading = const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E));
      subtitle = 'HTTP ${result.status} · ${result.elapsed.inMilliseconds} мс';
    } else {
      leading = const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444));
      subtitle = result.error ?? 'недоступен';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline),
        ),
        child: ListTile(
          leading: SizedBox(width: 24, child: Center(child: leading)),
          title: Text(target.name),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
