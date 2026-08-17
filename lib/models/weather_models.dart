import 'package:flutter/material.dart';

IconData weatherConditionIcon(int conditionId, String iconCode) {
  if (conditionId >= 200 && conditionId < 300) {
    return Icons.thunderstorm_outlined;
  }
  if (conditionId >= 300 && conditionId < 600) {
    return Icons.water_drop_outlined;
  }
  if (conditionId >= 600 && conditionId < 700) {
    return Icons.ac_unit;
  }
  if (conditionId >= 700 && conditionId < 800) {
    return Icons.foggy;
  }
  if (conditionId == 800) {
    return iconCode.endsWith('n')
        ? Icons.nightlight_outlined
        : Icons.wb_sunny_outlined;
  }
  return Icons.cloud_outlined;
}

class WeatherData {
  const WeatherData({
    required this.locationName,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.temperature,
    required this.feelsLike,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.description,
    required this.conditionId,
    required this.iconCode,
    required this.humidity,
    required this.pressure,
    required this.visibility,
    required this.windSpeed,
    required this.windDirection,
    required this.cloudiness,
    required this.sunrise,
    required this.sunset,
    required this.observedAt,
  });

  final String locationName;
  final String country;
  final double latitude;
  final double longitude;
  final double temperature;
  final double feelsLike;
  final double minimumTemperature;
  final double maximumTemperature;
  final String description;
  final int conditionId;
  final String iconCode;
  final int humidity;
  final int pressure;
  final int visibility;
  final double windSpeed;
  final int windDirection;
  final int cloudiness;
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime observedAt;

  factory WeatherData.fromOpenWeather(Map<String, dynamic> json) {
    final coordinates = json['coord'] as Map<String, dynamic>? ?? const {};
    final main = json['main'] as Map<String, dynamic>? ?? const {};
    final wind = json['wind'] as Map<String, dynamic>? ?? const {};
    final clouds = json['clouds'] as Map<String, dynamic>? ?? const {};
    final system = json['sys'] as Map<String, dynamic>? ?? const {};
    final weatherList = json['weather'] as List<dynamic>? ?? const [];
    final weather = weatherList.isEmpty
        ? const <String, dynamic>{}
        : weatherList.first as Map<String, dynamic>;
    final timezone = (json['timezone'] as num?)?.toInt() ?? 0;

    DateTime localTime(dynamic seconds) {
      final value = (seconds as num?)?.toInt() ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(
        (value + timezone) * 1000,
        isUtc: true,
      );
    }

    return WeatherData(
      locationName: json['name'] as String? ?? '未知位置',
      country: system['country'] as String? ?? '',
      latitude: (coordinates['lat'] as num?)?.toDouble() ?? 0,
      longitude: (coordinates['lon'] as num?)?.toDouble() ?? 0,
      temperature: (main['temp'] as num?)?.toDouble() ?? 0,
      feelsLike: (main['feels_like'] as num?)?.toDouble() ?? 0,
      minimumTemperature: (main['temp_min'] as num?)?.toDouble() ?? 0,
      maximumTemperature: (main['temp_max'] as num?)?.toDouble() ?? 0,
      description: weather['description'] as String? ?? '未知',
      conditionId: (weather['id'] as num?)?.toInt() ?? 0,
      iconCode: weather['icon'] as String? ?? '',
      humidity: (main['humidity'] as num?)?.toInt() ?? 0,
      pressure: (main['pressure'] as num?)?.toInt() ?? 0,
      visibility: (json['visibility'] as num?)?.toInt() ?? 0,
      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0,
      windDirection: (wind['deg'] as num?)?.toInt() ?? 0,
      cloudiness: (clouds['all'] as num?)?.toInt() ?? 0,
      sunrise: localTime(system['sunrise']),
      sunset: localTime(system['sunset']),
      observedAt: localTime(json['dt']),
    );
  }

  IconData get icon => weatherConditionIcon(conditionId, iconCode);

  String get windDirectionName {
    const names = <String>[
      '北',
      '东北',
      '东',
      '东南',
      '南',
      '西南',
      '西',
      '西北',
    ];
    return names[((windDirection + 22.5) ~/ 45) % 8];
  }
}

class HourlyWeatherForecast {
  const HourlyWeatherForecast({
    required this.time,
    required this.temperature,
    required this.feelsLike,
    required this.conditionId,
    required this.iconCode,
    required this.description,
    required this.precipitationProbability,
  });

  final DateTime time;
  final double temperature;
  final double feelsLike;
  final int conditionId;
  final String iconCode;
  final String description;
  final double precipitationProbability;

  IconData get icon => weatherConditionIcon(conditionId, iconCode);
}

class DailyWeatherForecast {
  const DailyWeatherForecast({
    required this.date,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.conditionId,
    required this.iconCode,
    required this.description,
    required this.precipitationProbability,
  });

  final DateTime date;
  final double minimumTemperature;
  final double maximumTemperature;
  final int conditionId;
  final String iconCode;
  final String description;
  final double precipitationProbability;

  IconData get icon => weatherConditionIcon(conditionId, iconCode);
}

class WeatherLocation {
  const WeatherLocation({
    required this.latitude,
    required this.longitude,
    required this.name,
  });

  final double latitude;
  final double longitude;
  final String name;
}
