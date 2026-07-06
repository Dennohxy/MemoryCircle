import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Backend base URL. Override at build time with
/// `--dart-define=API_BASE=http://127.0.0.1:8000`.
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8000',
);

/// A request failure with a message that is safe to show to family members.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

const _offlineMessage =
    'We could not reach Memory Circle right now. Check your connection and try again in a moment.';

class ApiClient {
  ApiClient({this.baseUrl = apiBase});

  final String baseUrl;

  String? _token;
  UserProfile? currentUser;

  /// Called once when the saved sign-in stops being accepted by the server,
  /// so the app can return to the sign-in screen gracefully.
  void Function()? onSessionExpired;

  static const _tokenPref = 'memory_circle_token';
  static const _userPref = 'memory_circle_user';
  static const _emailPref = 'memory_circle_last_email';

  // Small in-memory image cache, bounded so long sessions do not grow
  // unbounded. Insertion order is used as a simple least-recently-used list.
  static const _maxCachedImages = 150;
  final Map<String, Uint8List> _imageCache = {};
  final Map<String, Future<Uint8List>> _imageRequests = {};

  bool get isSignedIn => _token != null;

  Map<String, String> get _authHeaders =>
      {if (_token != null) 'Authorization': 'Bearer $_token'};

  Map<String, String> get _jsonHeaders =>
      {'Content-Type': 'application/json', ..._authHeaders};

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<http.Response> _run(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on http.ClientException {
      throw ApiException(_offlineMessage);
    }
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    if (response.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        body = null;
      }
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && _token != null) {
        // The saved sign-in is no longer valid; let the app bounce back to
        // the sign-in screen instead of failing on every request.
        _token = null;
        currentUser = null;
        onSessionExpired?.call();
      }
      throw ApiException(
        _friendlyError(body, response.statusCode),
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  String _friendlyError(dynamic body, int statusCode) {
    final detail = body is Map<String, dynamic> ? body['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    switch (statusCode) {
      case 401:
        return 'Your sign-in has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do that in this circle.';
      case 404:
        return 'We could not find that. It may have been removed.';
      case 422:
        return 'Some of the information looks incomplete. Please check the form and try again.';
      default:
        return 'Something went wrong on our side. Please try again.';
    }
  }

  Future<dynamic> _get(String path) async =>
      _decode(await _run(() => http.get(_uri(path), headers: _authHeaders)));

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async =>
      _decode(await _run(() => http.post(
            _uri(path),
            headers: _jsonHeaders,
            body: jsonEncode(body ?? <String, dynamic>{}),
          )));

  Future<dynamic> _patchJson(String path, Map<String, dynamic> body) async =>
      _decode(await _run(() => http.patch(
            _uri(path),
            headers: _jsonHeaders,
            body: jsonEncode(body),
          )));

  // ---- Auth ----

  Future<UserProfile> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final data = await _post('/auth/register', {
      'display_name': displayName,
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    return _startSession(data);
  }

  Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final data = await _post('/auth/login', {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    return _startSession(data);
  }

  Future<UserProfile> _startSession(Map<String, dynamic> data) async {
    _token = data['token'] as String?;
    _imageCache.clear();
    final userMap = data['user'] as Map<String, dynamic>;
    currentUser = UserProfile.fromJson(userMap);
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_tokenPref, _token!);
    await prefs.setString(_userPref, jsonEncode(userMap));
    await prefs.setString(_emailPref, currentUser!.email);
    return currentUser!;
  }

  /// Restores the saved sign-in from this device, if any, so people do not
  /// have to log in every time they open the app. No network call is made;
  /// an expired token is detected on first use via [onSessionExpired].
  Future<UserProfile?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenPref);
    final userJson = prefs.getString(_userPref);
    if (token == null || userJson == null) return null;
    try {
      currentUser =
          UserProfile.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
    _token = token;
    return currentUser;
  }

  /// The email used for the last sign-in on this device, for prefilling.
  Future<String?> lastEmail() async =>
      (await SharedPreferences.getInstance()).getString(_emailPref);

  Future<void> signOut() async {
    _token = null;
    currentUser = null;
    _imageCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPref);
    await prefs.remove(_userPref);
  }

  // ---- Circles ----

  Future<List<Circle>> listCircles() async => [
        for (final item in await _get('/circles') as List<dynamic>)
          Circle.fromJson(item as Map<String, dynamic>),
      ];

  Future<Circle> createCircle({
    required String name,
    String description = '',
  }) async =>
      Circle.fromJson(await _post('/circles', {
        'name': name,
        'description': description,
      }) as Map<String, dynamic>);

  Future<Circle> updateCircle(
    int circleId, {
    String? name,
    String? description,
  }) async =>
      Circle.fromJson(await _patchJson('/circles/$circleId', {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      }) as Map<String, dynamic>);

  // ---- Members ----

  Future<List<Member>> listMembers(int circleId) async => [
        for (final item
            in await _get('/circles/$circleId/members') as List<dynamic>)
          Member.fromJson(item as Map<String, dynamic>),
      ];

  Future<Member> updateMemberRole(
    int circleId,
    int memberId,
    CircleRole role,
  ) async =>
      Member.fromJson(await _patchJson(
        '/circles/$circleId/members/$memberId',
        {'role': role.apiValue},
      ) as Map<String, dynamic>);

  Future<Member> inviteMember(
    int circleId, {
    required String email,
    String displayName = '',
    CircleRole role = CircleRole.contributor,
  }) async =>
      Member.fromJson(await _post('/circles/$circleId/invites', {
        'email': email,
        'display_name': displayName,
        'role': role.apiValue,
      }) as Map<String, dynamic>);

  // ---- Photos ----

  static const _imageSubtypes = {
    'jpg': 'jpeg',
    'jpeg': 'jpeg',
    'png': 'png',
    'webp': 'webp',
  };

  MediaType _imageMediaType(String filename) {
    final dot = filename.lastIndexOf('.');
    final extension =
        dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
    final subtype = _imageSubtypes[extension];
    if (subtype == null) {
      throw ApiException(
        'That file type is not supported. Try a JPEG, PNG, or WebP image.',
      );
    }
    return MediaType('image', subtype);
  }

  Future<PhotoAsset> uploadPhoto(int circleId, PlatformFile file) async {
    final mediaType = _imageMediaType(file.name);
    final request = http.MultipartRequest(
      'POST',
      _uri('/circles/$circleId/assets/upload'),
    );
    request.headers.addAll(_authHeaders);
    if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: mediaType,
      ));
    } else if (file.path != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path!,
        filename: file.name,
        contentType: mediaType,
      ));
    } else {
      throw ApiException(
          'We could not read that photo. Please choose it again.');
    }
    final response =
        await _run(() async => http.Response.fromStream(await request.send()));
    return PhotoAsset.fromJson(_decode(response) as Map<String, dynamic>);
  }

  /// Returns the circle's existing photos matching the given SHA-256
  /// fingerprints, keyed by hash, so identical photos are linked instead of
  /// uploaded again.
  Future<Map<String, PhotoAsset>> matchPhotos(
    int circleId,
    List<String> hashes,
  ) async {
    final data = await _post('/circles/$circleId/assets/match', {
      'hashes': hashes,
    }) as Map<String, dynamic>;
    final matches = data['matches'] as Map<String, dynamic>? ?? const {};
    return {
      for (final entry in matches.entries)
        entry.key: PhotoAsset.fromJson(entry.value as Map<String, dynamic>),
    };
  }

  /// Fetches an image with the Authorization header so protected thumbnails
  /// and display images can be shown via `Image.memory`. Bytes are cached in
  /// memory for the session.
  Future<Uint8List> imageBytes(String path) {
    final cached = _imageCache.remove(path);
    if (cached != null) {
      _imageCache[path] = cached; // Mark as most recently used.
      return Future.value(cached);
    }
    return _imageRequests.putIfAbsent(path, () => _fetchImage(path));
  }

  Future<Uint8List> _fetchImage(String path) async {
    try {
      final response =
          await _run(() => http.get(_uri(path), headers: _authHeaders));
      if (response.statusCode >= 400) {
        throw ApiException(
          'This photo could not be loaded.',
          statusCode: response.statusCode,
        );
      }
      final bytes = response.bodyBytes;
      _imageCache[path] = bytes;
      while (_imageCache.length > _maxCachedImages) {
        _imageCache.remove(_imageCache.keys.first); // Evict least recent.
      }
      return bytes;
    } finally {
      _imageRequests.remove(path);
    }
  }

  // ---- Memories ----

  Future<Memory> createMemory(
    int circleId, {
    required int assetId,
    required String caption,
    String story = '',
    String eventName = '',
    DateTime? memoryDate,
    String locationText = '',
  }) async =>
      Memory.fromJson(await _post('/circles/$circleId/memories', {
        'asset_id': assetId,
        'caption': caption,
        'story': story,
        'event_name': eventName,
        if (memoryDate != null) 'memory_date': memoryDate.toIso8601String(),
        'location_text': locationText,
        'approval_status': 'pending',
      }) as Map<String, dynamic>);

  Future<List<Memory>> listMemories(int circleId, {String? status}) async {
    final query = status == null ? '' : '?status=$status';
    return [
      for (final item
          in await _get('/circles/$circleId/memories$query') as List<dynamic>)
        Memory.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Memory> updateMemory(
    int circleId,
    int memoryId,
    Map<String, dynamic> edits,
  ) async =>
      Memory.fromJson(await _patchJson(
        '/circles/$circleId/memories/$memoryId',
        edits,
      ) as Map<String, dynamic>);

  /// Approves a memory, optionally applying caption/story edits in the same
  /// step (the approve endpoint accepts a patch body).
  Future<Memory> approveMemory(
    int circleId,
    int memoryId, {
    Map<String, dynamic>? edits,
  }) async =>
      Memory.fromJson(await _post(
        '/circles/$circleId/memories/$memoryId/approve',
        edits ?? const {},
      ) as Map<String, dynamic>);

  Future<Memory> rejectMemory(int circleId, int memoryId) async =>
      Memory.fromJson(await _post(
        '/circles/$circleId/memories/$memoryId/reject',
      ) as Map<String, dynamic>);

  Future<Memory> requestChanges(int circleId, int memoryId) async =>
      Memory.fromJson(await _post(
        '/circles/$circleId/memories/$memoryId/request-changes',
      ) as Map<String, dynamic>);

  // ---- Albums ----

  Future<List<Album>> listAlbums(int circleId) async => [
        for (final item
            in await _get('/circles/$circleId/albums') as List<dynamic>)
          Album.fromJson(item as Map<String, dynamic>),
      ];

  Future<Album> createAlbum(
    int circleId, {
    required String title,
    String description = '',
  }) async =>
      Album.fromJson(await _post('/circles/$circleId/albums', {
        'title': title,
        'description': description,
      }) as Map<String, dynamic>);

  Future<void> generateAlbumPages(int circleId, int albumId) async =>
      _post('/circles/$circleId/albums/$albumId/pages/generate');

  Future<Album> getAlbum(int circleId, int albumId) async => Album.fromJson(
        await _get('/circles/$circleId/albums/$albumId')
            as Map<String, dynamic>,
      );

  Future<SharePackage> createSharePackage(
    int circleId,
    int albumId, {
    String? title,
    String note = '',
    String accessType = 'expires_at',
    DateTime? expiresAt,
    bool allowDownloads = false,
    bool includeCaptions = true,
  }) async =>
      SharePackage.fromJson(await _post(
        '/circles/$circleId/albums/$albumId/share-packages',
        {
          if (title != null) 'title': title,
          'note': note,
          'access_type': accessType,
          if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
          'allow_downloads': allowDownloads,
          'include_captions': includeCaptions,
        },
      ) as Map<String, dynamic>);

  Future<List<SharePackage>> listSharePackages(
    int circleId,
    int albumId,
  ) async =>
      [
        for (final item in await _get(
          '/circles/$circleId/albums/$albumId/share-packages',
        ) as List<dynamic>)
          SharePackage.fromJson(item as Map<String, dynamic>),
      ];

  Future<SharePackage> revokeSharePackage(
    int circleId,
    int albumId,
    int packageId,
  ) async =>
      SharePackage.fromJson(await _post(
        '/circles/$circleId/albums/$albumId/share-packages/$packageId/revoke',
      ) as Map<String, dynamic>);

  // ---- Health ----

  Future<CircleHealth> circleHealth(int circleId) async =>
      CircleHealth.fromJson(
        await _get('/circles/$circleId/health') as Map<String, dynamic>,
      );
}
