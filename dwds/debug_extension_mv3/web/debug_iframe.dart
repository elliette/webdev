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

// TODO: Figure out how to get the tab ID.
late String tabId;

void main() async {
  final id = await _getTabId();
  tabId = '$id';

  // _registerListeners();
  // _maybeUpdateDebuggingState();
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
      _maybeReconnectToDwds();
      break;
    case DebugState.stopDebugging:
      _stopDebugging();
      break;
  }
}

void _startDebugging() async {
  _debugSession = null;

  final newSession = await _createDebugSession();
  if (newSession == null) return;
  _debugSession = newSession;

  // When a debug session is detached, remove the reference to it:
  chrome.debugger.onDetach.addListener(allowInterop((Debuggee source, _) {
    if (source.tabId == newSession.tabId) {
      setStorageObject(
        type: StorageObject.debugState,
        json: DebugState.stopDebugging.toJSON(),
        tabId: tabId,
      );
    }
  }));
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
  chrome.debugger.attach(
      _debugSession!.debuggee, '1.3', allowInterop(_onDebuggerAttached));
}

Future<DebugSession?> _createDebugSession() async {
  final debugInfoJson =
      await fetchStorageObjectJson(type: StorageObject.debugInfo, tabId: tabId);

  if (debugInfoJson == null) {
    console.warn('Can\'t debug without debug info.');
    return null;
  }

  final debugInfo = DebugInfo.fromJSON(debugInfoJson);
  final dartTab = debugInfo.tabId;
  if (dartTab == null) {
    console.warn('Can\'t debug without a dart tab.');
    return null;
  }
  return DebugSession(int.parse(dartTab), debugInfo: debugInfo);
}

void _maybeReconnectToDwds() async {
  if (_debugSession != null) {
    window.console.log('Not reconnecting to DWDS, we have a debug session');
  }

  final newSession = await _createDebugSession();
  if (newSession == null) return;
  _debugSession = newSession;

  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));

  window.console.log('trying to reconnect to devtools');
  _connectToDwds(openDevTools: false);
}

void _stopDebugging() {
  if (_debugSession == null) return;
  _debugSession!.close();
  _debugSession = null;
  // TODO(elliette): Implement.
  window.console.log('Stopped debugging.');
}

_onDebuggerAttached() {
  final session = _debugSession;
  if (session == null) return;
  setStorageObject(
    type: StorageObject.debugState,
    json: DebugState.isDebugging.toJSON(),
    tabId: tabId,
  );

  chrome.debugger.sendCommand(session.debuggee, 'Runtime.enable', EmptyParam(),
      allowInterop((_) {
    final chromeError = chrome.runtime.lastError;
    if (chromeError != null) {
      window.alert(_translateChromeError(chromeError.message));
      return;
    }
  }));
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

void _handleExecutionContextCreated(Debuggee source, Object? params) {
  if (params == null) return;
  final session = _debugSession;
  if (session == null) return;

  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String;
  if (contextOrigin == session.debugInfo.origin) {
    final contextId = context['id'] as int;
    chrome.storage.local.set(
        ContextIdStorageObject(
          contextIdJson: ContextId(contextId: contextId).toJSON(),
        ),
        /*callback*/ allowInterop(_connectToDwds));
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
  final session = _debugSession;
  if (session == null) return;
  final extensionUri = session.debugInfo.extensionUri;
  if (extensionUri == null) return;

  final uri = Uri.parse(extensionUri);
  final authenticated = await _authenticateUser(uri, session.tabId);
  if (!authenticated) return;
  final client = _createClient(uri);
  _debugSession!.socketClient = client;

  // Listen to events from DWDS:
  client.stream.asBroadcastStream().listen(
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
      .sendCommand(session.debuggee, message.command, js_util.jsify(params),
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

  final tabUrl = await _getTabUrl(session.tabId);
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = session.debugInfo.appId
    ..instanceId = session.debugInfo.instanceId
    ..contextId = contextId
    ..tabUrl = tabUrl
    ..uriOnly = false))));
}

Future<bool> _authenticateUser(Uri uri, int tabId) async {
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
      chrome.debugger.detach(Debuggee(tabId: tabId), allowInterop(() {}));
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

SocketClient _createClient(Uri uri) {
  if (uri.isScheme('ws') || uri.isScheme('wss')) {
    return WebSocketClient(WebSocketChannel.connect(uri));
  }
  return SseSocketClient(SseClient(uri.toString()));
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
