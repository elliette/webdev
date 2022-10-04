// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'storage.dart';
import 'web_api.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  // chrome.webNavigation.onCommitted
  //     .addListener(allowInterop(_maybeReinjectIframe));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop((_) async {
    final tabId = await _getTabId();
    // _executeInjectorScript();
    setStorageObject(
      type: StorageObject.debugState,
      json: DebugState.startDebugging.toJSON(),
      tabId: '$tabId',
    );
  }));

  chrome.debugger.onDetach.addListener(allowInterop(_onDebuggerDetach));

  // When a Dart application tab is closed, detach the corresponding debug
  // session:
  chrome.tabs.onRemoved.addListener(allowInterop(_detachDebuggerForTab));
}

// void _maybeReinjectIframe(NavigationInfo navigationInfo) async {
//   if (['reload', 'typed'].contains(navigationInfo.transitionType)) {
//     final json = await fetchStorageObjectJson(
//         type: StorageObject.devToolsTab, tabId: '${navigationInfo.tabId}');
//     if (json != null) {
//       _executeInjectorScript();
//     }
//   }
// }

void _onDebuggerDetach(Debuggee source, String _) async {
  final isDartAppBeingDebugged = await _isDartAppBeingDebugged(source.tabId);
  if (!isDartAppBeingDebugged) return;

  // Remove the corresponding Dart DevTools:
  final json = await fetchStorageObjectJson(
      type: StorageObject.devToolsTab, tabId: '${source.tabId}');
  if (json != null) {
    final devToolsTab = DevToolsTab.fromJSON(json).tabId;
    chrome.tabs.remove([devToolsTab], /*callback=*/ null);
  }

  // Update storage objects to notify debug_iframe to stop debugging:
  await removeStorageObject(
    type: StorageObject.devToolsTab,
    tabId: '${source.tabId}',
  );
  await setStorageObject(
    type: StorageObject.debugState,
    json: DebugState.stopDebugging.toJSON(),
    tabId: '${source.tabId}',
  );
}

void _detachDebuggerForTab(int tabId, _) async {
  final shouldDetach = await _isDartAppBeingDebugged(tabId);
  if (shouldDetach) {
    chrome.debugger.detach(Debuggee(tabId: tabId), allowInterop(() {}));
  }
}

Future<bool> _isDartAppBeingDebugged(int tabId) async {
  // Verify that the tab is for a Dart app:
  final json = await fetchStorageObjectJson(
    type: StorageObject.debugState,
    tabId: '$tabId',
  );
  if (json == null) return false;

  final debugState = DebugState.fromJSON(json);
  return debugState == DebugState.isDebugging;
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;

  final tabId = await _getTabId();
  if (tabId == null) return;
  final id = '${tabId}';

  interceptMessage<DebugInfo>(
      message: jsRequest,
      expectedType: MessageType.debugInfo,
      expectedSender: Script.detector,
      expectedRecipient: Script.background,
      messageHandler: (DebugInfo message) async {
        chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
        final json = await fetchStorageObjectJson(
            type: StorageObject.debugInfo, tabId: id);
        if (json == message.toJSON()) {
          console.log('Not setting debug info, already set.');
        } else {
          setStorageObject(
              type: StorageObject.debugInfo, json: message.toJSON(), tabId: id);
        }
        // Inject the debug IFRAME:
        console.log('EXECUTING INJECTOR SCRIPT, WE HAVE A DART APP.');
        _executeInjectorScript();
      });
}

Future<void> _executeInjectorScript() async {
  final tabId = await _getTabId();
  if (tabId != null) {
    chrome.scripting.executeScript(
      InjectDetails(
          target: Target(tabId: tabId), files: ['iframe_injector.dart.js']),
      /*callback*/ null,
    );
  }
}

Future<int?> _getTabId() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  final tab = tabs.isNotEmpty ? tabs.first : null;
  return tab?.id;
}
