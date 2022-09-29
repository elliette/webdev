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
  devToolsTab,
  debugState,
  debugInfo;

  String get keyName {
    switch (this) {
      case StorageObject.contextId:
        return 'contextIdJson';
      case StorageObject.dartTab:
        return 'dartTabJson';
      case StorageObject.devToolsTab:
        return 'devToolsTabJson';
      case StorageObject.debugInfo:
        return 'debugInfoJson';
      case StorageObject.debugState:
        return 'debugStateJson';
    }
  }
}

Future<bool> setStorageObject({
  required StorageObject type,
  required String json,
  required String tabId,
  void Function()? callback,
}) {
  final storageKey = '$tabId-${type.keyName}';
  final map = <String, String>{storageKey: json};
    final completer = new Completer<bool>();
  chrome.storage.local.set(jsify(map), allowInterop(() {
    console.log('--- setting { $storageKey: $json }.');
    if (callback != null) {
      callback();
    }
        completer.complete(true);
  }));
    return completer.future;
}

Future<String?> fetchStorageObjectJson({
  required StorageObject type,
  required String tabId,
}) {
  final storageKey = '$tabId-${type.keyName}';
  final completer = new Completer<String?>();
  chrome.storage.local.get([storageKey], allowInterop((Object result) {
    final json = getProperty(result, storageKey) as String?;
    console.log('--- fetching { $storageKey: $json }.');
    completer.complete(json);
  }));
  return completer.future;
}

Future<bool> removeStorageObject({
  required StorageObject type,
  required String tabId,
}) {
  final storageKey = '$tabId-${type.keyName}';
  final completer = new Completer<bool>();
  chrome.storage.local.remove([storageKey], allowInterop(() {
    console.log('--- removed $storageKey.');
    completer.complete(true);
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

@JS()
@anonymous
class DevToolsTabStorageObject {
  external String? get devToolsTabJson;
  external factory DevToolsTabStorageObject({String devToolsTabJson});
}

class DevToolsTab {
  final int tabId;
  final String tabUrl;

  DevToolsTab({required this.tabId, required this.tabUrl});

  factory DevToolsTab.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final tabId = decoded['tabId'] as int;
    final tabUrl = decoded['tabUrl'] as String;
    return DevToolsTab(tabId: tabId, tabUrl: tabUrl);
  }

  String toJSON() {
    return jsonEncode({'tabId': tabId, 'tabUrl': tabUrl});
  }
}
