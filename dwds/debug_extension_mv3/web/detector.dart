// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:html';
import 'package:js/js.dart';
import 'dart:js_util';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

bool dartAppReady = false;
bool isLoaded = false;
String? debugInfo;

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.onReadyStateChange.listen((_) {
    if (isLoaded) return;
    if (document.readyState != 'complete') return;
    isLoaded = true;
    _maybeSendDartReadyMessage();
  });

  document.addEventListener('dart-app-ready', (_) {
    debugInfo = getProperty(_, 'detail') as String?;
    console.log('IN DETECTOR, debugInfo is $debugInfo');
    dartAppReady = true;
    _maybeSendDartReadyMessage();
  });
}

void _maybeSendDartReadyMessage() async {
  if (isLoaded && dartAppReady) {
    if (debugInfo == null) {
      console.warn('Can\'t debug without debug info.');
      return;
    }
    _sendMessageToBackground(
      type: MessageType.debugInfo,
      encodedBody: debugInfo!,
    );
  }
}

void _sendMessageToBackground({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.background,
    from: Script.detector,
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

