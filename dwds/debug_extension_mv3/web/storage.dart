// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library storage;

import 'package:js/js.dart';
import 'dart:async';

import 'chrome_api.dart';

enum StorageObject {
  dartTab,
  debugInfo;

  String get keyName {
    switch (this) {
      case StorageObject.dartTab:
        return 'dartTabJson';
      case StorageObject.debugInfo:
        return 'debugInfoJson';
    }
  }
}

Future<String?> fetchStorageObjectJson(StorageObject object) {
  final completer = new Completer<String?>();
  chrome.storage.local.get([object.keyName], allowInterop((Object result) {
    String? json;
    switch (object) {
      case StorageObject.debugInfo:
        final debugInfoObject = result as DebugInfoStorageObject;
        json = debugInfoObject.debugInfoJson;
        break;
      case StorageObject.dartTab:
        final dartTabObject = result as DartTabStorageObject;
        json = dartTabObject.dartTabJson;
        break;
    }
    completer.complete(json);
  }));
  return completer.future;
}

@JS()
@anonymous
class DebugInfoStorageObject {
  external String? get debugInfoJson;
  external factory DebugInfoStorageObject({String debugInfoJson});
}

@JS()
@anonymous
class DartTabStorageObject {
  external String? get dartTabJson;
  external factory DartTabStorageObject({String dartTabJson});
}
