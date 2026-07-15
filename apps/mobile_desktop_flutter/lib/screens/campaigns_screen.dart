import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app/theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/loading_state.dart';
import '../widgets/paper_card.dart';

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
                  child: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_link),
                    label: const Text('New guest link'),
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
                          Text(_statusLine(campaign),
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
                                  label: const Text('Share link'),
                                ),
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
