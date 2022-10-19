// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:convert';
import 'dart:html';

import 'package:js/js.dart';

import 'web_api.dart';

enum Script {
  debugIframe,
  background,
  debugInfo,
  debugTab,
  detector,
  iframe,
  iframeInjector;

  factory Script.fromString(String value) {
    return Script.values.byName(value);
  }
}

enum MessageType {
  dartAppDetected,
  dartTab,
  debugInfo,
  debugState,
  iframeReady;

  factory MessageType.fromString(String value) {
    return MessageType.values.byName(value);
  }
}

class Message {
  final Script to;
  final Script from;
  final MessageType type;
  final String encodedBody;
  final String? error;

  Message({
    required this.to,
    required this.from,
    required this.type,
    required this.encodedBody,
    this.error,
  });

  factory Message.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    return Message(
      to: Script.fromString(decoded['to'] as String),
      from: Script.fromString(decoded['from'] as String),
      type: MessageType.fromString(decoded['type'] as String),
      encodedBody: decoded['encodedBody'] as String,
      error: decoded['error'] as String?,
    );
  }

  String toJSON() {
    return jsonEncode({
      'type': type.name,
      'to': to.name,
      'from': from.name,
      'encodedBody': encodedBody,
      if (error != null) 'error': error,
    });
  }
}

void interceptMessage<T>({
  required String? message,
  required MessageType expectedType,
  required Script expectedSender,
  required Script expectedRecipient,
  required void Function(T message) messageHandler,
}) {
  try {
    if (message == null) return;
    final decodedMessage = Message.fromJSON(message);
    if (decodedMessage.type != expectedType ||
        decodedMessage.to != expectedRecipient ||
        decodedMessage.from != expectedSender) {
      return;
    }
    final messageType = decodedMessage.type;
    final messageBody = decodedMessage.encodedBody;
    switch (messageType) {
      case MessageType.dartAppDetected:
        messageHandler(DartAppDetected.fromJSON(messageBody) as T);
        break;
      case MessageType.dartTab:
        messageHandler(DartTab.fromJSON(messageBody) as T);
        break;
      case MessageType.debugInfo:
        messageHandler(DebugInfo.fromJSON(messageBody) as T);
        break;
      case MessageType.debugState:
        messageHandler(DebugState.fromJSON(messageBody) as T);
        break;
      case MessageType.iframeReady:
        messageHandler(IframeReady.fromJSON(messageBody) as T);
        break;
    }
  } catch (error) {
    console.warn(
        'Error intercepting $expectedType from $expectedSender to $expectedRecipient: $error');
  }
}

String? jsEventToMessageData(
  Event event, {
  String? expectedOrigin,
}) {
  try {
    final messageEvent = event as MessageEvent;
    if (expectedOrigin != null &&
        messageEvent.origin.removeTrailingSlash() !=
            expectedOrigin.removeTrailingSlash()) {
      return null;
    }
    return messageEvent.data as String;
  } catch (error) {
    console.warn('Error converting event to message data: $error');
    return null;
  }
}

class IframeReady {
  final bool isReady;

  IframeReady({required this.isReady});

  factory IframeReady.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final isReady = decoded['isReady'] as bool;
    return IframeReady(isReady: isReady);
  }

  String toJSON() {
    return jsonEncode({
      'isReady': isReady,
    });
  }
}

enum DebugState {
  isDebugging,
  isConnecting,
  startDebugging,
  stopDebugging;

  factory DebugState.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final debugStateValue = decoded['debugState'] as String;
    return DebugState.values.byName(debugStateValue);
  }

  String toJSON() {
    return jsonEncode({
      'debugState': name,
    });
  }
}

class DebugInfo {
  final String? origin;
  final String? extensionUri;
  final String? appId;
  final String? instanceId;
  final String? entrypointPath;
  final int? tabId;

  DebugInfo({
    this.origin,
    this.extensionUri,
    this.appId,
    this.instanceId,
    this.entrypointPath,
    this.tabId,
  });

  factory DebugInfo.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final origin = decoded['origin'] as String?;
    final extensionUri = decoded['extensionUri'] as String?;
    final appId = decoded['appId'] as String?;
    final instanceId = decoded['instanceId'] as String?;
    final entrypointPath = decoded['entrypointPath'] as String?;
    final tabId = decoded['tabId'] as int?;
    return DebugInfo(
      origin: origin,
      extensionUri: extensionUri,
      appId: appId,
      instanceId: instanceId,
      entrypointPath: entrypointPath,
      tabId: tabId,
    );
  }

  String toJSON() {
    return jsonEncode({
      'origin': origin,
      'extensionUri': extensionUri,
      'appId': appId,
      'instanceId': instanceId,
      'entrypointPath': entrypointPath,
      'tabId': tabId,
    });
  }
}

extension RemoveTrailingSlash on String {
  String removeTrailingSlash() {
    final trailingSlash = '/';
    if (endsWith(trailingSlash)) {
      return substring(0, length - 1);
    }
    return this;
  }
}

class DartTab {
  final int tabId;

  DartTab({required this.tabId});

  factory DartTab.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final tabId = decoded['tabId'] as int;
    return DartTab(tabId: tabId);
  }

  String toJSON() {
    return jsonEncode({'tabId': tabId});
  }
}

class DartAppDetected {
  final bool detected;

  DartAppDetected({required this.detected});

  factory DartAppDetected.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final detected = decoded['detected'] as bool;
    return DartAppDetected(detected: detected);
  }

  String toJSON() {
    return jsonEncode({
      'detected': detected,
    });
  }
}
