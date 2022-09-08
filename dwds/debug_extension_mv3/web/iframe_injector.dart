// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:js';

import 'chrome_api.dart';
import 'messaging.dart';

void main() {
  _registerListeners();

  // Inject the IFRAMEs into the current tab.
  _injectIframe('writer_iframe');
  _injectIframe('debug_iframe');
}

void _registerListeners() {
  window.addEventListener(
    'message',
    allowInterop(_handleWindowMessageEvents),
  );
}

void _injectIframe(String name) {
  final iframe = document.createElement('iframe');
  final iframeSrc = chrome.runtime.getURL('$name.html');
  iframe.setAttribute('src', iframeSrc);
  iframe.setAttribute('id', name);
  document.body?.append(iframe);
}

void _handleWindowMessageEvents(Event event) {
  final messageData =
      jsEventToMessageData(event, expectedOrigin: chrome.runtime.getURL(''));
  if (messageData == null) return;

  interceptMessage<IframeReady>(
    message: messageData,
    expectedType: MessageType.iframeReady,
    expectedSender: Script.iframe,
    expectedRecipient: Script.iframeInjector,
    messageHandler: _iframeReadyMessageHandler,
  );
}

void _iframeReadyMessageHandler(IframeReady message) {
  if (message.isReady != true) return;
  // Inject a script to fetch debug info global variables.
  _injectDebugInfoScript();

  // Send a message back to IFRAME so that it has access to the tab ID.
  _sendMessageToIframe(
      type: MessageType.debugState,
      encodedBody: DebugState(shouldDebug: true).toJSON());
}

void _injectDebugInfoScript() {
  final script = document.createElement('script');
  final scriptSrc = chrome.runtime.getURL('debug_info.dart.js');
  script.setAttribute('type', 'module');
  script.setAttribute('src', scriptSrc);
  document.head?.append(script);
}

void _sendMessageToIframe({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.iframe,
    from: Script.iframeInjector,
    type: type,
    encodedBody: encodedBody,
  );
  chrome.runtime.sendMessage(
    /*id*/ null,
    message.toJSON(),
    /*options*/ null,
    /*callback*/ null,
  );
}
