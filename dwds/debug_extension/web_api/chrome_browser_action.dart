// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
class ChromeBrowserAction {
  @JS('chrome.browserAction.onClicked.addListener')
  external static void onClickedAddListener(Function callback);

  @JS('chrome.browserAction.setIcon')
  external static void setIcon(IconInfo iconInfo);
}

@JS()
@anonymous
class IconInfo {
  external String get path;
  external factory IconInfo({String path});
}
