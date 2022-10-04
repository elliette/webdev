// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:convert';
import 'dart:html';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'storage.dart';

late int tabId;
void main() async {
  _registerListeners();
  tabId = await _getTabId() ?? -1;

  // Send a message to the injector script so that it has access to the tab.
  _sendMessageToIframeInjector(
    type: MessageType.dartTab,
    encodedBody: DartTab(tabId: tabId).toJSON(),
  );
}

void _registerListeners() {
  window.addEventListener('message', allowInterop(_handleWindowMessages));
}

void _sendMessageToIframeInjector({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.iframeInjector,
    from: Script.iframe,
    type: type,
    encodedBody: encodedBody,
  );
  window.parent?.postMessage(message.toJSON(), '*');
}

void _handleWindowMessages(Event event) {
  final messageData = jsEventToMessageData(event);
  if (messageData == null) return;

  interceptMessage<DebugInfo>(
      message: messageData,
      expectedType: MessageType.debugInfo,
      expectedSender: Script.debugInfo,
      expectedRecipient: Script.iframe,
      messageHandler: (DebugInfo message) {
        // setStorageObject(
        //   type: StorageObject.debugInfo,
        //   json: message.toJSON(),
        //   tabId: tabId,
        // );
      });
}

// TODO: Move into shared file.
Future<int?> _getTabId() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  final tab = tabs.isNotEmpty ? tabs.first : null;
  return tab?.id;
}
