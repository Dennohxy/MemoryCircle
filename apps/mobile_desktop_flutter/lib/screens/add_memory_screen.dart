import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/paper_card.dart';

/// Step-by-step contribution flow: choose a photo, tell the story, send it
/// for review.
class AddMemoryView extends StatefulWidget {
  const AddMemoryView({
    super.key,
    required this.api,
    required this.circle,
    required this.onDone,
  });

  final ApiClient api;
  final Circle circle;
  final VoidCallback onDone;

  @override
  State<AddMemoryView> createState() => _AddMemoryViewState();
}

class _AddMemoryViewState extends State<AddMemoryView> {
  final _captionController = TextEditingController();
  final _storyController = TextEditingController();
  final _eventController = TextEditingController();
  final _dateController = TextEditingController();
  final _locationController = TextEditingController();

  PlatformFile? _picked;
  Uint8List? _previewBytes;
  PhotoAsset? _uploaded;
  DateTime? _memoryDate;

  bool _uploading = false;
  bool _submitting = false;
  String? _uploadError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _captionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _captionController.dispose();
    _storyController.dispose();
    _eventController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _uploaded != null &&
      !_uploading &&
      !_submitting &&
      _captionController.text.trim().isNotEmpty;

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() {
      _picked = result.files.first;
      _previewBytes = result.files.first.bytes;
      _uploaded = null;
      _uploadError = null;
    });
    await _upload();
  }

  Future<void> _upload() async {
    final file = _picked;
    if (file == null) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final asset = await widget.api.uploadPhoto(widget.circle.id, file);
      if (mounted) setState(() => _uploaded = asset);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() =>
            _uploadError = 'We could not upload this photo. ${error.message} '
                'Try a JPEG, PNG, or WebP image.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _memoryDate ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _memoryDate = picked;
        _dateController.text = formatFriendlyDate(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.api.createMemory(
        widget.circle.id,
        assetId: _uploaded!.id,
        caption: _captionController.text.trim(),
        story: _storyController.text.trim(),
        eventName: _eventController.text.trim(),
        memoryDate: _memoryDate,
        locationText: _locationController.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Your memory was sent. A reviewer will take a look before it joins the album.'),
      ));
      widget.onDone();
    } on ApiException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _stepHeader(theme, 1, 'Choose a photo'),
                const SizedBox(height: Insets.sm + Insets.xs),
                PaperCard(child: _photoStep(theme)),
                const SizedBox(height: Insets.lg),
                _stepHeader(theme, 2, 'Tell the story'),
                const SizedBox(height: Insets.sm + Insets.xs),
                PaperCard(child: _storyStep(theme)),
                const SizedBox(height: Insets.lg),
                _stepHeader(theme, 3, 'Send for review'),
                const SizedBox(height: Insets.sm + Insets.xs),
                PaperCard(child: _submitStep(theme)),
                const SizedBox(height: Insets.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepHeader(ThemeData theme, int number, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.deepGreen,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(width: Insets.sm + Insets.xs),
        Text(title, style: theme.textTheme.titleLarge),
      ],
    );
  }

  Widget _photoStep(ThemeData theme) {
    if (_picked == null) {
      return InkWell(
        onTap: _pickPhoto,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 170,
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_a_photo_outlined,
                  size: 40, color: AppColors.deepGreen),
              const SizedBox(height: Insets.sm + Insets.xs),
              Text('Choose a photo', style: theme.textTheme.titleMedium),
              const SizedBox(height: Insets.xs),
              Text(
                'JPEG, PNG, or WebP',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.softInk),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_previewBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _previewBytes!,
              height: 260,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          )
        else
          Row(
            children: [
              const Icon(Icons.photo_outlined, color: AppColors.softInk),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(_picked!.name,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        const SizedBox(height: Insets.md),
        if (_uploading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: Insets.sm),
          Text(
            'Uploading your photo…',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
          ),
        ] else if (_uploadError != null) ...[
          Text(
            _uploadError!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.rust),
          ),
          const SizedBox(height: Insets.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _upload,
              icon: const Icon(Icons.refresh),
              label: const Text('Try uploading again'),
            ),
          ),
        ] else if (_uploaded != null)
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: Insets.sm),
              Text('Photo ready', style: theme.textTheme.bodyMedium),
            ],
          ),
        const SizedBox(height: Insets.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _uploading ? null : _pickPhoto,
            child: const Text('Choose a different photo'),
          ),
        ),
      ],
    );
  }

  Widget _storyStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _captionController,
          textInputAction: TextInputAction.next,
          decoration: appInput(
            'Short caption',
            helper: 'A line under the photo, like "Grandma\'s 80th birthday".',
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _storyController,
          minLines: 4,
          maxLines: 8,
          decoration: appInput('What is the story behind this photo?'),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _eventController,
          textInputAction: TextInputAction.next,
          decoration: appInput('What was the occasion? (optional)'),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _dateController,
          readOnly: true,
          onTap: _pickDate,
          decoration: appInput(
            'When did this happen? (optional)',
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _locationController,
          decoration: appInput('Where was this? (optional)'),
        ),
      ],
    );
  }

  Widget _submitStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A reviewer in your family will take a look before this memory joins the album.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: Insets.sm),
          Text(
            _submitError!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.rust),
          ),
        ],
        const SizedBox(height: Insets.md),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Send for review'),
        ),
        if (_uploaded == null || _captionController.text.trim().isEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(
            _uploaded == null
                ? 'Choose a photo first, then you can send it.'
                : 'Add a short caption so your family knows what this is.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.softInk),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
