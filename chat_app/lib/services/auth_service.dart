import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'current_user';
  
  final ApiService _apiService = ApiService();
  User? _currentUser;
  String? _authToken;

  // 单例模式
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // 获取当前用户
  User? get currentUser => _currentUser;
  
  // 获取认证令牌
  String? get authToken => _authToken;
  
  // 是否已登录
  bool get isLoggedIn => _authToken != null && _currentUser != null;

  // 登录
  Future<User> login(String username, String password) async {
    final result = await _apiService.login(username, password);
    
    _authToken = result['token'] ?? result['accessToken'];
    if (_authToken != null) {
      _apiService.setAuthToken(_authToken!);
      
      // 获取用户信息
      try {
        _currentUser = await _apiService.getCurrentUser();
      } catch (e) {
        // 如果无法获取用户信息，使用响应中的用户数据
        if (result['user'] != null) {
          _currentUser = User.fromJson(result['user']);
        } else {
          throw Exception('无法获取用户信息');
        }
      }
      
      // 保存到本地存储
      await _saveToStorage();
      
      return _currentUser!;
    } else {
      throw Exception('登录失败：未获取到认证令牌');
    }
  }

  // 注册
  Future<User> register(Map<String, dynamic> userData) async {
    final result = await _apiService.register(userData);
    
    // 注册成功后自动登录
    if (result['token'] != null || result['user'] != null) {
      _authToken = result['token'] ?? result['accessToken'];
      if (_authToken != null) {
        _apiService.setAuthToken(_authToken!);
      }
      
      _currentUser = User.fromJson(result['user'] ?? result);
      
      // 保存到本地存储
      await _saveToStorage();
      
      return _currentUser!;
    } else {
      throw Exception('注册失败');
    }
  }

  // 登出
  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      // 即使API调用失败，也要清除本地数据
      print('登出API调用失败: $e');
    }
    
    await _clearStorage();
    _authToken = null;
    _currentUser = null;
    _apiService.clearAuthToken();
  }

  // 从本地存储恢复登录状态
  Future<void> restoreAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _authToken = prefs.getString(_tokenKey);
      final userJson = prefs.getString(_userKey);
      
      if (_authToken != null && userJson != null) {
        _apiService.setAuthToken(_authToken!);
        _currentUser = User.fromJson(json.decode(userJson));
        
        // 验证令牌是否仍然有效
        try {
          final updatedUser = await _apiService.getCurrentUser();
          _currentUser = updatedUser;
          await _saveToStorage(); // 更新保存的用户信息
        } catch (e) {
          // 令牌无效，清除登录状态
          print('令牌无效，清除登录状态: $e');
          await logout();
        }
      }
    } catch (e) {
      print('恢复登录状态失败: $e');
      await _clearStorage();
    }
  }

  // 更新用户信息
  Future<User> updateProfile(Map<String, dynamic> userData) async {
    if (!isLoggedIn) {
      throw Exception('用户未登录');
    }
    
    _currentUser = await _apiService.updateProfile(userData);
    await _saveToStorage();
    return _currentUser!;
  }

  // 刷新用户信息
  Future<User> refreshUserInfo() async {
    if (!isLoggedIn) {
      throw Exception('用户未登录');
    }
    
    _currentUser = await _apiService.getCurrentUser();
    await _saveToStorage();
    return _currentUser!;
  }

  // 保存到本地存储
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_authToken != null) {
        await prefs.setString(_tokenKey, _authToken!);
      }
      
      if (_currentUser != null) {
        await prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
      }
    } catch (e) {
      print('保存到本地存储失败: $e');
    }
  }

  // 清除本地存储
  Future<void> _clearStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (e) {
      print('清除本地存储失败: $e');
    }
  }
} 