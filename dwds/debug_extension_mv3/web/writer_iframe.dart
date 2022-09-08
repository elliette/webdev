// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'storage.dart';

void main() {
  _registerListeners();

  // Send a message to the injector script that the IFRAME has loaded.
  _sendMessageToIframeInjector(
    type: MessageType.iframeReady,
    encodedBody: IframeReady(isReady: true).toJSON(),
  );
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
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

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) {
  if (jsRequest is! String) return;

  interceptMessage<DebugState>(
      message: jsRequest,
      expectedType: MessageType.debugState,
      expectedSender: Script.iframeInjector,
      expectedRecipient: Script.iframe,
      messageHandler: (DebugState message) {
        final senderTabId = sender.tab?.id;
        if (senderTabId != null && message.shouldDebug) {
          chrome.storage.local.set(
              DartTabStorageObject(
                dartTabJson: DartTab(tabId: senderTabId).toJSON(),
              ),
              /*callback*/ null);
        }
      });
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
        chrome.storage.local.set(
            DebugInfoStorageObject(
              debugInfoJson: message.toJSON(),
            ),
            /*callback*/ null);
      });
}