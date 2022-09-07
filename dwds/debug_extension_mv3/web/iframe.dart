// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

final _channel = BroadcastChannel(debugTabChannelName);

int? _tabId;
DebugInfo? _debugInfo;
bool _messageSent = false;

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
  window.addEventListener(
    'message',
    allowInterop(_handleWindowMessageEvents),
  );
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
          if (_debugInfo != null && !_messageSent) {
            _sendMessageToDebugTab(senderTabId, _debugInfo!);
          } else {
            _tabId = senderTabId;
          }
        }
      });
}

void _handleWindowMessageEvents(Event event) {
  final messageData = jsEventToMessageData(event);
  if (messageData == null) return;

  interceptMessage<DebugInfo>(
      message: messageData,
      expectedType: MessageType.debugInfo,
      expectedSender: Script.debugInfo,
      expectedRecipient: Script.iframe,
      messageHandler: (DebugInfo message) {
        if (_tabId != null && !_messageSent) {
          _sendMessageToDebugTab(_tabId!, message);
        } else {
          _debugInfo = message;
        }
      });
}

void _sendMessageToDebugTab(int tabId, DebugInfo debugInfo) {
  final encodedBody = new DebugInfo(
    tabId: tabId,
    origin: debugInfo.origin,
    extensionUri: debugInfo.extensionUri,
    appId: debugInfo.appId,
    instanceId: debugInfo.instanceId,
  ).toJSON();
  final message = Message(
    to: Script.debugTab,
    from: Script.iframe,
    type: MessageType.debugInfo,
    encodedBody: encodedBody,
  );
  _channel.postMessage(message.toJSON());
  _messageSent = true;
}
