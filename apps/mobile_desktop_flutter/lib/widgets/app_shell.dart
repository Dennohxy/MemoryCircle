import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../screens/add_memory_screen.dart';
import '../screens/albums_screen.dart';
import '../screens/bulk_add_screen.dart';
import '../screens/circle_dashboard_screen.dart';
import '../screens/health_screen.dart';
import '../screens/members_screen.dart';
import '../screens/memories_review_screen.dart';
import '../screens/photos_screen.dart';
import '../screens/settings_screen.dart';
import 'error_state.dart';
import 'loading_state.dart';

/// The areas of one memory circle.
enum CircleSection {
  overview,
  addMemory,
  bulkAdd,
  photos,
  review,
  albums,
  members,
  health,
  settings,
}

/// Responsive scaffold for a circle: a quiet navigation rail on wide
/// screens, and a dashboard with pushed screens on phones.
class CircleShell extends StatefulWidget {
  const CircleShell({super.key, required this.api, required this.circle});

  final ApiClient api;
  final Circle circle;

  @override
  State<CircleShell> createState() => _CircleShellState();
}

class _CircleShellState extends State<CircleShell> {
  late Circle _circle = widget.circle;
  CircleSection _section = CircleSection.overview;
  CircleRole? _role;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    setState(() => _loadError = null);
    try {
      final members = await widget.api.listMembers(_circle.id);
      final me = widget.api.currentUser;
      var found = CircleRole.viewer;
      for (final member in members) {
        if (member.userId == me?.id) {
          found = member.role;
          break;
        }
      }
      if (mounted) setState(() => _role = found);
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    }
  }

  bool get _isWide => MediaQuery.sizeOf(context).width >= 960;

  List<({CircleSection section, String label, IconData icon})> _destinations(
    CircleRole role,
  ) =>
      [
        (
          section: CircleSection.overview,
          label: 'Overview',
          icon: Icons.cottage_outlined
        ),
        if (role.canContribute)
          (
            section: CircleSection.addMemory,
            label: 'Add a Memory',
            icon: Icons.add_photo_alternate_outlined
          ),
        if (role.canContribute)
          (
            section: CircleSection.bulkAdd,
            label: 'Add a Whole Album',
            icon: Icons.photo_library_outlined
          ),
        (
          section: CircleSection.photos,
          label: 'All Photos',
          icon: Icons.collections_outlined
        ),
        if (role.canReview)
          (
            section: CircleSection.review,
            label: 'Review Memories',
            icon: Icons.fact_check_outlined
          ),
        (
          section: CircleSection.albums,
          label: 'My Albums',
          icon: Icons.auto_stories_outlined
        ),
        (
          section: CircleSection.members,
          label: 'Family Members',
          icon: Icons.group_outlined
        ),
        (
          section: CircleSection.health,
          label: 'Album Health',
          icon: Icons.favorite_border
        ),
        (
          section: CircleSection.settings,
          label: 'Settings',
          icon: Icons.tune_outlined
        ),
      ];

  String _titleFor(CircleSection section) => switch (section) {
        CircleSection.overview => 'Overview',
        CircleSection.addMemory => 'Add a Memory',
        CircleSection.bulkAdd => 'Add a Whole Album',
        CircleSection.photos => 'All Photos',
        CircleSection.review => 'Review Memories',
        CircleSection.albums => 'My Albums',
        CircleSection.members => 'Family Members',
        CircleSection.health => 'Album Health',
        CircleSection.settings => 'Settings',
      };

  Widget _sectionBody(CircleSection section, CircleRole role) =>
      switch (section) {
        CircleSection.overview => CircleDashboardView(
            api: widget.api,
            circle: _circle,
            role: role,
            onOpen: _open,
          ),
        CircleSection.addMemory => AddMemoryView(
            api: widget.api,
            circle: _circle,
            onDone: _memorySent,
          ),
        CircleSection.bulkAdd => BulkAddView(
            api: widget.api,
            circle: _circle,
            role: role,
          ),
        CircleSection.photos => PhotosView(api: widget.api, circle: _circle),
        CircleSection.review =>
          MemoriesReviewView(api: widget.api, circle: _circle),
        CircleSection.albums =>
          AlbumsView(api: widget.api, circle: _circle, role: role),
        CircleSection.members =>
          MembersView(api: widget.api, circle: _circle, role: role),
        CircleSection.health => HealthView(api: widget.api, circle: _circle),
        CircleSection.settings => SettingsView(
            api: widget.api,
            circle: _circle,
            role: role,
            onUpdated: (updated) => setState(() => _circle = updated),
          ),
      };

  /// Opens a section: switches the rail selection on wide screens, pushes a
  /// screen on phones.
  void _open(CircleSection section) {
    final role = _role;
    if (role == null) return;
    if (_isWide) {
      setState(() => _section = section);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(_titleFor(section))),
        body: _sectionBody(section, role),
      ),
    ));
  }

  /// Called after a memory is sent for review.
  void _memorySent() {
    if (_isWide) {
      setState(() => _section = CircleSection.overview);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_circle.name)),
        body: ErrorState(message: _loadError!, onRetry: _loadRole),
      );
    }
    if (role == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_circle.name)),
        body: const LoadingState(message: 'Opening your circle…'),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    if (width < 960) {
      return Scaffold(
        appBar: AppBar(title: Text(_circle.name)),
        body: CircleDashboardView(
          api: widget.api,
          circle: _circle,
          role: role,
          onOpen: _open,
        ),
      );
    }

    final destinations = _destinations(role);
    var selectedIndex =
        destinations.indexWhere((entry) => entry.section == _section);
    if (selectedIndex == -1) selectedIndex = 0;
    final section = destinations[selectedIndex].section;
    final extended = width >= 1240;

    return Scaffold(
      appBar: AppBar(title: Text(_circle.name)),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _section = destinations[index].section),
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            backgroundColor: Colors.transparent,
            destinations: [
              for (final entry in destinations)
                NavigationRailDestination(
                  icon: Icon(entry.icon),
                  label: Text(entry.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _sectionBody(section, role)),
        ],
      ),
    );
  }
}
