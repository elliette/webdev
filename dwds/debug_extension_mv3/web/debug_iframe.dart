// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_iframe;

import 'dart:convert';
import 'dart:html';
import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/connect_request.dart';
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
DebugInfo? _debugInfo;

late String tabId;
late Debuggee debuggee;

bool reconnecting = false;

// cl/478639188 / mv3-work 
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
  if (debugStateJson == null) {
    // send message to injected client to connect to the app
    console.log('[IFRAME] Not debugging, send ready message to injected client.');
    _sendReadyMessageToInjectedClient();
    return;
  }

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
    case DebugState.isConnecting:
      // Don't do anything if we are currently trying to connect to DWDS.
      break;
  }
}

void _sendReadyMessageToInjectedClient() async {
  final clientWindow = window.parent;
  if (clientWindow == null) {
    console.warn('Did not find IFRAME parent.');
    return;
  }
  final debugInfo = await _getDebugInfo();
  final clientOrigin = debugInfo.origin;
  if (clientOrigin == null) {
    console.warn('Cannot send message without origin');
    return;
  }
  clientWindow.postMessage('dart-extension-ready', clientOrigin);
}

void _maybeReconnectToDwds() {
  if (_debugSession != null) return;
  _connectToDwds(reconnecting: true);
}

void _startDebugging() {
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
    json: DebugState.isConnecting.toJSON(),
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

void _onDebuggerEvent(Debuggee source, String method, Object? params) {
  if (method == 'Runtime.executionContextCreated') {
    _handleExecutionContextCreated(source, params);
  }

  _forwardChromeDebuggerEventToDwds(source, method, params);
}

void _forwardChromeDebuggerEventToDwds(
    Debuggee source, String method, dynamic params) async {
  final session = _debugSession;
  if (session == null) return;

  final event = _extensionEventFor(method, params);
  session.sendEvent(event);
}

void _handleExecutionContextCreated(Debuggee source, Object? params) async {
  if (params == null) return;

  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String;
  final debugInfo = await _getDebugInfo();
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

void _connectToDwds({bool reconnecting = false}) async {
  final contextIdJson = await fetchStorageObjectJson(
    type: StorageObject.contextId,
    tabId: tabId,
  );
  if (contextIdJson == null) {
    console.warn('Can\'t connect to DWDS without a context ID.');
    return;
  }
  final contextId = ContextId.fromJSON(contextIdJson).contextId;
  final debugInfo = await _getDebugInfo();
  final extensionUri = debugInfo.extensionUri;
  if (extensionUri == null) return;

  final uri = Uri.parse(extensionUri);
  final authenticated = await _authenticateUser(uri);
  if (!authenticated) return;
  final client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  _debugSession = DebugSession(client, int.parse(tabId), debugInfo.appId!);
  setStorageObject(
    type: StorageObject.debugState,
    json: DebugState.isDebugging.toJSON(),
    tabId: tabId,
  );

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

  if (reconnecting) {
    console.log('[IFRAME] Reconnected to DWDS, sending ready message to injected client.');
    _sendReadyMessageToInjectedClient();
  } else {
    _sendDevToolsRequest(client, contextId);
  }
}

void _routeDwdsEvent(String eventData, SocketClient client) async {
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
        final url = message.params;
        await _handleDevToolsUrl(url);
        break;
    }
  }
}

Future<void> _handleDevToolsUrl(String url) async {
  final json = await fetchStorageObjectJson(
    type: StorageObject.devToolsTab,
    tabId: tabId,
  );
  if (json != null) {
    final devToolsTab = DevToolsTab.fromJSON(json);
    final expectedUrl =
        _getQueryParameter(url: devToolsTab.tabUrl, param: 'uri');
    final actualUrl = _getQueryParameter(
        url: await _getTabUrl(devToolsTab.tabId), param: 'uri');

    if (expectedUrl == actualUrl) {
      console.log('Not opening $url, already have $actualUrl');
      return;
    }
  }

  final completer = Completer<void>();
  chrome.tabs.create(
      TabInfo(
        active: false, // Figure out why host permissions fail if set to true.
        pinned: false,
        url: url,
      ), allowInterop((Tab tab) async {
    final id = tab.id;
    final tabUrl = await _getTabUrl(id);
    setStorageObject(
        type: StorageObject.devToolsTab,
        json: DevToolsTab(
          tabId: id,
          tabUrl: tabUrl,
        ).toJSON(),
        tabId: tabId,
        callback: () {
          completer.complete();
        });
  }));
  return completer.future;
}

void _forwardDwdsEventToChromeDebugger(
    ExtensionRequest message, SocketClient client) {
  final session = _debugSession;
  if (session == null) return;

  final messageParams = message.commandParams ?? '{}';
  final params = BuiltMap<String, Object>(json.decode(messageParams)).toMap();
  console.log('[IFRAME] Forwarding ${message.command} to Chrome Debugger.');

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
  final debugInfo = await _getDebugInfo();

  final tabUrl = await _getTabUrl(int.parse(tabId));
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = debugInfo.appId
    ..instanceId = debugInfo.instanceId
    ..contextId = contextId
    ..tabUrl = tabUrl
    ..uriOnly = true))));
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

Future<String> _getTabUrl(int tabId, {int retries = 3}) async {
  final tab = await promiseToFuture<Tab?>(chrome.tabs.get(tabId));
  final tabUrl = tab?.url ?? '';
  if (tabUrl.isNotEmpty || retries == 0) {
    return tabUrl;
  }

  await Future.delayed(Duration(seconds: 1));
  return _getTabUrl(tabId, retries: retries - 1);
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

Future<DebugInfo> _getDebugInfo() async {
  if (_debugInfo != null) return _debugInfo!;
  final debugInfoJson =
      await fetchStorageObjectJson(type: StorageObject.debugInfo, tabId: tabId);
  if (debugInfoJson == null) {
    throw Exception('Can\'t debug without debug info.');
  }
  _debugInfo = DebugInfo.fromJSON(debugInfoJson);
  return _debugInfo!;
}

String _getQueryParameter({required String url, required String param}) {
  final uri = Uri.dataFromString(url);
  return uri.queryParameters[param] ?? '';
}
