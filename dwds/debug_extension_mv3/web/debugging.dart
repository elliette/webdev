// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debugging;

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js_util';

import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/src/sockets.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:sse/client/sse_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chrome_api.dart';
import 'data_serializers.dart';
import 'debug_session.dart';
import 'storage.dart';
import 'web_api.dart';

final _enableDebugLogging = true;

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

final _debugSessions = <DebugSession>[];

void registerDebugEventListeners() {
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
}

void attachDebugger(int tabId) {
  chrome.debugger.attach(
    Debuggee(tabId: tabId),
    '1.3',
    allowInterop(
      () => _enableExecutionContextReporting(tabId),
    ),
  );
}

_enableExecutionContextReporting(int tabId) {
  // Runtime.enable enables reporting of execution contexts creation by means of
  // executionContextCreated event. When the reporting gets enabled the event
  // will be sent immediately for each existing execution context:
  chrome.debugger.sendCommand(
      Debuggee(tabId: tabId), 'Runtime.enable', EmptyParam(), allowInterop((_) {
    final chromeError = chrome.runtime.lastError;
    if (chromeError != null) {
      final errorMessage = _translateChromeError(chromeError.message);
      console.warn(errorMessage);
      return;
    }
  }));
}

String _translateChromeError(String chromeErrorMessage) {
  if (chromeErrorMessage.contains('Cannot access') ||
      chromeErrorMessage.contains('Cannot attach')) {
    return _notADartAppAlert;
  }
  return _devToolsAlreadyOpenedAlert;
}

Future<void> _onDebuggerEvent(
    Debuggee source, String method, Object? params) async {
  if (method != 'Runtime.executionContextCreated') {
    return _forwardChromeDebuggerEventToDwds(source, method, params);
  }
  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String?;
  // Ignore execution contexts for chrome extensions:
  if (contextOrigin == null || contextOrigin.contains(('chrome-extension:')))
    return;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: source.tabId,
  );
  if (contextOrigin != debugInfo?.appOrigin) return;
  final contextId = context['id'] as int;
  final connected = await _connectToDwds(
    dartAppContextId: contextId,
    dartAppTabId: source.tabId,
    debugInfo: debugInfo!,
  );
  if (connected) {
    _debugLog('Connected to DWDS.');
  } else {
    _debugWarn('Failed to connect to DWDS.');
  }
}

Future<bool> _connectToDwds({
  required int dartAppContextId,
  required int dartAppTabId,
  required DebugInfo debugInfo,
}) async {
  if (debugInfo.extensionUrl == null) {
    _debugWarn('Can\'t connect to DWDS without an extension URL.');
    return false;
  }
  final uri = Uri.parse(debugInfo.extensionUrl!);
  // Start the client connection with DWDS:
  final client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  final debugSession = DebugSession(client: client, appTabId: dartAppTabId);
  _debugSessions.add(debugSession);
  client.stream.listen((data) => _routeDwdsEvent(data, client, dartAppTabId), onDone: () {
    _debugLog('Received stream done event');
  }, onError: (err) {
    _debugWarn('Received stream error event: $err');
  }, cancelOnError: true);
  _debugLog('Done creating event stream.');
  final tabUrl = await _getTabUrl(dartAppTabId);
  // Send a DevtoolsRequest to the event stream:
  final event = jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = debugInfo.appId
    ..instanceId = debugInfo.appInstanceId
    ..contextId = dartAppContextId
    ..tabUrl = tabUrl
    ..uriOnly = true)));
  _debugLog('Adding $event to event stream.');
  client.sink.add(event);
  return true;
}

void _routeDwdsEvent(String eventData, SocketClient client, int tabId) {
  final message = serializers.deserialize(jsonDecode(eventData));
  if (message is ExtensionRequest) {
    _forwardDwdsEventToChromeDebugger(message, client, tabId);
  } else if (message is ExtensionEvent) {
    switch (message.method) {
      case 'dwds.encodedUri':
        // TODO(elliette): Forward to external extensions.
        break;
      case 'dwds.devtoolsUri':
        _debugLog('Received DevTools URL: ${message.params}');
        break;
    }
  }
}

void _forwardDwdsEventToChromeDebugger(
    ExtensionRequest message, SocketClient client, int tabId) {
  final messageParams = message.commandParams ?? '{}';
  final params = BuiltMap<String, Object>(json.decode(messageParams)).toMap();
  chrome.debugger.sendCommand(
      Debuggee(tabId: tabId), message.command, js_util.jsify(params),
      allowInterop(([e]) {
    // No arguments indicate that an error occurred.
    if (e == null) {
      client.sink
          .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
            ..id = message.id
            ..success = false
            ..result = JSON.stringify(chrome.runtime.lastError)))));
    } else {
      client.sink
          .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
            ..id = message.id
            ..success = true
            ..result = JSON.stringify(e)))));
    }
  }));
}

void _forwardChromeDebuggerEventToDwds(
    Debuggee source, String method, dynamic params) {
  final debugSession = _debugSessions
      .firstWhereOrNull((session) => session.appTabId == source.tabId);

  if (debugSession == null) return;

  final event = _extensionEventFor(method, params);

  if (method == 'Debugger.scriptParsed') {
    debugSession.sendBatchedEvent(event);
  } else {
    debugSession.sendEvent(event);
  }
}

/// Construct an [ExtensionEvent] from [method] and [params].
ExtensionEvent _extensionEventFor(String method, dynamic params) {
  return ExtensionEvent((b) => b
    ..params = jsonEncode(json.decode(JSON.stringify(params)))
    ..method = jsonEncode(method));
}

Future<String> _getTabUrl(int tabId) async {
  final tab = await promiseToFuture<Tab?>(chrome.tabs.get(tabId));
  return tab?.url ?? '';
}

void _debugLog(String msg) {
  if (_enableDebugLogging) {
    console.log('$msg [TIME: ${_currentTime()}]');
  }
}

void _debugWarn(String msg) {
  if (_enableDebugLogging) {
    console.warn('$msg [TIME: ${_currentTime()}]');
  }
}

String _currentTime() {
  final date = DateTime.now();
  return '${date.hour}:${date.minute} ${date.second}s${date.millisecond}ms';
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
