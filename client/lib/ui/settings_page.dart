import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/call_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/input_validation.dart';
import '../theme/app_theme.dart';
import 'widgets/surface_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session});
  final CallController session;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _closing = false;
  final _form = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.session.serverUrl);
  late final _stun = TextEditingController(text: widget.session.stunServer);
  late final _token = TextEditingController(text: widget.session.token);
  bool _saving = false;
  bool _imageBusy = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    // Incoming calls always regain the foreground, including while editing.
    if (widget.session.inCall && mounted && !_closing) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _url.dispose();
    _stun.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.t('appearance'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: AppThemeType.values.map((type) {
                            final color = AppTheme.seedFor(type);
                            return ChoiceChip(
                              label: Text(l.t('theme_${type.name}')),
                              avatar: CircleAvatar(
                                backgroundColor: color,
                                radius: 8,
                              ),
                              selected: currentThemeTypeNotifier.value == type,
                              onSelected: (_) async {
                                currentThemeTypeNotifier.value = type;
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString('theme_type', type.name);
                                if (mounted) setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          initialValue: languageCodeNotifier.value,
                          decoration: InputDecoration(
                            labelText: l.languageLabel,
                          ),
                          items: ['auto', 'zh', 'en', 'fr']
                              .map(
                                (code) => DropdownMenuItem(
                                  value: code,
                                  child: Text(
                                    {
                                      'auto': l.languageAuto,
                                      'zh': '中文',
                                      'en': 'English',
                                      'fr': 'Français',
                                    }[code]!,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (code) async {
                            if (code == null) return;
                            languageCodeNotifier.value = code;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('language_code', code);
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _imageBusy ? null : _pickBackground,
                              icon: const Icon(Icons.wallpaper_outlined),
                              label: Text(l.chooseImage),
                            ),
                            if (widget.session.backgroundPath != null)
                              TextButton(
                                onPressed: _imageBusy
                                    ? null
                                    : () async {
                                        await widget.session.setBackground(
                                          null,
                                        );
                                        if (mounted) setState(() {});
                                      },
                                child: Text(l.resetBackground),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l.t('network'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SurfaceCard(
                    child: Form(
                      key: _form,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _url,
                            autocorrect: false,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: l.serverLabel,
                              hintText: 'wss://example.com',
                            ),
                            validator: (v) =>
                                InputValidation.signalingUrl(v!.trim())
                                ? null
                                : l.t('invalidServer'),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _stun,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: l.stunLabel,
                              hintText: 'stun:example.com:3478',
                            ),
                            validator: (v) =>
                                InputValidation.stunServer(v!.trim())
                                ? null
                                : l.t('invalidStun'),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _token,
                            autocorrect: false,
                            enableSuggestions: false,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: l.tokenLabel,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l.t('networkSaveHint'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: Text(_saving ? l.loading : l.applySave),
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.session.saveNetwork(_url.text, _stun.text, _token.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.t('saveFailed')),
          ),
        );
      }
    }
  }

  Future<void> _pickBackground() async {
    setState(() => _imageBusy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest =
          '${dir.path}/custom_bg_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(image.path).copy(dest);
      await widget.session.setBackground(dest);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.backgroundError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }
}
