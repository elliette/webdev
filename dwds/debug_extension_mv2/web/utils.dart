// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library utils;

import 'dart:async';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';

bool? _isDevMode;

bool isDevMode() {
  if (_isDevMode != null) {
    return _isDevMode!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  return extensionName.contains('DEV');
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

Future<Tab> createTab(String url, {bool inNewWindow = false}) async {
  // TODO(elliette): Switch to MV3 implementation.
  return _createTabMV2(url, inNewWindow: inNewWindow);
}

Future<Tab?> getTab(int tabId) {
  // TODO(elliette): Switch to MV3 implementation.
  return _getTabMV2(tabId);
}

Future<Tab?> getActiveTab() async {
  // TODO(elliette): Switch to MV3 implementation.
  return _getActiveTabMV2();
}

void removeTab(int tabId) {
  // TODO(elliette): Switch to MV3 implementation.
  return _removeTabMV2(tabId);
}

void injectScript(String scriptName, {required int tabId}) {
  // TODO(elliette): Switch to MV3 implementation.
  _injectScriptMV2(scriptName, tabId: tabId);
}

void onExtensionIconClicked(void Function(Tab) callback) {
  // TODO(elliette): Switch to MV3 implementation.
  _onExtensionIconClickedMV2(callback);
}

void setExtensionIcon(IconInfo info) {
  // TODO(elliette): Switch to MV3 implementation.
  _setExtensionIconMV2(info);
}

Future<Tab> _createTabMV2(String url, {bool inNewWindow = false}) {
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

Future<Tab?> _getTabMV2(int tabId) {
  final completer = Completer<Tab?>();
  chrome.tabs.get(tabId, allowInterop((tab) {
    completer.complete(tab);
  }));
  return completer.future;
}

Future<Tab?> _getActiveTabMV2() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final completer = Completer<Tab?>();
  chrome.tabs.query(query, allowInterop((List tabs) {
    if (tabs.isNotEmpty) {
      completer.complete(tabs.first as Tab);
    } else {
      completer.complete(null);
    }
  }));
  return completer.future;
}

void _removeTabMV2(int tabId) {
  chrome.tabs.remove(tabId, /* callback= */ null);
}

void _injectScriptMV2(String scriptName, {required int tabId}) {
  chrome.tabs.executeScript(
    tabId,
    TabInjectDetails(
      file: 'lifeline_connection.dart.js',
    ),
    /*callback*/ null,
  );
}

void _onExtensionIconClickedMV2(void Function(Tab) callback) {
  chrome.browserAction.onClicked.addListener(callback);
}

void _setExtensionIconMV2(IconInfo info) {
  chrome.browserAction.setIcon(info, /*callback*/ null);
}

/*
Future<Tab> _createTabMV3(String url, {bool inNewWindow = false}) {
  if (inNewWindow) {
    final windowPromise = chrome.windows.create(
      WindowInfo(focused: true, url: url),
    );
    final windowObj = await promiseToFuture<WindowObj>(windowPromise);
    return windowObj.tabs.first;
  }
  final tabPromise = chrome.tabs.create(TabInfo(
    active: true,
    url: url,
  ));
  return promiseToFuture<Tab>(tabPromise);
}

Future<Tab?> _getTabMV3(int tabId) {
  return promiseToFuture<Tab?>(chrome.tabs.get(tabId));
}

Future<Tab?> _getActiveTabMV3() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
}

void _removeTabMV3(int tabId) async {
  chrome.tabs.remove(tabId);
}

void _injectScriptMV3(String scriptName, {required int tabId}) {
  chrome.scripting.executeScript(
    InjectDetails(
      target: Target(tabId: tabId),
      files: [scriptName],
    ),
    /*callback*/ null,
  );
}

void _onExtensionIconClickedMV3(void Function(Tab) callback) {
  chrome.action.onClicked.addListener(callback);
}

void _setExtensionIconMV#(IconInfo info) {
  chrome.action.setIcon(info, /*callback*/ null);
}
*/
