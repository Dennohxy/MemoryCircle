import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app/theme.dart';
import '../widgets/authed_image.dart';

/// The no-login flow opened from a campaign link (`?campaign=TOKEN`): a guest
/// enters their name and email (optionally confirms a code), then uploads
/// photos to the event and sees the shared gallery.
class GuestCampaignScreen extends StatefulWidget {
  const GuestCampaignScreen(
      {super.key, required this.api, required this.token});

  final ApiClient api;
  final String token;

  @override
  State<GuestCampaignScreen> createState() => _GuestCampaignScreenState();
}

enum _Step { loading, closed, register, verify, contribute }

class _GuestCampaignScreenState extends State<GuestCampaignScreen> {
  _Step _step = _Step.loading;
  Map<String, dynamic>? _campaign;
  String? _guestToken;
  String _error = '';
  bool _busy = false;
  int _uploaded = 0;
  bool _acceptConsent = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getCampaign(widget.token);
      if (!mounted) return;
      setState(() {
        _campaign = data;
        _step = data['is_open'] == true ? _Step.register : _Step.closed;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _step = _Step.closed;
        _error = error.message;
      });
    }
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter your name and a valid email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = _isYearbook
          ? await widget.api.registerContributor(
              widget.token,
              name: name,
              email: email,
              acceptConsent: _acceptConsent,
            )
          : await widget.api
              .registerGuest(widget.token, name: name, email: email);
      if (!mounted) return;
      if (result['needs_verification'] == true) {
        setState(() => _step = _Step.verify);
      } else {
        setState(() {
          _guestToken =
              (result['guest_token'] ?? result['contributor_token']) as String?;
          _step = _Step.contribute;
        });
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final guestToken = _isYearbook
          ? await widget.api.verifyContributor(
              widget.token,
              email: _emailController.text.trim(),
              code: _codeController.text.trim(),
            )
          : await widget.api.verifyGuest(
              widget.token,
              email: _emailController.text.trim(),
              code: _codeController.text.trim(),
            );
      if (!mounted) return;
      setState(() {
        _guestToken = guestToken;
        _step = _Step.contribute;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final token = _guestToken;
    if (token == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    var done = 0;
    for (final file in result.files) {
      try {
        if (_isYearbook) {
          final assetId = await widget.api.uploadContributionAsset(
            widget.token,
            contributorToken: token,
            file: file,
          );
          await widget.api.createContribution(
            widget.token,
            contributorToken: token,
            type: 'photo_memory',
            payload: {'caption': ''},
            assetId: assetId,
          );
        } else {
          await widget.api
              .guestUpload(widget.token, guestToken: token, file: file);
        }
        done++;
      } on ApiException catch (error) {
        setState(() => _error = error.message);
      }
    }
    if (!mounted) return;
    setState(() {
      _uploaded += done;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_campaign?['title'] as String? ?? 'Event campaign'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_step) {
      case _Step.loading:
        return const Center(child: CircularProgressIndicator());
      case _Step.closed:
        return _Message(
          icon: Icons.lock_clock_outlined,
          title: 'This upload link is closed',
          message: _error.isNotEmpty
              ? _error
              : 'The event has ended or the link was turned off.',
        );
      case _Step.register:
        return _registerForm(context);
      case _Step.verify:
        return _verifyForm(context);
      case _Step.contribute:
        return _contribute(context);
    }
  }

  bool get _isYearbook =>
      (_campaign?['campaign_type'] as String? ?? 'photo_collection') !=
      'photo_collection';

  bool get _needsConsent =>
      _isYearbook && (_campaign?['consent_text'] as String? ?? '').isNotEmpty;

  List<String> get _enabledTypes => [
        for (final item in ((_campaign?['contribution_schema']
                    as Map<String, dynamic>?)?['enabled_types']
                as List<dynamic>? ??
            const []))
          '$item',
      ];

  Future<void> _submitStructured(String type) async {
    final token = _guestToken;
    if (token == null) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContributionDialog(type: type),
    );
    if (payload == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.api.createContribution(
        widget.token,
        contributorToken: token,
        type: type,
        payload: payload,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Submission sent for organizer review.'),
      ));
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _registerForm(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text(_isYearbook
            ? 'You\'re invited to add to the yearbook'
            : 'You\'re invited to add photos',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: Insets.sm),
        Text(
          _isYearbook
              ? 'Add your name and email so your event submissions can be reviewed. No account needed.'
              : 'Add your name and email so ${_campaign?['circle_name'] ?? 'the organisers'} '
                  'know who shared each photo. No account needed.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
        if (_isYearbook &&
            (_campaign?['consent_text'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: Insets.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acceptConsent,
            onChanged: (value) =>
                setState(() => _acceptConsent = value ?? false),
            title: Text(_campaign!['consent_text'] as String),
          ),
        ],
        const SizedBox(height: Insets.lg),
        TextField(
            controller: _nameController, decoration: appInput('Your name')),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: appInput('Your email'),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(_error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.attention)),
        ],
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: _busy || (_needsConsent && !_acceptConsent)
              ? null
              : _register,
          child: Text(_busy ? 'Please wait…' : 'Continue'),
        ),
      ],
    );
  }

  Widget _verifyForm(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Check your email', style: theme.textTheme.headlineSmall),
        const SizedBox(height: Insets.sm),
        Text(
          'We sent a 6-digit code to ${_emailController.text.trim()}. '
          'Enter it below to start adding photos.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
        const SizedBox(height: Insets.lg),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          decoration: appInput('6-digit code'),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(_error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.attention)),
        ],
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? 'Please wait…' : 'Confirm'),
        ),
      ],
    );
  }

  Widget _contribute(BuildContext context) {
    if (_isYearbook) return _yearbookContribute(context);
    final theme = Theme.of(context);
    final gallery = (_campaign?['gallery'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _pickAndUpload,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_busy ? 'Uploading…' : 'Add your photos'),
        ),
        if (_uploaded > 0) ...[
          const SizedBox(height: Insets.sm),
          Text(
            'Thank you! $_uploaded photo${_uploaded == 1 ? '' : 's'} sent — '
            'they appear once the organisers approve them.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
            textAlign: TextAlign.center,
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(_error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.attention)),
        ],
        const SizedBox(height: Insets.lg),
        if (gallery.isNotEmpty)
          Text('Shared so far', style: theme.textTheme.titleMedium),
        const SizedBox(height: Insets.sm),
        Expanded(
          child: gallery.isEmpty
              ? Center(
                  child: Text(
                    'Be the first to add a photo.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.softInk),
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: Insets.sm,
                    mainAxisSpacing: Insets.sm,
                  ),
                  itemCount: gallery.length,
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AuthedImage(
                      api: widget.api,
                      path: gallery[index]['thumbnail_url'] as String? ?? '',
                      cacheWidth: 300,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _yearbookContribute(BuildContext context) {
    final theme = Theme.of(context);
    final gallery = (_campaign?['gallery'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final types = _enabledTypes;
    return ListView(
      children: [
        Text('Add to the event', style: theme.textTheme.headlineSmall),
        const SizedBox(height: Insets.sm),
        Text(
          'Choose what you want to send. Everything waits for organizer review before it appears in the event publication.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
        const SizedBox(height: Insets.lg),
        if (types.contains('photo_memory'))
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndUpload,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_busy ? 'Uploading…' : 'Add photos'),
          ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            if (types.contains('graduate_profile'))
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _submitStructured('graduate_profile'),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Graduate profile'),
              ),
            if (types.contains('dedication'))
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _submitStructured('dedication'),
                icon: const Icon(Icons.favorite_border, size: 18),
                label: const Text('Dedication'),
              ),
            if (types.contains('typed_signature'))
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _submitStructured('typed_signature'),
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: const Text('Signature'),
              ),
            if (types.contains('official_message'))
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _submitStructured('official_message'),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Official message'),
              ),
            if (types.contains('acknowledgement'))
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _submitStructured('acknowledgement'),
                icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                label: const Text('Acknowledgement'),
              ),
          ],
        ),
        if (_uploaded > 0) ...[
          const SizedBox(height: Insets.sm),
          Text(
            'Thank you! $_uploaded photo${_uploaded == 1 ? '' : 's'} sent for review.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.deepGreen),
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Text(_error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.attention)),
        ],
        const SizedBox(height: Insets.lg),
        if (gallery.isNotEmpty) ...[
          Text('Approved photos', style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: Insets.sm,
              mainAxisSpacing: Insets.sm,
            ),
            itemCount: gallery.length,
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AuthedImage(
                api: widget.api,
                path: gallery[index]['thumbnail_url'] as String? ?? '',
                cacheWidth: 300,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContributionDialog extends StatefulWidget {
  const _ContributionDialog({required this.type});

  final String type;

  @override
  State<_ContributionDialog> createState() => _ContributionDialogState();
}

class _ContributionDialogState extends State<_ContributionDialog> {
  final Map<String, TextEditingController> _controllers = {};
  String _signatureStyle = 'clean_script';

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      _controllers[field.$1] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<(String, String, int)> get _fields => switch (widget.type) {
        'graduate_profile' => const [
            ('full_name', 'Full name', 1),
            ('programme', 'Programme', 1),
            ('honours', 'Honours', 1),
            ('quote', 'Quote', 2),
            ('future_plans', 'Future plans', 2),
          ],
        'dedication' => const [
            ('message', 'Message', 5),
            ('from_name', 'From', 1),
            ('recipient_label', 'To', 1),
          ],
        'official_message' => const [
            ('title', 'Title', 1),
            ('message', 'Message', 7),
            ('author_name', 'Author name', 1),
            ('author_role', 'Author role', 1),
          ],
        'typed_signature' => const [
            ('text', 'Signature text', 1),
          ],
        'acknowledgement' => const [
            ('message', 'Message', 5),
            ('from_name', 'From', 1),
          ],
        _ => const [
            ('message', 'Message', 4),
          ],
      };

  String get _title => switch (widget.type) {
        'graduate_profile' => 'Graduate profile',
        'dedication' => 'Dedication',
        'official_message' => 'Official message',
        'typed_signature' => 'Typed signature',
        'acknowledgement' => 'Acknowledgement',
        _ => 'Submission',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in _fields) ...[
                TextField(
                  controller: _controllers[field.$1],
                  maxLines: field.$3,
                  decoration: appInput(field.$2),
                ),
                const SizedBox(height: Insets.md),
              ],
              if (widget.type == 'typed_signature')
                DropdownButtonFormField<String>(
                  initialValue: _signatureStyle,
                  decoration: appInput('Style'),
                  items: const [
                    DropdownMenuItem(
                        value: 'clean_script', child: Text('Clean script')),
                    DropdownMenuItem(
                        value: 'serif_caps', child: Text('Serif caps')),
                    DropdownMenuItem(
                        value: 'modern_sans', child: Text('Modern sans')),
                  ],
                  onChanged: (value) =>
                      setState(() => _signatureStyle = value ?? 'clean_script'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final payload = {
              for (final entry in _controllers.entries)
                if (entry.value.text.trim().isNotEmpty)
                  entry.key: entry.value.text.trim(),
              if (widget.type == 'typed_signature') 'style': _signatureStyle,
            };
            Navigator.of(context).pop(payload);
          },
          child: const Text('Send for review'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.softInk),
          const SizedBox(height: Insets.md),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: Insets.sm),
          Text(message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.softInk)),
        ],
      ),
    );
  }
}
