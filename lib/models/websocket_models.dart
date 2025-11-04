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

/// WebSocket连接状态枚举
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 模块状态枚举
enum ModuleStatus {
  uninitialized,
  initializing,
  running,
  stopping,
  stopped,
  error,
}

/// WebSocket消息基类
abstract class WebSocketMessage {
  final String type;
  final String? requestId;

  const WebSocketMessage({
    required this.type,
    this.requestId,
  });

  Map<String, dynamic> toJson();

  /// 从JSON创建WebSocket消息
  static WebSocketMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    
    if (type.endsWith('_request')) {
      return WebSocketRequest.fromJson(json);
    } else if (type.endsWith('_response')) {
      return WebSocketResponse.fromJson(json);
    } else if (type.endsWith('_event')) {
      return WebSocketEvent.fromJson(json);
    }
    
    throw ArgumentError('Unknown message type: $type');
  }
}

/// WebSocket请求消息
class WebSocketRequest extends WebSocketMessage {
  final Map<String, dynamic> data;

  const WebSocketRequest({
    required String type,
    required String requestId,
    required this.data,
  }) : super(type: type, requestId: requestId);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'request_id': requestId,
      'data': data,
    };
  }

  factory WebSocketRequest.fromJson(Map<String, dynamic> json) {
    return WebSocketRequest(
      type: json['type'] as String,
      requestId: json['request_id'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() => 'WebSocketRequest(type: $type, requestId: $requestId, data: $data)';
}

/// WebSocket响应消息
class WebSocketResponse extends WebSocketMessage {
  final bool success;
  final int errorCode;
  final String? message;
  final Map<String, dynamic> data;

  const WebSocketResponse({
    required String type,
    required String requestId,
    required this.success,
    required this.errorCode,
    this.message,
    required this.data,
  }) : super(type: type, requestId: requestId);

  @override
  Map<String, dynamic> toJson() {
    final json = {
      'type': type,
      'request_id': requestId,
      'success': success,
      'error': errorCode,
      'data': data,
    };
    
    if (message != null) {
      json['message'] = message!;
    }
    
    return json;
  }

  factory WebSocketResponse.fromJson(Map<String, dynamic> json) {
    return WebSocketResponse(
      type: json['type'] as String,
      requestId: json['request_id'] as String,
      success: json['success'] as bool? ?? false,
      errorCode: json['error'] as int? ?? -1,
      message: json['message'] as String?,
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() => 'WebSocketResponse(type: $type, requestId: $requestId, success: $success, errorCode: $errorCode, message: $message, data: $data)';
}

/// WebSocket事件消息
class WebSocketEvent extends WebSocketMessage {
  final Map<String, dynamic> data;

  const WebSocketEvent({
    required String type,
    required this.data,
  }) : super(type: type);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
    };
  }

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() => 'WebSocketEvent(type: $type, data: $data)';
}

/// 模块事件
class ModuleEvent {
  final String moduleId;
  final String eventType;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  ModuleEvent({
    required this.moduleId,
    required this.eventType,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'ModuleEvent(moduleId: $moduleId, eventType: $eventType, data: $data, timestamp: $timestamp)';
}

/// WebSocket异常
class WebSocketException implements Exception {
  final String message;
  final int? errorCode;
  final dynamic originalError;

  const WebSocketException(
    this.message, {
    this.errorCode,
    this.originalError,
  });

  @override
  String toString() => 'WebSocketException: $message${errorCode != null ? ' (code: $errorCode)' : ''}';
}

/// 模块异常
class ModuleException implements Exception {
  final String moduleId;
  final String message;
  final dynamic originalError;

  const ModuleException(
    this.moduleId,
    this.message, {
    this.originalError,
  });

  @override
  String toString() => 'ModuleException[$moduleId]: $message';
}