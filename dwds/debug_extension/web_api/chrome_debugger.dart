// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS('chrome.debugger')
class ChromeDebugger {
  @JS('attach')
  external static void attach(
      Debuggee target, String requiredVersion, Function callback);

  @JS('detach')
  external static void detach(Debuggee target, Function callback);

  @JS('sendCommand')
  external static void sendCommand(
      Debuggee target, String method, Object? commandParams, Function callback);
}

@JS('chrome.debugger.onDetach')
class ChromeDebuggerOnDetach {
  @JS('addListener')
  external static dynamic addListener(Function callback);
}

@JS('chrome.debugger.onEvent')
class ChromeDebuggerOnEvent {
  @JS('addListener')
  external static dynamic addListener(Function callback);
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
