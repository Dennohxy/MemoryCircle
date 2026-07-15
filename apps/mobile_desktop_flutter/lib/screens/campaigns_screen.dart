import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/paper_card.dart';
import 'flip_album_screen.dart';

/// Owner tool for time-limited, no-login guest upload links (events/campaigns).
class CampaignsView extends StatefulWidget {
  const CampaignsView({super.key, required this.api, required this.circle});

  final ApiClient api;
  final Circle circle;

  @override
  State<CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends State<CampaignsView> {
  late Future<List<GuestCampaign>> _campaigns =
      widget.api.listCampaigns(widget.circle.id);

  void _refresh() =>
      setState(() => _campaigns = widget.api.listCampaigns(widget.circle.id));

  Future<void> _create() async {
    final input = await showDialog<({String title, int? days, bool verify})>(
      context: context,
      builder: (_) => const _CreateCampaignDialog(),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.createCampaign(
        widget.circle.id,
        title: input.title,
        expiresAt: input.days == null
            ? null
            : DateTime.now().add(Duration(days: input.days!)),
        requireEmailVerify: input.verify,
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(
        content: Text('Guest upload link created. Share it with your guests.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _createYearbook() async {
    final input = await showDialog<
        ({
          String title,
          String university,
          String faculty,
          String cohort,
          String date,
          int? days,
          bool verify
        })>(
      context: context,
      builder: (_) => const _CreateYearbookDialog(),
    );
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.createGraduationCampaign(
        widget.circle.id,
        title: input.title,
        expiresAt: input.days == null
            ? null
            : DateTime.now().add(Duration(days: input.days!)),
        requireEmailVerify: input.verify,
        details: {
          'university': input.university,
          'faculty': input.faculty,
          'cohort': input.cohort,
          'graduation_date': input.date,
        },
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(
        content: Text('Event campaign created. Add branding, then publish it.'),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _share(GuestCampaign campaign) async {
    final message = 'Add your photos to "${campaign.title}" on Omoide no Wa — '
        'no account needed:\n${campaign.shareUrl}';
    try {
      await Share.share(message);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: campaign.shareUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied — paste it anywhere.')),
        );
      }
    }
  }

  Future<void> _extend(GuestCampaign campaign) async {
    final messenger = ScaffoldMessenger.of(context);
    final base = (campaign.expiresAt != null &&
            campaign.expiresAt!.isAfter(DateTime.now()))
        ? campaign.expiresAt!
        : DateTime.now();
    try {
      await widget.api.updateCampaign(widget.circle.id, campaign.id,
          expiresAt: base.add(const Duration(days: 7)));
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Open for another 7 days.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _revoke(GuestCampaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this link?'),
        content: Text('Guests will no longer be able to open or upload to '
            '"${campaign.title}".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Close link')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.revokeCampaign(widget.circle.id, campaign.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Link closed.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _uploadLogo(GuestCampaign campaign) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final studio = await widget.api.campaignStudio(widget.circle.id, campaign.id);
      final theme = studio['theme'] as Map<String, dynamic>?;
      final presetId = theme?['id'] as int?;
      if (presetId == null) {
        throw ApiException('This campaign does not have a theme preset yet.');
      }
      await widget.api.uploadBrandAsset(
        widget.circle.id,
        presetId,
        kind: 'logo',
        file: result.files.first,
        rightsConfirmed: true,
      );
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Logo added to the yearbook theme.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _publish(GuestCampaign campaign) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.publishCampaign(widget.circle.id, campaign.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Yearbook link is live for guests.')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _generateYearbook(GuestCampaign campaign) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final album = await widget.api.generateYearbook(widget.circle.id, campaign.id);
      if (!mounted) return;
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Yearbook generated.')));
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlipAlbumScreen(
          api: widget.api,
          circleId: widget.circle.id,
          album: album,
        ),
      ));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _reviewSubmissions(GuestCampaign campaign) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ContributionReviewSheet(
        api: widget.api,
        circleId: widget.circle.id,
        campaign: campaign,
      ),
    );
    if (mounted) _refresh();
  }

  String _statusLine(GuestCampaign c) {
    if (c.revoked) return 'Closed';
    if (c.expiresAt == null) return 'Open · no end date';
    final left = c.expiresAt!.difference(DateTime.now()).inDays;
    if (left < 0) return 'Ended ${-left} day${-left == 1 ? '' : 's'} ago';
    return 'Open · ends in $left day${left == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<GuestCampaign>>(
      future: _campaigns,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(message: '${snapshot.error}', onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const LoadingState(message: 'Loading your guest links...');
        }
        final campaigns = snapshot.data!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(Insets.md),
              children: [
                Text(
                  'Create a link so guests can upload photos to an event — with '
                  'no account. Uploads wait for your approval before appearing.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.softInk),
                ),
                const SizedBox(height: Insets.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _createYearbook,
                        icon: const Icon(Icons.school_outlined),
                        label: const Text('New event campaign'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add_link),
                        label: const Text('Photo collection link'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Insets.md),
                if (campaigns.isEmpty)
                  const EmptyState(
                    icon: Icons.qr_code_2_outlined,
                    title: 'No guest links yet',
                    message:
                        'Create one for a wedding, reunion, or class event so '
                        'everyone can add their photos.',
                  )
                else
                  for (final campaign in campaigns) ...[
                    PaperCard(
                      padding: const EdgeInsets.all(Insets.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(campaign.title,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                              campaign.isYearbook
                                  ? 'Event campaign · Graduation yearbook · ${campaign.status}'
                                  : _statusLine(campaign),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: campaign.isOpen
                                    ? AppColors.deepGreen
                                    : AppColors.softInk,
                              )),
                          const SizedBox(height: Insets.sm),
                          Wrap(
                            spacing: Insets.sm,
                            runSpacing: Insets.xs,
                            children: [
                              if (!campaign.revoked)
                                OutlinedButton.icon(
                                  onPressed: () => _share(campaign),
                                  icon: const Icon(Icons.ios_share, size: 18),
                                  label: Text(campaign.isDraft
                                      ? 'Copy draft link'
                                      : 'Share link'),
                                ),
                              if (campaign.isYearbook) ...[
                                OutlinedButton.icon(
                                  onPressed: () => _uploadLogo(campaign),
                                  icon: const Icon(Icons.badge_outlined, size: 18),
                                  label: const Text('Add logo'),
                                ),
                                if (campaign.isDraft)
                                  FilledButton.icon(
                                    onPressed: () => _publish(campaign),
                                    icon: const Icon(Icons.public, size: 18),
                                    label: const Text('Publish'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => _reviewSubmissions(campaign),
                                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                                  label: const Text('Review submissions'),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _generateYearbook(campaign),
                                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                                  label: const Text('Generate yearbook'),
                                ),
                              ],
                              if (!campaign.revoked)
                                TextButton.icon(
                                  onPressed: () => _extend(campaign),
                                  icon: const Icon(Icons.more_time, size: 18),
                                  label: const Text('Extend 7 days'),
                                ),
                              if (!campaign.revoked)
                                TextButton.icon(
                                  onPressed: () => _revoke(campaign),
                                  icon: const Icon(Icons.link_off, size: 18),
                                  label: const Text('Close'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreateCampaignDialog extends StatefulWidget {
  const _CreateCampaignDialog();

  @override
  State<_CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<_CreateCampaignDialog> {
  final _titleController = TextEditingController();
  final _daysController = TextEditingController(text: '14');
  bool _verify = true;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _titleController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('New guest upload link'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: appInput('Event name',
                  hint: 'For example, "Amina & Kofi\'s wedding"'),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _daysController,
              keyboardType: TextInputType.number,
              decoration: appInput('Open for how many days?',
                  helper: 'Leave empty for no end date. You can extend later.'),
            ),
            const SizedBox(height: Insets.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _verify,
              onChanged: (v) => setState(() => _verify = v),
              title: const Text('Confirm guest emails with a code'),
              subtitle: const Text('Reduces spam (needs email set up).'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: canCreate
              ? () => Navigator.of(context).pop((
                    title: _titleController.text.trim(),
                    days: int.tryParse(_daysController.text.trim()),
                    verify: _verify,
                  ))
              : null,
          child: const Text('Create link'),
        ),
      ],
    );
  }
}

class _CreateYearbookDialog extends StatefulWidget {
  const _CreateYearbookDialog();

  @override
  State<_CreateYearbookDialog> createState() => _CreateYearbookDialogState();
}

class _CreateYearbookDialogState extends State<_CreateYearbookDialog> {
  final _titleController = TextEditingController();
  final _universityController = TextEditingController();
  final _facultyController = TextEditingController();
  final _cohortController = TextEditingController();
  final _dateController = TextEditingController();
  final _daysController = TextEditingController(text: '30');
  bool _verify = true;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _universityController.dispose();
    _facultyController.dispose();
    _cohortController.dispose();
    _dateController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _titleController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('New event campaign'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: appInput('Event title',
                    hint: 'Engineering Graduation 2026'),
              ),
              const SizedBox(height: Insets.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Event type: Graduation yearbook',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.softInk),
                ),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _universityController,
                decoration: appInput('Organization or university'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _facultyController,
                decoration: appInput('Faculty or programme'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _cohortController,
                decoration: appInput('Cohort', hint: 'Class of 2026'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _dateController,
                decoration: appInput('Graduation date'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                decoration: appInput('Open for how many days?'),
              ),
              const SizedBox(height: Insets.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _verify,
                onChanged: (v) => setState(() => _verify = v),
                title: const Text('Confirm guest emails with a code'),
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
          onPressed: canCreate
              ? () => Navigator.of(context).pop((
                    title: _titleController.text.trim(),
                    university: _universityController.text.trim(),
                    faculty: _facultyController.text.trim(),
                    cohort: _cohortController.text.trim(),
                    date: _dateController.text.trim(),
                    days: int.tryParse(_daysController.text.trim()),
                    verify: _verify,
                  ))
              : null,
          child: const Text('Create event'),
        ),
      ],
    );
  }
}

class _ContributionReviewSheet extends StatefulWidget {
  const _ContributionReviewSheet({
    required this.api,
    required this.circleId,
    required this.campaign,
  });

  final ApiClient api;
  final int circleId;
  final GuestCampaign campaign;

  @override
  State<_ContributionReviewSheet> createState() =>
      _ContributionReviewSheetState();
}

class _ContributionReviewSheetState extends State<_ContributionReviewSheet> {
  late Future<List<CampaignContribution>> _future =
      widget.api.listCampaignContributions(widget.circleId, widget.campaign.id);

  void _refresh() => setState(() {
        _future =
            widget.api.listCampaignContributions(widget.circleId, widget.campaign.id);
      });

  Future<void> _act(CampaignContribution contribution, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.moderateCampaignContribution(
        widget.circleId,
        widget.campaign.id,
        contribution.id,
        action,
      );
      _refresh();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _kindLabel(String value) => switch (value) {
        'photo_memory' => 'Photo',
        'graduate_profile' => 'Profile',
        'dedication' => 'Dedication',
        'official_message' => 'Official message',
        'typed_signature' => 'Signature',
        'acknowledgement' => 'Acknowledgement',
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Event submissions',
                        style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Expanded(
                child: FutureBuilder<List<CampaignContribution>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ErrorState(
                          message: '${snapshot.error}', onRetry: _refresh);
                    }
                    if (!snapshot.hasData) {
                      return const LoadingState(message: 'Loading submissions...');
                    }
                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No submissions yet',
                        message: 'Shared guest submissions will appear here.',
                      );
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Insets.sm),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return PaperCard(
                          padding: const EdgeInsets.all(Insets.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_kindLabel(item.type),
                                  style: theme.textTheme.labelLarge),
                              const SizedBox(height: 4),
                              Text(item.title,
                                  style: theme.textTheme.titleMedium,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text('${item.displayName} · ${item.status}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.softInk)),
                              if (item.status == 'pending' ||
                                  item.status == 'changes_requested') ...[
                                const SizedBox(height: Insets.sm),
                                Wrap(
                                  spacing: Insets.sm,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () => _act(item, 'approve'),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Approve'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _act(item, 'request-changes'),
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      label: const Text('Changes'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _act(item, 'reject'),
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Reject'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
