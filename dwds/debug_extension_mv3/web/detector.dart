// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:html';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

bool isDartApp = false;
bool isLoaded = false;

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
    isDartApp = true;
    _maybeSendDartReadyMessage();
  });
}

void _maybeSendDartReadyMessage() {
  if (isLoaded && isDartApp) {
    _sendMessageToBackground(
      type: MessageType.dartAppDetected,
      encodedBody: DartAppDetected(detected: true).toJSON(),
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

