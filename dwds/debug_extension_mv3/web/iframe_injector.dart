// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';

import 'chrome_api.dart';

void main() {
  // Inject the IFRAME into the current tab.
  _injectIframe();
}

void _injectIframe() {
  final iframe = document.createElement('iframe');
  final iframeSrc = chrome.runtime.getURL('iframe.html');
  iframe.setAttribute('src', iframeSrc);
  iframe.setAttribute('id', 'dartDebugExtensionIframe');
  document.body?.append(iframe);
}