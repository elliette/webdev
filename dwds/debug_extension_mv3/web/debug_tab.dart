// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_tab;

import 'dart:convert';
import 'dart:html';

import 'package:collection/collection.dart' show IterableExtension;
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

const _authenticationPath = '\$dwdsExtensionAuthentication';

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

final _channel = BroadcastChannel(debugTabChannelName);

final _debugSessions = <DebugSession>[];

late final int _tabId;
late final String _origin;
late final String _extensionUri;
late final String _appId;
late final String _instanceId;

void main() {
  _registerListeners();
}

void _registerListeners() {
  _channel.addEventListener(
    'message',
    allowInterop(_handleChannelMessageEvents),
  );
}

void _handleChannelMessageEvents(Event event) {
  final messageData =
      jsEventToMessageData(event, expectedOrigin: chrome.runtime.getURL(''));
  if (messageData == null) return;

  interceptMessage<DebugInfo>(
    message: messageData,
    expectedType: MessageType.debugInfo,
    expectedSender: Script.iframe,
    expectedRecipient: Script.debugTab,
    messageHandler: _debugInfoMessageHandler,
  );
}

void _debugInfoMessageHandler(DebugInfo message) {
  _tabId = message.tabId!;
  _origin = message.origin!;
  _extensionUri = message.extensionUri!;
  _appId = message.appId!;
  _instanceId = message.instanceId!;

  _startDebugging();
}

void _startDebugging() {
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
  chrome.debugger.attach(
      Debuggee(tabId: _tabId), '1.3', allowInterop(_onDebuggerAttached));
}

_onDebuggerAttached() {
  chrome.debugger
      .sendCommand(Debuggee(tabId: _tabId), 'Runtime.enable', EmptyParam(),
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

void _handleExecutionContextCreated(Debuggee source, Object? params) {
  if (params == null) return;
  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String;
  if (contextOrigin == _origin) {
    final contextId = context['id'] as int;
    _connectToDwds(contextId);
  }
}

void _connectToDwds(int contextId) async {
  final uri = Uri.parse(_extensionUri);
  final authenticated = await _authenticateUser(uri, _tabId);
  if (!authenticated) return;
  final client = _createClient(uri);
  _debugSessions.add(DebugSession(client, _tabId, _appId));

  // Listen to events from DWDS:
  client.stream.listen(
    (data) => _routeDwdsEvent(data, client),
    onDone: () {
      console.log('Closing debug connection with DWDS.');
      _removeAndDetachDebugSessionForTab(_tabId);
    },
    onError: (_) {
      console.warn('Received error, closing debug connection with DWDS.');
      _removeAndDetachDebugSessionForTab(_tabId);
    },
    cancelOnError: true,
  );

  _sendDevToolsRequest(client, contextId);
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
        _injectDevToolsIframe(message.params);
        break;
    }
  }
}

void _forwardDwdsEventToChromeDebugger(
    ExtensionRequest message, SocketClient client) {
  final messageParams = message.commandParams ?? '{}';
  final params = BuiltMap<String, Object>(json.decode(messageParams)).toMap();
  chrome.debugger.sendCommand(
      Debuggee(tabId: _tabId), message.command, js_util.jsify(params),
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
  final tabUrl = await _getTabUrl(_tabId);
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = _appId
    ..instanceId = _instanceId
    ..contextId = contextId
    ..tabUrl = tabUrl
    ..uriOnly = true))));
}

void _injectDevToolsIframe(String devToolsUri) {
  final iframe = document.createElement('iframe');
  iframe.setAttribute('src', devToolsUri);
  iframe.setAttribute('scrolling', 'no');
  final iframeContainer =
      document.getElementById('dartDevToolsIframeContainer') as DivElement;
  iframeContainer.append(iframe);
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

// Tries to remove the debug session for the specified tab, and detach the
// debugger associated with that debug session.
void _removeAndDetachDebugSessionForTab(int tabId) {
  final removedTabId = _removeDebugSessionForTab(tabId);

  if (removedTabId != -1) {
    chrome.debugger.detach(Debuggee(tabId: removedTabId), allowInterop(() {}));
  }
}

// Tries to remove the debug session for the specified tab. If no session is
// found, returns -1. Otherwise returns the tab ID.
int _removeDebugSessionForTab(int tabId) {
  final session = _debugSessions.firstWhereOrNull(
      (session) => session.appTabId == tabId || session.devtoolsTabId == tabId);
  if (session != null) {
    // Note: package:sse will try to keep the connection alive, even after the
    // client has been closed. Therefore the extension sends an event to notify
    // DWDS that we should close the connection, instead of relying on the done
    // event sent when the client is closed. See details:
    // https://github.com/dart-lang/webdev/pull/1595#issuecomment-1116773378
    final event =
        _extensionEventFor('DebugExtension.detached', js_util.jsify({}));
    session.sendEvent(event);
    session.close();
    _debugSessions.remove(session);

    return session.appTabId;
  } else {
    return -1;
  }
}


@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
