import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  User? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  // Keys for SharedPreferences
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserData = 'user_data';

  /// Initialize auth state from local storage
  Future<bool> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_keyAccessToken);
      _refreshToken = prefs.getString(_keyRefreshToken);
      final userData = prefs.getString(_keyUserData);

      if (_accessToken != null && userData != null) {
        _currentUser = User.fromJson(jsonDecode(userData));

        // Validate token with server
        final isValid = await validateToken();
        if (!isValid) {
          // Try refresh
          final refreshed = await refreshAccessToken();
          if (!refreshed) {
            await _clearAuthData();
            return false;
          }
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      await _clearAuthData();
    }
    return false;
  }

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(ApiConstants.requestTimeout);

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200 && data['code'] == 200) {
        final responseData = data['data'];
        _accessToken = responseData['accessToken'] ?? responseData['token'];
        _refreshToken = responseData['refreshToken'];
        _currentUser = User.fromJson(responseData['user']);

        await _saveAuthData();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Login error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
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
      final response = await http.post(
        Uri.parse(ApiConstants.register),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'email': email,
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

  /// Refresh access token using refresh token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await http.post(
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
      final response = await http.get(
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
        await http.post(
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
    String? bio,
    String? phone,
  }) async {
    if (_accessToken == null) return false;

    try {
      final response = await http.put(
        Uri.parse(ApiConstants.userProfile),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
        body: jsonEncode({
          if (displayName != null) 'displayName': displayName,
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
        response = await http.get(Uri.parse(url), headers: headers)
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'POST':
        response = await http.post(Uri.parse(url), headers: headers,
            body: body is String ? body : jsonEncode(body))
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'PUT':
        response = await http.put(Uri.parse(url), headers: headers,
            body: body is String ? body : jsonEncode(body))
            .timeout(ApiConstants.requestTimeout);
        break;
      case 'DELETE':
        response = await http.delete(Uri.parse(url), headers: headers)
            .timeout(ApiConstants.requestTimeout);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // Auto refresh on 401
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        headers['Authorization'] = 'Bearer $_accessToken';
        switch (method.toUpperCase()) {
          case 'GET':
            response = await http.get(Uri.parse(url), headers: headers)
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'POST':
            response = await http.post(Uri.parse(url), headers: headers,
                body: body is String ? body : jsonEncode(body))
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'PUT':
            response = await http.put(Uri.parse(url), headers: headers,
                body: body is String ? body : jsonEncode(body))
                .timeout(ApiConstants.requestTimeout);
            break;
          case 'DELETE':
            response = await http.delete(Uri.parse(url), headers: headers)
                .timeout(ApiConstants.requestTimeout);
            break;
        }
      }
    }

    return response;
  }

  /// Save auth data to SharedPreferences
  Future<void> _saveAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) prefs.setString(_keyAccessToken, _accessToken!);
    if (_refreshToken != null) prefs.setString(_keyRefreshToken, _refreshToken!);
    if (_currentUser != null) prefs.setString(_keyUserData, jsonEncode(_currentUser!.toJson()));
  }

  /// Clear auth data from SharedPreferences
  Future<void> _clearAuthData() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserData);
  }
}
