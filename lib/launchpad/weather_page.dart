import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/weather_models.dart';
import '../services/display_service.dart';
import '../services/weather_service.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final WeatherService _service = WeatherService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleChanged);
    if (_service.hasApiKey && _service.weather == null) {
      _service.refresh();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            tooltip: '刷新天气',
            onPressed: _service.loading ? null : _service.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_service.loading && _service.weather == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_service.hasApiKey) {
      return _buildMessage(
        context,
        icon: Icons.key_outlined,
        title: '需要配置 OpenWeather API Key',
        message: '请在“设置 → 远程 Web 设置”中开启服务，使用手机或电脑配置天气。',
      );
    }
    if (_service.weather == null) {
      return _buildMessage(
        context,
        icon: Icons.cloud_off_outlined,
        title: '暂时无法获取天气',
        message: _service.error ?? '请稍后重试',
        action: FilledButton.icon(
          onPressed: _service.refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }

    final weather = _service.weather!;
    return RefreshIndicator(
      onRefresh: _service.refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth > 700 ? 32.0 : 16.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              32,
            ),
            children: [
              _buildCurrentWeather(context, weather),
              const SizedBox(height: 16),
              if (_service.forecastNotice != null) ...[
                _buildForecastNotice(context, _service.forecastNotice!),
                const SizedBox(height: 16),
              ],
              if (_service.hourlyForecast.isNotEmpty) ...[
                _buildHourlyForecast(context),
                const SizedBox(height: 20),
              ],
              if (_service.dailyForecast.isNotEmpty) ...[
                _buildDailyForecast(context),
                const SizedBox(height: 20),
              ],
              _buildMetrics(context, weather, constraints.maxWidth),
              if (_service.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _service.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildForecastNotice(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyForecast(BuildContext context) {
    final forecasts = _service.hourlyForecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _service.usingOneCall ? '未来 24 小时' : '未来 24 小时（每 3 小时）',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 174,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: forecasts.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final forecast = forecasts[index];
              return SizedBox(
                width: 112,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        Text(DateFormat('HH:mm').format(forecast.time)),
                        const SizedBox(height: 8),
                        Icon(
                          forecast.icon,
                          size: 34,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${forecast.temperature.round()}°',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '降水 ${(forecast.precipitationProbability * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyForecast(BuildContext context) {
    final forecasts = _service.dailyForecast;
    final now = DateTime.now();
    String dateLabel(DateTime date) {
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return '今天';
      }
      return DateFormat('MM/dd E').format(date);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '未来 ${forecasts.length} 天',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < forecasts.length; index++) ...[
                Builder(
                  builder: (context) {
                    final forecast = forecasts[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 72,
                        child: Text(
                          dateLabel(forecast.date),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      title: Row(
                        children: [
                          Icon(
                            forecast.icon,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              forecast.description,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '降水 ${(forecast.precipitationProbability * 100).round()}%',
                      ),
                      trailing: Text(
                        '${forecast.minimumTemperature.round()}° / '
                        '${forecast.maximumTemperature.round()}°',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
                if (index != forecasts.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentWeather(BuildContext context, WeatherData weather) {
    final colorScheme = Theme.of(context).colorScheme;
    final updated = _service.lastUpdated == null
        ? ''
        : DateFormat('HH:mm').format(_service.lastUpdated!);
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(
              weather.icon,
              size: 88,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weather.locationName}'
                    '${weather.country.isEmpty ? '' : ' · ${weather.country}'}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    weather.description,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${weather.temperature.round()}°',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w300,
                        ),
                  ),
                  Text(
                    '体感 ${weather.feelsLike.round()}°  '
                    '最高 ${weather.maximumTemperature.round()}°  '
                    '最低 ${weather.minimumTemperature.round()}°',
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                  if (updated.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_service.autoLocation ? 'IP 自动定位' : '手动位置'}'
                      ' · $updated 更新',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(
    BuildContext context,
    WeatherData weather,
    double width,
  ) {
    final columns = width >= 900
        ? 4
        : width >= 560
            ? 3
            : 2;
    final items = <({IconData icon, String label, String value})>[
      (
        icon: Icons.water_drop_outlined,
        label: '湿度',
        value: '${weather.humidity}%',
      ),
      (
        icon: Icons.air,
        label: '风',
        value:
            '${weather.windSpeed.toStringAsFixed(1)} m/s ${weather.windDirectionName}风',
      ),
      (
        icon: Icons.speed,
        label: '气压',
        value: '${weather.pressure} hPa',
      ),
      (
        icon: Icons.visibility_outlined,
        label: '能见度',
        value: '${(weather.visibility / 1000).toStringAsFixed(1)} km',
      ),
      (
        icon: Icons.cloud_outlined,
        label: '云量',
        value: '${weather.cloudiness}%',
      ),
      (
        icon: Icons.wb_sunny_outlined,
        label: '日出',
        value: DateFormat('HH:mm').format(weather.sunrise),
      ),
      (
        icon: Icons.nights_stay_outlined,
        label: '日落',
        value: DateFormat('HH:mm').format(weather.sunset),
      ),
      (
        icon: Icons.location_on_outlined,
        label: '坐标',
        value:
            '${weather.latitude.toStringAsFixed(2)}, ${weather.longitude.toStringAsFixed(2)}',
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        item.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
