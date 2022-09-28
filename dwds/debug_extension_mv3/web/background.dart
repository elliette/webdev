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

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop((_) async {
    final tabId = await _getTabId();
    setStorageObject(
      type: StorageObject.debugState,
      json: DebugState.startDebugging.toJSON(),
      tabId: '$tabId',
    );
  }));

  // When a Dart application tab is closed, detach the corresponding debug
  // session:
  chrome.tabs.onRemoved.addListener(allowInterop(_detachDebuggerForTab));
}

// Tries to remove the debug session for the specified tab, and detach the
// debugger associated with that debug session.
void _detachDebuggerForTab(int tabId, _) {
  // TODO: only detach debugger if we are debugging that tab (check Chrome storage).
  // Change DebugState in Chrome storage to not debugging.
  chrome.debugger.detach(Debuggee(tabId: tabId), allowInterop(() {}));
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) {
  if (jsRequest is! String) return;

  interceptMessage<DartAppDetected>(
      message: jsRequest,
      expectedType: MessageType.dartAppDetected,
      expectedSender: Script.detector,
      expectedRecipient: Script.background,
      messageHandler: (DartAppDetected message) {
        _handleDartAppDetected(message);
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

void _handleDartAppDetected(DartAppDetected message) {
  if (message.detected) {
    _executeInjectorScript();
    chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
  }
}

Future<int?> _getTabId() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  final tab = tabs.isNotEmpty ? tabs.first : null;
  return tab?.id;
}
