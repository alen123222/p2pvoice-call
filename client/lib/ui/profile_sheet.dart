import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/call_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/avatar_model.dart';
import '../models/input_validation.dart';
import 'widgets/avatar_circle.dart';

Future<void> showProfileSheet(BuildContext context, CallController session) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProfileSheet(session: session),
    );

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.session});
  final CallController session;
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  bool _closing = false;
  final _form = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.session.userId);
  late String _avatar = widget.session.avatarId;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted && widget.session.inCall && !_closing) {
      _closing = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.editIdTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            TextFormField(
              controller: _id,
              maxLength: 64,
              autocorrect: false,
              decoration: InputDecoration(labelText: l.myUserIdLabel),
              validator: (value) => InputValidation.userId(value!.trim())
                  ? null
                  : l.t('invalidId'),
            ),
            const SizedBox(height: 12),
            Text(l.avatarPickerTitle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AvatarManager.presets
                  .map(
                    (avatar) => Semantics(
                      selected: _avatar == avatar.id,
                      child: IconButton(
                        tooltip: l.avatarName(avatar.id),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _avatar = avatar.id),
                        style: IconButton.styleFrom(
                          backgroundColor: _avatar == avatar.id
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                        ),
                        icon: AvatarCircle(avatar: avatar, size: 42),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l.chooseImage),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() => _busy = true);
                        try {
                          await widget.session.updateIdentity(
                            _id.text.trim(),
                            _avatar,
                          );
                          if (context.mounted) Navigator.of(context).pop();
                        } catch (_) {
                          _failed();
                        }
                      },
                child: Text(l.save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _failed() {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.t('saveFailed'))),
    );
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 80,
      );
      if (image == null || !mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
      final file = await File(image.path).copy('${dir.path}/$id.jpg');
      await AvatarManager.addAvatar(
        AvatarItem(
          id: id,
          name: 'Custom',
          emoji: '🖼️',
          imagePath: file.path,
          gradient: const [Color(0xFF3C8B80), Color(0xFF8CD6AD)],
        ),
      );
      if (mounted) setState(() => _avatar = id);
    } catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
