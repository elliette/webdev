// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
class ChromeDebugger {
  @JS('chrome.debugger.attach')
  external static void attach(
      Debuggee target, String requiredVersion, Function callback);

  @JS('chrome.debugger.detach')
  external static void detach(Debuggee target, Function callback);

  @JS('chrome.debugger.onDetach.addListener')
  external static dynamic onDetachAddListener(Function callback);

  @JS('chrome.debugger.onEvent.addListener')
  external static dynamic onEventAddListener(Function callback);

  @JS('chrome.debugger.sendCommand')
  external static void sendCommand(
      Debuggee target, String method, Object? commandParams, Function callback);
}

@JS()
@anonymous
class Debuggee {
  external int get tabId;
  external String get extensionId;
  external String get targetId;
  external factory Debuggee({int tabId, String? extensionId, String? targetId});
}

@JS()
@anonymous
class SendCommandOptions {
  external String get method;
  external Object get commandParams;
}
