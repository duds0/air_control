import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/regions.dart';
import '../../domain/providers.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _pat = TextEditingController();
  final _country = TextEditingController(text: 'BR');
  ThinqRegion _region = ThinqRegion.america;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _pat.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_pat.text.trim().isEmpty) {
      setState(() => _error = 'Cole o seu token (PAT).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(credentialsProvider.notifier).signIn(
            pat: _pat.text,
            country: _country.text,
            region: _region,
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Não foi possível conectar. Verifique o token, o país e a região.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ac_unit_rounded,
                      size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('Air Control',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    'Gere um token em connect-pat.lgthinq.com (conta ThinQ) e cole abaixo. Ele fica guardado apenas neste dispositivo.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _pat,
                    obscureText: _hide,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Token (PAT)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                      suffixIcon: IconButton(
                        icon: Icon(_hide
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _country,
                          maxLength: 2,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'País',
                            counterText: '',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<ThinqRegion>(
                          initialValue: _region,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Região',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          items: [
                            for (final r in ThinqRegion.values)
                              DropdownMenuItem(
                                value: r,
                                child: Text(r.label,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (r) => setState(() => _region = r!),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _connect,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Conectar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
