// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debugInfo;

import 'dart:html';
import 'dart:js';

import 'package:js/js.dart';

import 'messaging.dart';

void main() {
  final scriptElement = document.getElementById('debugInfoScript');
  window.console.log('SCRIPT ELEMENT IS $scriptElement');
  final tabId = scriptElement?.dataset['tabid'];
  // final dartTabId = scriptElement?.getAttribute('data-tabid');
  window.console.log('DART TAB ID IS!!!  $tabId');

  // Send a message to the IFRAME with the debug info.
  _sendMessageToIframe(
    type: MessageType.debugInfo,
    encodedBody: _readDartDebugInfo().toJSON(),
  );
}

DebugInfo _readDartDebugInfo() {

  final scriptElement = document.getElementById('debugInfoScript');
  window.console.log('SCRIPT ELEMENT IS $scriptElement');
  final tabId = scriptElement?.dataset['tabid'];
  // final dartTabId = scriptElement?.getAttribute('data-tabid');
  window.console.log('DART TAB ID IS!!!  $tabId');

  final origin = window.location.origin;
  final windowContext = JsObject.fromBrowserObject(window);
  final extensionUri = windowContext['\$dartExtensionUri'];
  final appId = windowContext['\$dartAppId'];
  final instanceId = windowContext['\$dartAppInstanceId'];
  return DebugInfo(
    origin: origin,
    extensionUri: extensionUri,
    appId: appId,
    instanceId: instanceId,
  );
}

void _sendMessageToIframe({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.iframe,
    from: Script.debugInfo,
    type: type,
    encodedBody: encodedBody,
  );
  final iframe =
      document.getElementById('writer_iframe') as IFrameElement;
  iframe.contentWindow?.postMessage(message.toJSON(), '*');
}
