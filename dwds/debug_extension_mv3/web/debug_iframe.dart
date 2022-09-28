// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_iframe;

import 'dart:convert';
import 'dart:html';

import 'package:built_collection/built_collection.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/sockets.dart';
import 'package:sse/client/sse_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chrome_api.dart';
import 'debug_session.dart';
import 'messaging.dart';
import 'web_api.dart';
import 'storage.dart';

const _authenticationPath = '\$dwdsExtensionAuthentication';

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

DebugSession? _debugSession;

late String tabId;
late Debuggee debuggee;
late DebugInfo debugInfo;

void main() async {
  final id = await _getTabId();
  if (id == null) {
    console.warn('Can\'t debug without a tab ID.');
    return null;
  }

  tabId = '$id';
  debuggee = Debuggee(tabId: id);

  _registerListeners();
  _maybeUpdateDebuggingState();
}

void _registerListeners() {
  chrome.storage.onChanged.addListener(allowInterop((_, __) {
    _maybeUpdateDebuggingState();
  }));
}

void _maybeUpdateDebuggingState() async {
  final debugStateJson = await fetchStorageObjectJson(
    type: StorageObject.debugState,
    tabId: tabId,
  );

  if (debugStateJson == null) return;

  final debugState = DebugState.fromJSON(debugStateJson);
  switch (debugState) {
    case DebugState.startDebugging:
      _startDebugging();
      break;
    case DebugState.isDebugging:
      window.console.log('might reconnect to DWDS');
      // _maybeReconnectToDwds();
      break;
    case DebugState.stopDebugging:
      _stopDebugging();
      break;
  }
}

void _startDebugging() async {
  final debugInfoJson =
      await fetchStorageObjectJson(type: StorageObject.debugInfo, tabId: tabId);
  if (debugInfoJson == null) {
    console.warn('Can\'t debug without debug info.');
    return null;
  }
  debugInfo = DebugInfo.fromJSON(debugInfoJson);

  chrome.debugger.onDetach.addListener(allowInterop(_onDebuggerDetach));
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
  chrome.debugger.attach(debuggee, '1.3', allowInterop(_onDebuggerAttach));
}

void _stopDebugging() {
  final session = _debugSession;
  if (session == null) return;

  // Note: package:sse will try to keep the connection alive, even after the
  // client has been closed. Therefore the extension sends an event to notify
  // DWDS that we should close the connection, instead of relying on the done
  // event sent when the client is closed. See details:
  // https://github.com/dart-lang/webdev/pull/1595#issuecomment-1116773378
  final event =
      _extensionEventFor('DebugExtension.detached', js_util.jsify({}));
  session.sendEvent(event);
  session.close();
  _debugSession = null;
}

void _onDebuggerAttach() {
  setStorageObject(
    type: StorageObject.debugState,
    json: DebugState.isDebugging.toJSON(),
    tabId: tabId,
  );

  chrome.debugger.sendCommand(debuggee, 'Runtime.enable', EmptyParam(),
      allowInterop((_) {
    final chromeError = chrome.runtime.lastError;
    if (chromeError != null) {
      window.alert(_translateChromeError(chromeError.message));
      return;
    }
  }));
}

void _onDebuggerDetach(Debuggee source, String _) {
  if (tabId != '${source.tabId}') return;
  setStorageObject(
    type: StorageObject.debugState,
    json: DebugState.stopDebugging.toJSON(),
    tabId: tabId,
  );
}

void _onDebuggerEvent(Debuggee source, String method, Object? params) {
  if (method == 'Runtime.executionContextCreated') {
    _handleExecutionContextCreated(source, params);
  }

  _forwardChromeDebuggerEventToDwds(source, method, params);
}

void _forwardChromeDebuggerEventToDwds(
    Debuggee source, String method, dynamic params) {
  final session = _debugSession;
  if (session == null) return;

  final event = _extensionEventFor(method, params);
  session.sendEvent(event);
}

void _handleExecutionContextCreated(Debuggee source, Object? params) async {
  if (params == null) return;

  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String;
  if (contextOrigin == debugInfo.origin) {
    final contextId = context['id'] as int;
    setStorageObject(
      type: StorageObject.contextId,
      json: ContextId(contextId: contextId).toJSON(),
      tabId: tabId,
      callback: _connectToDwds,
    );
  }
}

void _connectToDwds({bool openDevTools = true}) async {
  final contextIdJson = await fetchStorageObjectJson(
    type: StorageObject.contextId,
    tabId: tabId,
  );
  if (contextIdJson == null) {
    console.warn('Can\'t connect to DWDS without a context ID.');
    return;
  }
  final contextId = ContextId.fromJSON(contextIdJson).contextId;
  final extensionUri = debugInfo.extensionUri;
  if (extensionUri == null) return;

  final uri = Uri.parse(extensionUri);
  final authenticated = await _authenticateUser(uri);
  if (!authenticated) return;
  final client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  _debugSession = DebugSession(client, int.parse(tabId), debugInfo.appId!);

  // Listen to events from DWDS:
  // client.stream.asBroadcastStream().listen?
  client.stream.listen(
    (data) => _routeDwdsEvent(data, client),
    onDone: () {
      console.log('Received done event.');
    },
    onError: (error) {
      console.warn('Received error: $error');
    },
    cancelOnError: true,
  );

  if (openDevTools) {
    _sendDevToolsRequest(client, contextId);
  }
}

void _routeDwdsEvent(String eventData, SocketClient client) {
  final message = serializers.deserialize(jsonDecode(eventData));
  if (message is ExtensionRequest) {
    _forwardDwdsEventToChromeDebugger(message, client);
  } else if (message is ExtensionEvent) {
    switch (message.method) {
      case 'dwds.encodedUri':
        // TODO(elliette): Forward to external extensions.
        break;
      case 'dwds.devtoolsUri':
        // TODO(elliette): Embed in Chrome DevTools panel.
        break;
    }
  }
}

void _forwardDwdsEventToChromeDebugger(
    ExtensionRequest message, SocketClient client) {
  final session = _debugSession;
  if (session == null) return;

  final messageParams = message.commandParams ?? '{}';
  final params = BuiltMap<String, Object>(json.decode(messageParams)).toMap();
  chrome.debugger
      .sendCommand(debuggee, message.command, js_util.jsify(params),
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

void _sendDevToolsRequest(SocketClient client, int contextId) async {
  final session = _debugSession;
  if (session == null) return;

  final tabUrl = await _getTabUrl(int.parse(tabId));
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = debugInfo.appId
    ..instanceId = debugInfo.instanceId
    ..contextId = contextId
    ..tabUrl = tabUrl
    ..uriOnly = false))));
}

Future<bool> _authenticateUser(Uri uri) async {
  var authUri = uri.replace(path: _authenticationPath);
  if (authUri.scheme == 'ws') authUri = authUri.replace(scheme: 'http');
  if (authUri.scheme == 'wss') authUri = authUri.replace(scheme: 'https');
  final authUrl = authUri.toString();
  try {
    final response = await HttpRequest.request(authUrl,
        method: 'GET', withCredentials: true);
    final responseText = response.responseText ?? '';
    if (!responseText.contains('Dart Debug Authentication Success!')) {
      throw Exception('Not authenticated.');
    }
  } catch (_) {
    if (window.confirm(
        'Authentication required.\n\nClick OK to authenticate then try again.')) {
      window.open(authUrl, 'Dart DevTools Authentication');
      chrome.debugger.detach(debuggee, allowInterop(() {}));
    }
    return false;
  }
  return true;
}

/// Construct an [ExtensionEvent] from [method] and [params].
ExtensionEvent _extensionEventFor(String method, dynamic params) {
  return ExtensionEvent((b) => b
    ..params = jsonEncode(json.decode(JSON.stringify(params)))
    ..method = jsonEncode(method));
}

String _translateChromeError(String chromeErrorMessage) {
  if (chromeErrorMessage.contains('Cannot access') ||
      chromeErrorMessage.contains('Cannot attach')) {
    return _notADartAppAlert;
  }
  return _devToolsAlreadyOpenedAlert;
}

Future<String> _getTabUrl(int tabId) async {
  final tab = await promiseToFuture<Tab?>(chrome.tabs.get(tabId));
  return tab?.url ?? '';
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}

Future<int?> _getTabId() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  final tab = tabs.isNotEmpty ? tabs.first : null;
  return tab?.id;
}
