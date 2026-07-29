/*
Copyright 2025 kozakemi

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

/// 屏幕亮度状态，数值范围统一为 0–100。
class BrightnessStatus {
  const BrightnessStatus({
    required this.current,
    required this.max,
    required this.autoEnabled,
    required this.available,
  });

  final int current;
  final int max;
  final bool autoEnabled;
  final bool available;

  BrightnessStatus copyWith({
    int? current,
    int? max,
    bool? autoEnabled,
    bool? available,
  }) {
    return BrightnessStatus(
      current: current ?? this.current,
      max: max ?? this.max,
      autoEnabled: autoEnabled ?? this.autoEnabled,
      available: available ?? this.available,
    );
  }

  int get percentage {
    if (max <= 0) return 0;
    return ((current / max) * 100).round().clamp(0, 100);
  }

  String get description {
    if (!available) return '亮度控制不可用';

    final percent = percentage;
    if (percent >= 80) return '很亮 ($percent%)';
    if (percent >= 60) return '较亮 ($percent%)';
    if (percent >= 40) return '适中 ($percent%)';
    if (percent >= 20) return '较暗 ($percent%)';
    return '很暗 ($percent%)';
  }
}
