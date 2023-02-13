// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library utils;

import 'dart:async';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'logger.dart';

Future<Tab> createTab(String url, {bool inNewWindow = false}) {
  final completer = Completer<Tab>();
  if (inNewWindow) {
    chrome.windows.create(
      WindowInfo(focused: true, url: url),
      allowInterop(
        (WindowObj windowObj) {
          completer.complete(windowObj.tabs.first);
        },
      ),
    );
  } else {
    chrome.tabs.create(
      TabInfo(
        active: true,
        url: url,
      ),
      allowInterop(
        (Tab tab) {
          completer.complete(tab);
        },
      ),
    );
  }
  return completer.future;
}

Future<Tab?> getTab(int tabId) {
  final completer = Completer<Tab?>();
  chrome.tabs.get(tabId, allowInterop((tab) {
    completer.complete(tab);
  }));
  return completer.future;
}

Future<Tab?> get activeTab async {
  final completer = Completer<Tab?>();
  final query = QueryInfo(active: true, currentWindow: true);
  chrome.tabs.query(query, allowInterop((List tabs) {
    if (tabs.isNotEmpty) {
      completer.complete(tabs.first as Tab);
    } else {
      completer.complete(null);
    }
  }));
  return completer.future;
}

Future<bool> removeTab(int tabId) {
  final completer = Completer<bool>();
  chrome.tabs.remove(tabId, allowInterop(() {
    completer.complete(true);
  }));
  return completer.future;
}

Future<bool> injectScript(String scriptName, {required int tabId}) async {
  if (isMV3) {
    await promiseToFuture(_executeScriptMV3(
        _InjectDetails(
          target: Target(tabId: tabId),
          files: [scriptName],
        )));
    return true;
  } else {
    debugWarn('Script injection is only supported in Manifest V3.');
    return false;
  }
}

void onExtensionIconClicked(void Function(Tab) callback) {
  if (isMV3) {
    _onExtensionIconClickedMV3(callback);
  } else {
    _onExtensionIconClickedMV2(callback);
  }
}

void setExtensionIcon(String path) {
  final info = _IconInfo(path: path);
  if (isMV3) {
    _setExtensionIconMV3(info, /*callback*/ null);
  } else {
    _setExtensionIconMV2(info, /*callback*/ null);
  }
}

bool? _isDevMode;

bool get isDevMode {
  if (_isDevMode != null) {
    return _isDevMode!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  _isDevMode = extensionName.contains('DEV');
  return _isDevMode!;
}

bool? _isMV3;

bool get isMV3 {
  if (_isMV3 != null) {
    return _isMV3!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final manifestVersion =
      getProperty(extensionManifest, 'manifest_version') ?? 2;
  _isMV3 = manifestVersion == 3;
  return _isMV3!;
}

String addQueryParameters(
  String uri, {
  required Map<String, String> queryParameters,
}) {
  final originalUri = Uri.parse(uri);
  final newUri = originalUri.replace(queryParameters: {
    ...originalUri.queryParameters,
    ...queryParameters,
  });
  return newUri.toString();
}

@JS('chrome.scripting.executeScript')
external Object _executeScriptMV3(
  _InjectDetails details
);

@JS()
@anonymous
class _InjectDetails {
  external Target get target;
  external List<String>? get files;
  external factory _InjectDetails({
    Target target,
    List<String>? files,
  });
}

@JS('chrome.browserAction.onClicked.addListener')
external void _onExtensionIconClickedMV2(void Function(Tab tab) callback);

@JS('chrome.action.onClicked.addListener')
external void _onExtensionIconClickedMV3(void Function(Tab tab) callback);

@JS('chrome.browserAction.setIcon')
external void _setExtensionIconMV2(_IconInfo iconInfo, Function? callback);

@JS('chrome.action.setIcon')
external void _setExtensionIconMV3(_IconInfo iconInfo, Function? callback);

@JS()
@anonymous
class _IconInfo {
  external String get path;
  external factory _IconInfo({required String path});
}
