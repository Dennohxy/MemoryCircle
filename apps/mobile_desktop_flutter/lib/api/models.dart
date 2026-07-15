/// Typed models for the Memory Circle FastAPI payloads.
library;

int _asInt(dynamic value) => value is int ? value : int.parse('$value');

String _asText(dynamic value) => value == null ? '' : '$value';

DateTime? _asDate(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value');

String initialsFor(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final second = parts.length > 1 ? parts.elementAt(1)[0] : '';
  return (first + second).toUpperCase();
}

/// "March 4, 2024" style dates for non-technical readers.
String formatFriendlyDate(DateTime? date) {
  if (date == null) return '';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: _asInt(json['id']),
        displayName: _asText(json['display_name']),
        email: _asText(json['email']),
      );

  final int id;
  final String displayName;
  final String email;

  String get initials => initialsFor(displayName);
}

/// Circle roles as the backend knows them, with the plain-language names the
/// app shows instead.
enum CircleRole {
  owner('owner', 'Owner', 'Manages the circle'),
  editor('editor', 'Editor', 'Edits circles, campaigns, and albums'),
  approver('approver', 'Reviewer', 'Can add memories to the album'),
  contributor('contributor', 'Contributor', 'Can send memories'),
  viewer('viewer', 'Viewer', 'Can view the album');

  const CircleRole(this.apiValue, this.label, this.blurb);

  final String apiValue;
  final String label;
  final String blurb;

  static CircleRole fromApi(String? value) => CircleRole.values.firstWhere(
        (role) => role.apiValue == value,
        orElse: () => CircleRole.viewer,
      );

  bool get canContribute => this != CircleRole.viewer;
  bool get canEdit => this == CircleRole.owner || this == CircleRole.editor;
  bool get canReview =>
      this == CircleRole.owner ||
      this == CircleRole.editor ||
      this == CircleRole.approver;
  bool get isOwner => this == CircleRole.owner;
}

class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.description,
    this.ownerUserId,
  });

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
        id: _asInt(json['id']),
        name: _asText(json['name']),
        description: _asText(json['description']),
        ownerUserId: json['owner_user_id'] == null
            ? null
            : _asInt(json['owner_user_id']),
      );

  final int id;
  final String name;
  final String description;
  final int? ownerUserId;

  String get initials => initialsFor(name);
}

class Member {
  const Member({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    this.user,
    this.lastActiveAt,
    this.inactivityTier = 'active',
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: _asInt(json['id']),
        userId: _asInt(json['user_id']),
        role: CircleRole.fromApi(json['role'] as String?),
        status: _asText(json['status']),
        user: json['user'] == null
            ? null
            : UserProfile.fromJson(json['user'] as Map<String, dynamic>),
        lastActiveAt: _asDate(json['last_active_at']),
        inactivityTier: _asText(json['inactivity_tier']).isEmpty
            ? 'active'
            : _asText(json['inactivity_tier']),
      );

  final int id;
  final int userId;
  final CircleRole role;
  final String status;
  final UserProfile? user;

  /// When this member last did anything in the circle.
  final DateTime? lastActiveAt;

  /// 'active', 'demote' (idle >=30 days), or 'flagged' (idle >=90 days).
  final String inactivityTier;

  bool get isFlaggedInactive => inactivityTier == 'flagged';

  String get displayName => user?.displayName ?? 'Family member';
  String get email => user?.email ?? '';
}

/// A pending request to merge one circle into another.
class MergeRequest {
  const MergeRequest({
    required this.id,
    required this.sourceCircleId,
    required this.targetCircleId,
    required this.status,
    this.sourceName = '',
    this.targetName = '',
  });

  factory MergeRequest.fromJson(Map<String, dynamic> json) => MergeRequest(
        id: _asInt(json['id']),
        sourceCircleId: _asInt(json['source_circle_id']),
        targetCircleId: _asInt(json['target_circle_id']),
        status: _asText(json['status']),
        sourceName: _asText((json['source'] as Map<String, dynamic>?)?['name']),
        targetName: _asText((json['target'] as Map<String, dynamic>?)?['name']),
      );

  final int id;
  final int sourceCircleId;
  final int targetCircleId;
  final String status;
  final String sourceName;
  final String targetName;
}

/// A time-limited link that lets non-logged-in guests upload photos.
class GuestCampaign {
  const GuestCampaign({
    required this.id,
    required this.token,
    required this.title,
    required this.shareUrl,
    required this.isOpen,
    required this.revoked,
    this.note = '',
    this.circleName = '',
    this.campaignType = 'photo_collection',
    this.status = 'published',
    this.details = const {},
    this.linkedAlbumId,
    this.expiresAt,
  });

  factory GuestCampaign.fromJson(Map<String, dynamic> json) => GuestCampaign(
        id: _asInt(json['id']),
        token: _asText(json['token']),
        title: _asText(json['title']),
        shareUrl: _asText(json['share_url']),
        isOpen: json['is_open'] == true,
        revoked: json['revoked'] == true,
        note: _asText(json['note']),
        circleName: _asText(json['circle_name']),
        campaignType: _asText(json['campaign_type']).isEmpty
            ? 'photo_collection'
            : _asText(json['campaign_type']),
        status:
            _asText(json['status']).isEmpty ? 'published' : _asText(json['status']),
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
        linkedAlbumId: json['linked_album_id'] == null
            ? null
            : _asInt(json['linked_album_id']),
        expiresAt: _asDate(json['expires_at']),
      );

  final int id;
  final String token;
  final String title;
  final String shareUrl;
  final bool isOpen;
  final bool revoked;
  final String note;
  final String circleName;
  final String campaignType;
  final String status;
  final Map<String, dynamic> details;
  final int? linkedAlbumId;
  final DateTime? expiresAt;

  bool get isYearbook => campaignType != 'photo_collection';
  bool get isDraft => status == 'draft';
}

class CampaignContribution {
  const CampaignContribution({
    required this.id,
    required this.type,
    required this.status,
    required this.payload,
    this.displayName = '',
    this.thumbnailUrl = '',
  });

  factory CampaignContribution.fromJson(Map<String, dynamic> json) =>
      CampaignContribution(
        id: _asInt(json['id']),
        type: _asText(json['contribution_type']),
        status: _asText(json['moderation_status']),
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
        displayName: _asText(json['display_name']),
        thumbnailUrl: _asText(json['thumbnail_url']),
      );

  final int id;
  final String type;
  final String status;
  final Map<String, dynamic> payload;
  final String displayName;
  final String thumbnailUrl;

  String get title {
    final fields = [
      payload['full_name'],
      payload['title'],
      payload['message'],
      payload['caption'],
      payload['text'],
    ];
    for (final value in fields) {
      final text = _asText(value);
      if (text.isNotEmpty) return text;
    }
    return displayName.isEmpty ? type : displayName;
  }
}

/// A registered person found via member search, with whether they are
/// already in the circle.
class DirectoryPerson {
  const DirectoryPerson({required this.user, required this.alreadyMember});

  factory DirectoryPerson.fromJson(Map<String, dynamic> json) =>
      DirectoryPerson(
        user: UserProfile.fromJson(json),
        alreadyMember: json['already_member'] == true,
      );

  final UserProfile user;
  final bool alreadyMember;
}

/// A circle found by name search, with whether the searcher is already a
/// member or has a pending/answered request.
class CircleSearchResult {
  const CircleSearchResult({
    required this.id,
    required this.name,
    required this.description,
    required this.isMember,
    this.requestStatus,
  });

  factory CircleSearchResult.fromJson(Map<String, dynamic> json) =>
      CircleSearchResult(
        id: _asInt(json['id']),
        name: _asText(json['name']),
        description: _asText(json['description']),
        isMember: json['is_member'] == true,
        requestStatus: json['request_status'] as String?,
      );

  final int id;
  final String name;
  final String description;
  final bool isMember;
  final String? requestStatus;

  bool get isPending => requestStatus == 'pending';
}

/// A pending request from someone asking to join a circle.
class JoinRequest {
  const JoinRequest({required this.id, this.user});

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
        id: _asInt(json['id']),
        user: json['user'] == null
            ? null
            : UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );

  final int id;
  final UserProfile? user;

  String get displayName => user?.displayName ?? 'Someone';
  String get email => user?.email ?? '';
}

/// A pending invitation for the signed-in person to join a circle.
class Invitation {
  const Invitation({
    required this.circleId,
    required this.circleName,
    required this.circleDescription,
    required this.role,
    required this.inviterName,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        circleId: _asInt(json['circle_id']),
        circleName: _asText(json['circle_name']),
        circleDescription: _asText(json['circle_description']),
        role: CircleRole.fromApi(json['role'] as String?),
        inviterName: _asText(json['inviter_name']),
      );

  final int circleId;
  final String circleName;
  final String circleDescription;
  final CircleRole role;
  final String inviterName;
}

class PhotoAsset {
  const PhotoAsset({
    required this.id,
    required this.thumbnailUrl,
    required this.displayUrl,
    required this.originalFilename,
    this.contentHash = '',
    this.captureDate,
  });

  factory PhotoAsset.fromJson(Map<String, dynamic> json) => PhotoAsset(
        id: _asInt(json['id']),
        thumbnailUrl: _asText(json['thumbnail_url']),
        displayUrl: _asText(json['display_url']),
        originalFilename: _asText(json['original_filename']),
        contentHash: _asText(json['content_hash']),
        captureDate: _asDate(json['capture_date']),
      );

  final int id;
  final String thumbnailUrl;
  final String displayUrl;
  final String originalFilename;
  final String contentHash;
  final DateTime? captureDate;
}

class ApprovalSendResult {
  const ApprovalSendResult({
    required this.sent,
    required this.alreadyPending,
    required this.notificationsQueued,
  });

  factory ApprovalSendResult.fromJson(Map<String, dynamic> json) =>
      ApprovalSendResult(
        sent: _asInt(json['sent'] ?? 0),
        alreadyPending: _asInt(json['already_pending'] ?? 0),
        notificationsQueued: _asInt(json['notifications_queued'] ?? 0),
      );

  final int sent;
  final int alreadyPending;
  final int notificationsQueued;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.circleId,
    this.targetType = '',
    this.targetId,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: _asInt(json['id']),
        title: _asText(json['title']),
        body: _asText(json['body']),
        type: _asText(json['type']),
        circleId: json['circle_id'] == null ? null : _asInt(json['circle_id']),
        targetType: _asText(json['target_type']),
        targetId: json['target_id'] == null ? null : _asInt(json['target_id']),
        createdAt: _asDate(json['created_at']),
      );

  final int id;
  final String title;
  final String body;
  final String type;
  final int? circleId;
  final String targetType;
  final int? targetId;
  final DateTime? createdAt;
}

class ApprovalProgress {
  const ApprovalProgress({
    required this.approvalsHave,
    required this.approvalsNeeded,
    required this.voterIds,
  });

  factory ApprovalProgress.fromJson(Map<String, dynamic>? json) =>
      ApprovalProgress(
        approvalsHave: _asInt(json?['approvals_have'] ?? 0),
        approvalsNeeded: _asInt(json?['approvals_needed'] ?? 0),
        voterIds: [
          for (final id in json?['voter_ids'] as List<dynamic>? ?? const [])
            _asInt(id),
        ],
      );

  final int approvalsHave;
  final int approvalsNeeded;
  final List<int> voterIds;

  bool hasVoted(int? userId) => userId != null && voterIds.contains(userId);
}

class Memory {
  const Memory({
    required this.id,
    required this.assetId,
    required this.caption,
    required this.story,
    required this.eventName,
    required this.locationText,
    required this.approvalStatus,
    required this.approval,
    this.memoryDate,
    this.submittedBy,
    this.asset,
  });

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
        id: _asInt(json['id']),
        assetId: _asInt(json['asset_id']),
        caption: _asText(json['caption']),
        story: _asText(json['story']),
        eventName: _asText(json['event_name']),
        locationText: _asText(json['location_text']),
        approvalStatus: _asText(json['approval_status']),
        approval: ApprovalProgress.fromJson(
            json['approval'] as Map<String, dynamic>?),
        memoryDate: _asDate(json['memory_date']),
        submittedBy:
            json['submitted_by'] == null ? null : _asInt(json['submitted_by']),
        asset: json['asset'] == null
            ? null
            : PhotoAsset.fromJson(json['asset'] as Map<String, dynamic>),
      );

  final int id;
  final int assetId;
  final String caption;
  final String story;
  final String eventName;
  final String locationText;
  final String approvalStatus;
  final ApprovalProgress approval;
  final DateTime? memoryDate;
  final int? submittedBy;
  final PhotoAsset? asset;

  /// "Graduation day · March 4, 2024 · Nairobi" style summary line.
  String get metaLine => [
        eventName,
        formatFriendlyDate(memoryDate),
        locationText,
      ].where((part) => part.isNotEmpty).join(' · ');
}

class UploadedPhoto {
  const UploadedPhoto({required this.asset, this.memory});

  factory UploadedPhoto.fromJson(Map<String, dynamic> json) => UploadedPhoto(
        asset: PhotoAsset.fromJson(json['asset'] as Map<String, dynamic>),
        memory: json['memory'] == null
            ? null
            : Memory.fromJson(json['memory'] as Map<String, dynamic>),
      );

  final PhotoAsset asset;
  final Memory? memory;
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.description,
    this.targetPhotoCount = 0,
    this.maxPhotoCount,
    this.coverMemoryId,
    this.memorySequence = const [],
    this.status = 'active',
    this.removal,
    this.pages,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: _asInt(json['id']),
        title: _asText(json['title']),
        description: _asText(json['description']),
        targetPhotoCount:
            _asInt(json['target_photo_count'] ?? json['max_photo_count'] ?? 0),
        maxPhotoCount: json['max_photo_count'] == null
            ? null
            : _asInt(json['max_photo_count']),
        coverMemoryId: json['cover_memory_id'] == null
            ? null
            : _asInt(json['cover_memory_id']),
        memorySequence: [
          for (final id
              in json['memory_sequence'] as List<dynamic>? ?? const [])
            _asInt(id),
        ],
        status: _asText(json['status']).isEmpty
            ? 'active'
            : _asText(json['status']),
        removal: json['removal'] == null
            ? null
            : AlbumRemoval.fromJson(json['removal'] as Map<String, dynamic>),
        pages: json['pages'] == null
            ? null
            : [
                for (final page in json['pages'] as List<dynamic>)
                  AlbumPage.fromJson(page as Map<String, dynamic>),
              ],
      );

  final int id;
  final String title;
  final String description;

  /// Effective album size; the family maximum (12 per member) when unset.
  final int targetPhotoCount;

  /// Album size ceiling: 12 photos per active circle member.
  final int? maxPhotoCount;
  final int? coverMemoryId;
  final List<int> memorySequence;
  final String status;
  final AlbumRemoval? removal;
  final List<AlbumPage>? pages;

  bool get isPendingRemoval => status == 'pending_removal';
}

/// Progress of an approval-gated album removal.
class AlbumRemoval {
  const AlbumRemoval({
    required this.approvalsHave,
    required this.approvalsNeeded,
    required this.voterIds,
    this.requestedBy,
  });

  factory AlbumRemoval.fromJson(Map<String, dynamic> json) => AlbumRemoval(
        approvalsHave: _asInt(json['approvals_have'] ?? 0),
        approvalsNeeded: _asInt(json['approvals_needed'] ?? 0),
        voterIds: [
          for (final id in json['voter_ids'] as List<dynamic>? ?? const [])
            _asInt(id),
        ],
        requestedBy:
            json['requested_by'] == null ? null : _asInt(json['requested_by']),
      );

  final int approvalsHave;
  final int approvalsNeeded;
  final List<int> voterIds;
  final int? requestedBy;

  bool hasVoted(int? userId) => userId != null && voterIds.contains(userId);
}

class AlbumPage {
  const AlbumPage({
    required this.id,
    required this.pageNumber,
    required this.layout,
  });

  factory AlbumPage.fromJson(Map<String, dynamic> json) => AlbumPage(
        id: _asInt(json['id']),
        pageNumber: _asInt(json['page_number']),
        layout: (json['layout_json'] as Map<String, dynamic>?) ?? const {},
      );

  final int id;
  final int pageNumber;
  final Map<String, dynamic> layout;
}

class SharePackage {
  const SharePackage({
    required this.id,
    required this.title,
    required this.note,
    required this.accessType,
    required this.allowDownloads,
    required this.includeCaptions,
    required this.status,
    required this.shareUrl,
    this.expiresAt,
    this.createdAt,
    this.revokedAt,
    this.viewedAt,
  });

  factory SharePackage.fromJson(Map<String, dynamic> json) => SharePackage(
        id: _asInt(json['id']),
        title: _asText(json['title']),
        note: _asText(json['note']),
        accessType: _asText(json['access_type']),
        allowDownloads: json['allow_downloads'] == true,
        includeCaptions: json['include_captions'] != false,
        status: _asText(json['status']),
        shareUrl: _asText(json['share_url']),
        expiresAt: _asDate(json['expires_at']),
        createdAt: _asDate(json['created_at']),
        revokedAt: _asDate(json['revoked_at']),
        viewedAt: _asDate(json['viewed_at']),
      );

  final int id;
  final String title;
  final String note;
  final String accessType;
  final bool allowDownloads;
  final bool includeCaptions;
  final String status;
  final String shareUrl;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? revokedAt;
  final DateTime? viewedAt;

  String get statusLabel => switch (status) {
        'active' => 'Active',
        'expired' => 'Expired',
        'revoked' => 'Revoked',
        'viewed' => 'Viewed',
        _ => status,
      };
}

class CircleHealth {
  const CircleHealth({
    required this.assetCount,
    required this.missingCount,
  });

  factory CircleHealth.fromJson(Map<String, dynamic> json) => CircleHealth(
        assetCount: _asInt(json['asset_count'] ?? 0),
        missingCount:
            (json['missing_asset_ids'] as List<dynamic>? ?? const []).length,
      );

  final int assetCount;
  final int missingCount;

  bool get healthy => missingCount == 0;
}
