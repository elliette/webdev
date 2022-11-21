// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';
import 'dart:html' show WorkerGlobalScope;
import 'dart:js_util' as js_util;
import 'package:shelf/shelf.dart';

@JS()
external Console get console;

@JS()
external WorkerGlobalScope get self;

extension E on WorkerGlobalScope {
  Future<FetchResponse> fetchResource<T>(String resourceUrl, FetchOptions options) async {
    final fetchFuture = js_util.promiseToFuture(js_util.callMethod(self, 'fetch', [
        resourceUrl,
        options,
      ]));
    final response = await fetchFuture;
    return response as FetchResponse;
  }
}

@JS()
@anonymous
class FetchOptions {
  external String get method; // e.g., 'GET', 'POST'
  external CredentialsOptions get credentialsOptions;
  external factory FetchOptions({
    String method,
    CredentialsOptions credentialsOptions,
  });
}

@JS()
@anonymous
class CredentialsOptions {
  external String get credentials; // e.g., 'omit', 'same-origin', 'include'
  external factory CredentialsOptions({String credentials});
}

@JS()
@anonymous
class Console {
  external void log(String header,
      [String style1, String style2, String style3]);

  external void warn(String header,
      [String style1, String style2, String style3]);
}

@JS()
// ignore: non_constant_identifier_names
external Json get JSON;

@JS()
@anonymous
class Json {
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify
  external String stringify(o);
}

@JS()
@anonymous
class FetchResponse {
  external bool ok;
  external int status;
}

