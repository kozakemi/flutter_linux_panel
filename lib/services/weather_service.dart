import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_models.dart';

class WeatherService extends ChangeNotifier {
  WeatherService._();

  static final WeatherService instance = WeatherService._();

  static const String _apiKeyPreference = 'weather_openweather_api_key';
  static const String _autoLocationPreference = 'weather_auto_location';
  static const String _locationPreference = 'weather_location';

  String _apiKey = '';
  bool _autoLocation = true;
  String _manualLocation = '';
  WeatherData? _weather;
  List<HourlyWeatherForecast> _hourlyForecast = const <HourlyWeatherForecast>[];
  List<DailyWeatherForecast> _dailyForecast = const <DailyWeatherForecast>[];
  String? _forecastNotice;
  bool _usingOneCall = false;
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;
  Timer? _refreshTimer;

  String get apiKey => _apiKey;
  bool get hasApiKey => _apiKey.isNotEmpty;
  bool get autoLocation => _autoLocation;
  String get manualLocation => _manualLocation;
  WeatherData? get weather => _weather;
  List<HourlyWeatherForecast> get hourlyForecast => _hourlyForecast;
  List<DailyWeatherForecast> get dailyForecast => _dailyForecast;
  String? get forecastNotice => _forecastNotice;
  bool get usingOneCall => _usingOneCall;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPreference) ?? '';
    _autoLocation = prefs.getBool(_autoLocationPreference) ?? true;
    _manualLocation = prefs.getString(_locationPreference) ?? '';
    _refreshTimer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(refresh()),
    );
    if (hasApiKey) {
      unawaited(refresh());
    }
  }

  Future<void> updateConfiguration({
    required bool autoLocation,
    required String location,
    String? apiKey,
  }) async {
    final trimmedKey = apiKey?.trim();
    if (trimmedKey != null && trimmedKey.isNotEmpty) {
      _apiKey = trimmedKey;
    }
    _autoLocation = autoLocation;
    _manualLocation = location.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPreference, _apiKey);
    await prefs.setBool(_autoLocationPreference, _autoLocation);
    await prefs.setString(_locationPreference, _manualLocation);
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    if (!hasApiKey) {
      _error = '尚未配置 OpenWeather API Key';
      notifyListeners();
      return;
    }
    if (!_autoLocation && _manualLocation.isEmpty) {
      _error = '请设置城市或地区';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final location = _autoLocation
          ? await _locateByPublicIp()
          : await _geocodeLocation(_manualLocation);
      _weather = await _fetchCurrentWeather(location);
      try {
        await _fetchForecast(location);
      } catch (error) {
        _hourlyForecast = const <HourlyWeatherForecast>[];
        _dailyForecast = const <DailyWeatherForecast>[];
        _forecastNotice = '预报暂不可用：${_friendlyError(error)}';
      }
      _lastUpdated = DateTime.now();
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<WeatherLocation> _locateByPublicIp() async {
    Object? lastError;
    for (final uri in <Uri>[
      Uri.https('ipwho.is', '/'),
      Uri.https('ipapi.co', '/json/'),
    ]) {
      try {
        final json = await _getJson(uri);
        if (json['success'] == false) {
          throw WeatherServiceException(
            json['message'] as String? ?? 'IP 自动定位失败',
          );
        }
        final latitude = (json['latitude'] as num?)?.toDouble();
        final longitude = (json['longitude'] as num?)?.toDouble();
        if (latitude == null || longitude == null) {
          throw const WeatherServiceException('IP 定位服务未返回坐标');
        }
        final city = json['city'] as String? ?? '';
        final region = (json['region'] ?? json['region_name']) as String? ?? '';
        return WeatherLocation(
          latitude: latitude,
          longitude: longitude,
          name: city.isNotEmpty ? city : region,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw WeatherServiceException(
      'IP 自动定位失败${lastError == null ? '' : '：$lastError'}',
    );
  }

  Future<WeatherLocation> _geocodeLocation(String query) async {
    final uri = Uri.https(
      'api.openweathermap.org',
      '/geo/1.0/direct',
      {'q': query, 'limit': '1', 'appid': _apiKey},
    );
    final response = await _getJsonList(uri);
    if (response.isEmpty) {
      throw WeatherServiceException('找不到地区“$query”');
    }
    final result = response.first as Map<String, dynamic>;
    return WeatherLocation(
      latitude: (result['lat'] as num).toDouble(),
      longitude: (result['lon'] as num).toDouble(),
      name: result['name'] as String? ?? query,
    );
  }

  Future<WeatherData> _fetchCurrentWeather(WeatherLocation location) async {
    final uri = Uri.https(
      'api.openweathermap.org',
      '/data/2.5/weather',
      {
        'lat': '${location.latitude}',
        'lon': '${location.longitude}',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'zh_cn',
      },
    );
    return WeatherData.fromOpenWeather(await _getJson(uri));
  }

  Future<void> _fetchForecast(WeatherLocation location) async {
    try {
      await _fetchOneCallForecast(location);
      _usingOneCall = true;
      _forecastNotice = null;
    } catch (_) {
      await _fetchFiveDayForecast(location);
      _usingOneCall = false;
      _forecastNotice = '当前 API Key 未使用 One Call 3.0，已降级为每 3 小时、未来 5 天预报';
    }
  }

  Future<void> _fetchOneCallForecast(WeatherLocation location) async {
    final uri = Uri.https(
      'api.openweathermap.org',
      '/data/3.0/onecall',
      {
        'lat': '${location.latitude}',
        'lon': '${location.longitude}',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'zh_cn',
        'exclude': 'current,minutely,alerts',
      },
    );
    final json = await _getJson(uri);
    final offset = (json['timezone_offset'] as num?)?.toInt() ?? 0;
    final hourly = json['hourly'] as List<dynamic>? ?? const [];
    final daily = json['daily'] as List<dynamic>? ?? const [];
    if (hourly.isEmpty || daily.isEmpty) {
      throw const WeatherServiceException('One Call 未返回预报数据');
    }

    _hourlyForecast = hourly.take(24).map((item) {
      final value = item as Map<String, dynamic>;
      final weather = _firstWeather(value);
      return HourlyWeatherForecast(
        time: _localForecastTime(value['dt'], offset),
        temperature: (value['temp'] as num?)?.toDouble() ?? 0,
        feelsLike: (value['feels_like'] as num?)?.toDouble() ?? 0,
        conditionId: (weather['id'] as num?)?.toInt() ?? 0,
        iconCode: weather['icon'] as String? ?? '',
        description: weather['description'] as String? ?? '未知',
        precipitationProbability: (value['pop'] as num?)?.toDouble() ?? 0,
      );
    }).toList(growable: false);

    _dailyForecast = daily.take(7).map((item) {
      final value = item as Map<String, dynamic>;
      final temperature = value['temp'] as Map<String, dynamic>? ?? const {};
      final weather = _firstWeather(value);
      return DailyWeatherForecast(
        date: _localForecastTime(value['dt'], offset),
        minimumTemperature: (temperature['min'] as num?)?.toDouble() ?? 0,
        maximumTemperature: (temperature['max'] as num?)?.toDouble() ?? 0,
        conditionId: (weather['id'] as num?)?.toInt() ?? 0,
        iconCode: weather['icon'] as String? ?? '',
        description: weather['description'] as String? ?? '未知',
        precipitationProbability: (value['pop'] as num?)?.toDouble() ?? 0,
      );
    }).toList(growable: false);
  }

  Future<void> _fetchFiveDayForecast(WeatherLocation location) async {
    final uri = Uri.https(
      'api.openweathermap.org',
      '/data/2.5/forecast',
      {
        'lat': '${location.latitude}',
        'lon': '${location.longitude}',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'zh_cn',
      },
    );
    final json = await _getJson(uri);
    final city = json['city'] as Map<String, dynamic>? ?? const {};
    final offset = (city['timezone'] as num?)?.toInt() ?? 0;
    final list = json['list'] as List<dynamic>? ?? const [];
    if (list.isEmpty) {
      throw const WeatherServiceException('5 天预报接口未返回数据');
    }

    _hourlyForecast = list.take(8).map((item) {
      final value = item as Map<String, dynamic>;
      final main = value['main'] as Map<String, dynamic>? ?? const {};
      final weather = _firstWeather(value);
      return HourlyWeatherForecast(
        time: _localForecastTime(value['dt'], offset),
        temperature: (main['temp'] as num?)?.toDouble() ?? 0,
        feelsLike: (main['feels_like'] as num?)?.toDouble() ?? 0,
        conditionId: (weather['id'] as num?)?.toInt() ?? 0,
        iconCode: weather['icon'] as String? ?? '',
        description: weather['description'] as String? ?? '未知',
        precipitationProbability: (value['pop'] as num?)?.toDouble() ?? 0,
      );
    }).toList(growable: false);

    final aggregates = <String, _DailyForecastAggregate>{};
    for (final item in list) {
      final value = item as Map<String, dynamic>;
      final time = _localForecastTime(value['dt'], offset);
      final key =
          '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
      final main = value['main'] as Map<String, dynamic>? ?? const {};
      final weather = _firstWeather(value);
      final temperature = (main['temp'] as num?)?.toDouble() ?? 0;
      final minimum = (main['temp_min'] as num?)?.toDouble() ?? temperature;
      final maximum = (main['temp_max'] as num?)?.toDouble() ?? temperature;
      final aggregate = aggregates.putIfAbsent(
        key,
        () => _DailyForecastAggregate(
          date: DateTime.utc(time.year, time.month, time.day),
          minimumTemperature: minimum,
          maximumTemperature: maximum,
          conditionId: (weather['id'] as num?)?.toInt() ?? 0,
          iconCode: weather['icon'] as String? ?? '',
          description: weather['description'] as String? ?? '未知',
          precipitationProbability: (value['pop'] as num?)?.toDouble() ?? 0,
          representativeHourDistance: (time.hour - 12).abs(),
        ),
      );
      aggregate.minimumTemperature = minimum < aggregate.minimumTemperature
          ? minimum
          : aggregate.minimumTemperature;
      aggregate.maximumTemperature = maximum > aggregate.maximumTemperature
          ? maximum
          : aggregate.maximumTemperature;
      final probability = (value['pop'] as num?)?.toDouble() ?? 0;
      if (probability > aggregate.precipitationProbability) {
        aggregate.precipitationProbability = probability;
      }
      final distance = (time.hour - 12).abs();
      if (distance < aggregate.representativeHourDistance) {
        aggregate
          ..representativeHourDistance = distance
          ..conditionId = (weather['id'] as num?)?.toInt() ?? 0
          ..iconCode = weather['icon'] as String? ?? ''
          ..description = weather['description'] as String? ?? '未知';
      }
    }
    _dailyForecast = aggregates.values
        .take(5)
        .map((aggregate) => aggregate.toForecast())
        .toList(growable: false);
  }

  Map<String, dynamic> _firstWeather(Map<String, dynamic> value) {
    final list = value['weather'] as List<dynamic>? ?? const [];
    return list.isEmpty
        ? const <String, dynamic>{}
        : list.first as Map<String, dynamic>;
  }

  DateTime _localForecastTime(dynamic seconds, int offset) {
    final value = (seconds as num?)?.toInt() ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(
      (value + offset) * 1000,
      isUtc: true,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final value = await _requestJson(uri);
    if (value is! Map<String, dynamic>) {
      throw const WeatherServiceException('服务器返回的数据格式不正确');
    }
    return value;
  }

  Future<List<dynamic>> _getJsonList(Uri uri) async {
    final value = await _requestJson(uri);
    if (value is! List<dynamic>) {
      throw const WeatherServiceException('服务器返回的数据格式不正确');
    }
    return value;
  }

  Future<Object?> _requestJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
            const Duration(seconds: 12),
          );
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message']?.toString()
            : null;
        throw WeatherServiceException(
          message ?? '请求失败 (${response.statusCode})',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const WeatherServiceException('天气服务连接超时');
    } finally {
      client.close(force: true);
    }
  }

  String _friendlyError(Object error) {
    if (error is WeatherServiceException) return error.message;
    if (error is SocketException) return '无法连接天气服务，请检查网络';
    if (error is HandshakeException) return '天气服务安全连接失败';
    return '获取天气失败：$error';
  }
}

class WeatherServiceException implements Exception {
  const WeatherServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _DailyForecastAggregate {
  _DailyForecastAggregate({
    required this.date,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.conditionId,
    required this.iconCode,
    required this.description,
    required this.precipitationProbability,
    required this.representativeHourDistance,
  });

  final DateTime date;
  double minimumTemperature;
  double maximumTemperature;
  int conditionId;
  String iconCode;
  String description;
  double precipitationProbability;
  int representativeHourDistance;

  DailyWeatherForecast toForecast() => DailyWeatherForecast(
        date: date,
        minimumTemperature: minimumTemperature,
        maximumTemperature: maximumTemperature,
        conditionId: conditionId,
        iconCode: iconCode,
        description: description,
        precipitationProbability: precipitationProbability,
      );
}
