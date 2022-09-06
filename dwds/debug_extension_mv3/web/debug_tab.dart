// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_tab;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

final _channel = BroadcastChannel(debugTabChannelName);

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
  final tabId = message.tabId;
  if (tabId != null) {
    _startDebugging(tabId);
  }
}

void _startDebugging(int tabId) {
  final debuggee = Debuggee(tabId: tabId);
  chrome.debugger.attach(debuggee, '1.3', allowInterop(() async {
    chrome.debugger.sendCommand(debuggee, 'Runtime.enable', EmptyParam(),
        allowInterop((_) {
      final chromeError = chrome.runtime.lastError;
      if (chromeError != null) {
        window.alert(_translateChromeError(chromeError.message));
        return;
      }
      chrome.debugger.sendCommand(Debuggee(tabId: tabId), 'Runtime.enable',
          EmptyParam(), allowInterop((_) {}));
    }));
  }));
}

String _translateChromeError(String chromeErrorMessage) {
  if (chromeErrorMessage.contains('Cannot access') ||
      chromeErrorMessage.contains('Cannot attach')) {
    return _notADartAppAlert;
  }
  return _devToolsAlreadyOpenedAlert;
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
