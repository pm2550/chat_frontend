import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user.dart';
import 'crypto/password_hasher.dart';
import 'persistent_data_cache.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal()
      : _httpClient = null,
        _passwordHasher = PasswordHasher();

  @visibleForTesting
  AuthService.test({
    http.Client? httpClient,
    PasswordHasher? passwordHasher,
  })  : _httpClient = httpClient,
        _passwordHasher = passwordHasher ?? PasswordHasher();

  User? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _isLoading = false;
  bool _passwordUpgradeRequired = false;
  final http.Client? _httpClient;
  final PasswordHasher _passwordHasher;

  User? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;
  bool get passwordUpgradeRequired => _passwordUpgradeRequired;
  bool get passwordUpgradePending => _passwordUpgradeRequired;

  // Keys for SharedPreferences
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserData = 'user_data';

  /// Initialize auth state from local storage
  Future<bool> initialize({bool validateInBackground = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_keyAccessToken);
      _refreshToken = prefs.getString(_keyRefreshToken);
      final userData = prefs.getString(_keyUserData);

      if (_accessToken != null && userData != null) {
        final decodedUser = _decodeStoredUser(userData);
        if (decodedUser == null) {
          return false;
        }
        _currentUser = User.fromJson(decodedUser);
        notifyListeners();
        if (validateInBackground) {
          unawaited(_refreshCachedSessionIfNeeded());
        }
        return true;
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      await _clearAuthData();
    }
    return false;
  }

  Map<String, dynamic>? _decodeStoredUser(String userData) {
    try {
      final decoded = jsonDecode(userData);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is String) {
        final nested = jsonDecode(decoded);
        if (nested is Map<String, dynamic>) {
          return nested;
        }
      }
    } catch (e) {
      debugPrint('Stored user decode error: $e');
    }
    return null;
  }

  Future<bool> ensureAuthenticated() async {
    if (_accessToken != null && _currentUser != null) {
      return true;
    }

    return initialize();
  }

  Future<void> _refreshCachedSessionIfNeeded() async {
    if (_accessToken == null || _currentUser == null) return;
    if (await validateToken()) return;
    await refreshAccessToken();
  }

  /// Login with username and password.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _passwordUpgradeRequired = false;
    notifyListeners();

    try {
      final saltParams = await _fetchClientSaltParams(username);
      final payload = <String, dynamic>{'username': username};
      final usedLegacyPath = !saltParams.isClientArgon2;
      if (saltParams.isClientArgon2) {
        payload['clientHash'] = await _passwordHasher.hashWithSalt(
          password: password,
          salt: saltParams.salt,
          argon2Params: saltParams.argon2Params,
        );
      } else {
        payload['password'] = password;
      }

      final response = await _post(
        Uri.parse(ApiConstants.login),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(ApiConstants.requestTimeout);

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['code'] == 200) {
        await _persistLoginData(data['data']);
        _passwordUpgradeRequired = usedLegacyPath;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      if (response.statusCode == 409 ||
          data['message'] == 'PASSWORD_UPGRADE_REQUIRED') {
        final retry = await _post(
          Uri.parse(ApiConstants.login),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        ).timeout(ApiConstants.requestTimeout);
        final retryData = jsonDecode(utf8.decode(retry.bodyBytes));
        if (retry.statusCode == 200 && retryData['code'] == 200) {
          await _persistLoginData(retryData['data']);
          _passwordUpgradeRequired = true;
          _isLoading = false;
          notifyListeners();
          return true;
        }
        _passwordUpgradeRequired = false;
      }
    } catch (e) {
      debugPrint('Login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> _persistLoginData(dynamic responseData) async {
    _accessToken = responseData['accessToken'] ?? responseData['token'];
    _refreshToken = responseData['refreshToken'];
    _currentUser = User.fromJson(responseData['user']);
    await _saveAuthData();
  }

  /// Register new account
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    String? phone,
    String? displayName,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _post(
        Uri.parse(ApiConstants.register),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          ...await _newPasswordBundle(password),
          if (phone != null) 'phone': phone,
          if (displayName != null) 'displayName': displayName,
        }),
      ).timeout(ApiConstants.requestTimeout);

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      _isLoading = false;
      notifyListeners();

      if (response.statusCode == 200 && data['code'] == 200) {
        return {'success': true, 'message': data['message'] ?? '注册成功'};
      } else {
        return {'success': false, 'message': data['message'] ?? '注册失败'};
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return {'success': false, 'message': '网络错误: $e'};
    }
  }

  Future<ClientSaltParams> _fetchClientSaltParams(String username) async {
    final uri = Uri.parse(ApiConstants.clientSaltParams).replace(
      queryParameters: {'username': username},
    );
    final response = await _get(uri, headers: {'Accept': 'application/json'})
        .timeout(ApiConstants.requestTimeout);
    if (response.statusCode != 200) {
      throw Exception('无法获取密码参数');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw Exception('密码参数格式错误');
    }
    return ClientSaltParams(
      salt: data['salt']?.toString() ?? '',
      argon2Params: data['argon2Params']?.toString() ??
          PasswordHasher.defaultArgon2Params,
      scheme: data['scheme']?.toString() ?? PasswordHasher.legacyScheme,
    );
  }

  Future<Map<String, String>> _newPasswordBundle(String password) async {
    final hashed = await _passwordHasher.hashNewPassword(password);
    return {
      'clientHash': hashed.clientHash,
      'clientSalt': hashed.clientSalt,
      'argon2Params': hashed.argon2Params,
    };
  }

  /// Refresh access token using refresh token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await _post(
        Uri.parse(ApiConstants.refreshToken),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_refreshToken',
        },
      ).timeout(ApiConstants.requestTimeout);

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['code'] == 200) {
        final responseData = data['data'];
        _accessToken = responseData['accessToken'] ?? responseData['token'];
        if (responseData['refreshToken'] != null) {
          _refreshToken = responseData['refreshToken'];
        }
        _currentUser = User.fromJson(responseData['user']);
        await _saveAuthData();
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Token refresh error: $e');
    }
    return false;
  }

  /// Validate current token
  Future<bool> validateToken() async {
    if (_accessToken == null) return false;

    try {
      final response = await _get(
        Uri.parse(ApiConstants.validateToken),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(ApiConstants.requestTimeout);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      if (_accessToken != null) {
        await _post(
          Uri.parse(ApiConstants.logout),
          headers: {'Authorization': 'Bearer $_accessToken'},
        ).timeout(ApiConstants.requestTimeout);
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      await _clearAuthData();
      notifyListeners();
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? email,
    String? bio,
    String? phone,
  }) async {
    if (_accessToken == null) return false;

    try {
      final response = await _put(
        Uri.parse(ApiConstants.userProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          if (displayName != null) 'displayName': displayName,
          if (email != null) 'email': email,
          if (bio != null) 'bio': bio,
          if (phone != null) 'phone': phone,
        }),
      ).timeout(ApiConstants.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['data'] != null) {
          _currentUser = User.fromJson(data['data']);
          await _saveAuthData();
          notifyListeners();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Profile update error: $e');
    }
    return false;
  }

  /// Replace cached current user after profile/avatar updates.
  Future<void> replaceCurrentUser(User user) async {
    _currentUser = user;
    await _saveAuthData();
    notifyListeners();
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final username = _currentUser?.username;
    if (username == null || username.isEmpty) {
      throw Exception('请先登录');
    }
    final saltParams = await _fetchClientSaltParams(username);
    final body = <String, dynamic>{
      ...await _newPasswordChangeBundle(newPassword)
    };
    if (saltParams.isClientArgon2) {
      body['oldClientHash'] = await _passwordHasher.hashWithSalt(
        password: oldPassword,
        salt: saltParams.salt,
        argon2Params: saltParams.argon2Params,
      );
    } else {
      body['oldPassword'] = oldPassword;
    }
    final response = await authenticatedRequest(
      'POST',
      ApiConstants.profilePassword,
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body));
    }
    _passwordUpgradeRequired = false;
    notifyListeners();
  }

  Future<Map<String, String>> _newPasswordChangeBundle(String password) async {
    final hashed = await _passwordHasher.hashNewPassword(password);
    return {
      'newClientHash': hashed.clientHash,
      'newClientSalt': hashed.clientSalt,
      'newArgon2Params': hashed.argon2Params,
    };
  }

  /// Make authenticated API request with auto token refresh
  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    headers ??= {};
    headers['Authorization'] = 'Bearer $_accessToken';
    headers['Content-Type'] = 'application/json';

    http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _get(Uri.parse(url), headers: headers)
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'POST':
        response = await _post(Uri.parse(url),
                headers: headers,
                body: body is String ? body : jsonEncode(body))
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'PUT':
        response = await _put(Uri.parse(url),
                headers: headers,
                body: body is String ? body : jsonEncode(body))
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'DELETE':
        response = await _delete(Uri.parse(url), headers: headers)
            .timeout(ApiConstants.requestTimeout);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // Auto refresh on authentication failures. Some Spring Security paths
    // return 403 instead of 401 for expired or malformed JWTs.
    if (_shouldRefreshFor(response)) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        headers['Authorization'] = 'Bearer $_accessToken';
        switch (method.toUpperCase()) {
          case 'GET':
            response = await _get(Uri.parse(url), headers: headers)
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'POST':
            response = await _post(Uri.parse(url),
                    headers: headers,
                    body: body is String ? body : jsonEncode(body))
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'PUT':
            response = await _put(Uri.parse(url),
                    headers: headers,
                    body: body is String ? body : jsonEncode(body))
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'DELETE':
            response = await _delete(Uri.parse(url), headers: headers)
                .timeout(ApiConstants.requestTimeout);
            break;
        }
      }
    }

    return response;
  }

  bool _shouldRefreshFor(http.Response response) {
    if (_refreshToken == null) return false;
    return response.statusCode == 401 ||
        (response.statusCode == 403 && _isAuthenticationFailure(response));
  }

  @visibleForTesting
  bool debugIsAuthenticationFailure(http.Response response) =>
      _isAuthenticationFailure(response);

  bool _isAuthenticationFailure(http.Response response) {
    if (response.statusCode == 401) return true;
    if (response.statusCode != 403) return false;

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error']?.toString().toLowerCase() ?? '';
        final message = decoded['message']?.toString().toLowerCase() ?? '';
        return error.contains('jwt') ||
            error.contains('token') ||
            error.contains('authentication') ||
            message.contains('jwt') ||
            message.contains('token') ||
            message.contains('authentication');
      }
    } catch (_) {
      // Plain "Forbidden" can be a normal authorization failure and must not
      // wipe the whole local session.
    }
    final body = response.body.trim().toLowerCase();
    return body.contains('jwt') ||
        body.contains('token') ||
        body.contains('authentication');
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ?? decoded['error'] ?? '请求失败').toString();
      }
    } catch (_) {
      // Use generic error below.
    }
    return '请求失败';
  }

  Future<http.Response> _get(
    Uri url, {
    Map<String, String>? headers,
  }) {
    final client = _httpClient;
    return client == null
        ? http.get(url, headers: headers)
        : client.get(url, headers: headers);
  }

  Future<http.Response> _post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final client = _httpClient;
    return client == null
        ? http.post(url, headers: headers, body: body)
        : client.post(url, headers: headers, body: body);
  }

  Future<http.Response> _put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final client = _httpClient;
    return client == null
        ? http.put(url, headers: headers, body: body)
        : client.put(url, headers: headers, body: body);
  }

  Future<http.Response> _delete(
    Uri url, {
    Map<String, String>? headers,
  }) {
    final client = _httpClient;
    return client == null
        ? http.delete(url, headers: headers)
        : client.delete(url, headers: headers);
  }

  /// Save auth data to SharedPreferences
  Future<void> _saveAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString(_keyAccessToken, _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    }
    if (_currentUser != null) {
      await prefs.setString(_keyUserData, jsonEncode(_currentUser!.toJson()));
    }
  }

  /// Clear auth data from SharedPreferences
  Future<void> _clearAuthData() async {
    final previousUserId = _currentUser?.id;
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
    if (previousUserId != null) {
      await PersistentDataCache.clearUser(previousUserId);
    }
  }

  Future<void> clearLocalSession() async {
    await _clearAuthData();
    notifyListeners();
  }
}
