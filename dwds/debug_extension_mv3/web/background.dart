// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_types.dart';
import 'lifeline_ports.dart';
import 'messaging.dart';
import 'storage.dart';
import 'web_api.dart';

const _authenticationPath = '\$dwdsExtensionAuthentication';

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

final _debugSessions = <DebugSession>[];

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  chrome.tabs.onRemoved
      .addListener(allowInterop((tabId, _) => maybeRemoveLifelinePort(tabId)));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop(_maybeAttachDebugger));
}

<<<<<<< HEAD
Future<void> _maybeAttachDebugger(Tab currentTab) async {
  final tabId = currentTab.id;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
  if (debugInfo == null) {
    console.warn('Current tab is not debuggable.');
    return;
  }
  maybeCreateLifelinePort(tabId);
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
  chrome.debugger.attach(
    Debuggee(tabId: tabId),
    '1.3',
    allowInterop(
      () => _enableExecutionContextReporting(tabId),
    ),
  );

  // final devToolsOpener = await fetchStorageObject<DevToolsOpener>(
  //     type: StorageObject.devToolsOpener);
  // await _createTab('https://dart.dev/',
  //     inNewWindow: devToolsOpener?.newWindow ?? false);
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;

  interceptMessage<DebugInfo>(
      message: jsRequest,
      expectedType: MessageType.debugInfo,
      expectedSender: Script.detector,
      expectedRecipient: Script.background,
      messageHandler: (DebugInfo debugInfo) async {
        final currentTab = await _getTab();
        final currentUrl = currentTab?.url ?? '';
        final appUrl = debugInfo.appUrl ?? '';
        if (currentTab == null ||
            currentUrl.isEmpty ||
            appUrl.isEmpty ||
            currentUrl != appUrl) {
          console.warn(
              'Dart app detected at $appUrl but current tab is $currentUrl.');
          return;
        }
        // Save the debug info for the Dart app in storage:
        await setStorageObject<DebugInfo>(
            type: StorageObject.debugInfo,
            value: debugInfo,
            tabId: currentTab.id);
        // Update the icon to show that a Dart app has been detected:
        chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
      });
}

void _onDebuggerEvent(Debuggee source, String method, Object? params) {
  if (method == 'Runtime.executionContextCreated') {
    _handleExecutionContextCreated(source, params);
  }

  _forwardChromeDebuggerEventToDwds(source, method, params);
}

_enableExecutionContextReporting(int tabId) {
  // Runtime.enable enables reporting of execution contexts creation by means of
  // executionContextCreated event. When the reporting gets enabled the event
  // will be sent immediately for each existing execution context:
  chrome.debugger.sendCommand(
      Debuggee(tabId: tabId), 'Runtime.enable', EmptyParam(), allowInterop((_) {
    final chromeError = chrome.runtime.lastError;
    if (chromeError != null) {
      window.alert(_translateChromeError(chromeError.message));
      return;
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

Future<Tab?> _getTab() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
}

Future<Tab> _createTab(String url, {bool inNewWindow = false}) async {
  if (inNewWindow) {
    final windowPromise = chrome.windows.create(
      WindowInfo(focused: true, url: url),
    );
    final windowObj = await promiseToFuture<WindowObj>(windowPromise);
    return windowObj.tabs.first;
  }
  final tabPromise = chrome.tabs.create(TabInfo(
    active: true,
    url: url,
  ));
  return promiseToFuture<Tab>(tabPromise);
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
