// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:html';
import 'dart:js_util';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'logger.dart';
import 'messaging.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.addEventListener('dart-app-ready', _onDartAppReadyEvent);
}

void _onDartAppReadyEvent(Event event) {
  final debugInfo = getProperty(event, 'detail') as String?;
  if (debugInfo == null) {
    // TODO(elliette): Remove once DWDS 17.0.0 is in Flutter stable. If we are
    // on an older version of DWDS, then the debug info is not sent along with
    // the ready event. Therefore we must read it from the Window object, which
    // is slower.
    debugWarn(
        'No debug info sent with ready event, instead reading from Window.');
    _injectScript('debug_info');
  } else {
    _sendMessageToBackgroundScript(
      type: MessageType.debugInfo,
      body: debugInfo,
    );
  }
  _injectScript('auth_url');
}

void _injectScript(String scriptName) {
  final script = document.createElement('script');
  final scriptSrc = chrome.runtime.getURL('$scriptName.dart.js');
  script.setAttribute('src', scriptSrc);
  script.setAttribute('defer', true);
  document.head?.append(script);
}

void _sendMessageToBackgroundScript({
  required MessageType type,
  required String body,
}) {
  sendRuntimeMessage(
    type: type,
    body: body,
    sender: Script.detector,
    recipient: Script.background,
  );
}
