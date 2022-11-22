// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import 'package:js/js.dart';
import 'chrome_api.dart';
import 'debugging.dart';

void main() async {
  registerDebugEventListeners();

  final tab = await _getTab();
  if (tab == null) return;
  attachDebugger(tab.id);
}

Future<Tab?> _getTab() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
}