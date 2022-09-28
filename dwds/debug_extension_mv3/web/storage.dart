// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library storage;

import 'dart:convert';
import 'dart:js_util';

import 'package:js/js.dart';
import 'dart:async';

import 'chrome_api.dart';
import 'web_api.dart';

enum StorageObject {
  contextId,
  dartTab,
  debugState,
  debugInfo;

  String get keyName {
    switch (this) {
      case StorageObject.contextId:
        return 'contextIdJson';
      case StorageObject.dartTab:
        return 'dartTabJson';
      case StorageObject.debugInfo:
        return 'debugInfoJson';
      case StorageObject.debugState:
        return 'debugStateJson';
    }
  }
}

void setStorageObject({
  required StorageObject type,
  required String json,
  required String tabId,
  void Function()? callback,
}) {
  final storageKey = '$tabId-${type.keyName}';
  final map = <String, String>{storageKey: json};
  chrome.storage.local.set(jsify(map), allowInterop(() {
    console.log('Set storage item: $map.');
    if (callback != null) {
      callback();
    }
  }));
}

Future<String?> fetchStorageObjectJson({
  required StorageObject type,
  required String tabId,
}) {
  final storageKey = '$tabId-${type.keyName}';
  final completer = new Completer<String?>();
  chrome.storage.local.get([storageKey], allowInterop((Object result) {
    final json = getProperty(result, storageKey) as String?;
    console.log('Fetched storage item for $storageKey: $json.');
    completer.complete(json);
  }));
  return completer.future;
}

@JS()
@anonymous
class ContextIdStorageObject {
  external String? get contextIdJson;
  external factory ContextIdStorageObject({String contextIdJson});
}

class ContextId {
  final int contextId;

  ContextId({required this.contextId});

  factory ContextId.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final contextId = decoded['contextId'] as int;
    return ContextId(contextId: contextId);
  }

  String toJSON() {
    return jsonEncode({'contextId': contextId});
  }
}
