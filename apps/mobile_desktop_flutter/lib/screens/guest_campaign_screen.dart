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
      final result = await widget.api
          .registerGuest(widget.token, name: name, email: email);
      if (!mounted) return;
      if (result['needs_verification'] == true) {
        setState(() => _step = _Step.verify);
      } else {
        setState(() {
          _guestToken = result['guest_token'] as String?;
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
      final guestToken = await widget.api.verifyGuest(
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
        await widget.api
            .guestUpload(widget.token, guestToken: token, file: file);
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
        title: Text(_campaign?['title'] as String? ?? 'Guest uploads'),
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

  Widget _registerForm(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('You\'re invited to add photos',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: Insets.sm),
        Text(
          'Add your name and email so ${_campaign?['circle_name'] ?? 'the organisers'} '
          'know who shared each photo. No account needed.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.softInk),
        ),
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
          onPressed: _busy ? null : _register,
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
