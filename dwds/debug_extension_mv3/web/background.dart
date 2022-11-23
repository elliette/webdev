// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as jsUtil;

import 'chrome_api.dart';
import 'debugging.dart';
import 'lifeline_ports.dart';
import 'messaging.dart';
import 'storage.dart';
import 'web_api.dart';

const _authenticationPath = '\$dwdsExtensionAuthentication';

bool injectIframe = false;

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

Future<void> _maybeAttachDebugger(Tab currentTab) async {
  final tabId = currentTab.id;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
  console.log('got $debugInfo');
  if (debugInfo == null) {
    console.warn('Current tab is not debuggable.');
    return;
  }
  if (debugInfo.extensionUrl == null) {
    console.warn('Can\'t connect to DWDS without an extension URL.');
    return;
  }
  final uri = Uri.parse(debugInfo.extensionUrl!);
  final authenticated = await _authenticateUser(uri, tabId);
  if (!authenticated) {
    console.warn('User is not authenticated.');
    return;
  }

  maybeCreateLifelinePort(tabId);
  if (injectIframe) {
    console.log('CONNECT TO DWDS IN IFRAME');
    await _executeInjectorScript(tabId);
  } else {
    console.log('CONNECT TO DWDS IN SERVICE WORKER');
    registerDebugEventListeners();
    attachDebugger(tabId);
  }
}

Future<void> _executeInjectorScript(int tabId) async {
  chrome.scripting.executeScript(
    InjectDetails(
        target: Target(tabId: tabId), files: ['iframe_injector.dart.js']),
    /*callback*/ null,
  );
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

Future<bool> _authenticateUser(Uri uri, int tabId) async {
  var authUri = uri.replace(path: _authenticationPath);
  if (authUri.scheme == 'ws') authUri = authUri.replace(scheme: 'http');
  if (authUri.scheme == 'wss') authUri = authUri.replace(scheme: 'https');
  final authUrl = authUri.toString();
  try {
    final response = await fetch(
      authUrl,
      FetchOptions(
        method: 'GET',
        credentialsOptions: CredentialsOptions(credentials: 'include'),
      ),
    );
    final authSuccess = jsUtil.getProperty<bool>(response, 'ok');
    if (!authSuccess) {
      throw Exception('Not authenticated.');
    }
  } catch (_) {
    await _createTab(authUrl, inNewWindow: false);
    return false;
  }
  return true;
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
