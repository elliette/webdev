// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'devtools_request.g.dart';

/// A request to open DevTools.
abstract class DevToolsRequest
    implements Built<DevToolsRequest, DevToolsRequestBuilder> {
  static Serializer<DevToolsRequest> get serializer =>
      _$devToolsRequestSerializer;

  factory DevToolsRequest([Function(DevToolsRequestBuilder) updates]) =
      _$DevToolsRequest;

  DevToolsRequest._();

  /// Identifies a given application, across tabs/windows.
  String get appId;

  /// Identifies a given instance of an application, unique per tab/window.
  String get instanceId;

  /// Identifies the context in which evaluations should occur.
  ///
  /// Defines execution context for the debug service that connects
  /// to chrome via the extension debugger.
  /// Can be `null` for local debug service, which gets the execution
  /// context from the Chrome runtime.
  int? get contextId;

  /// Belongs to the tab that requests the DevTools.
  ///
  /// Defines the tab being debugged for the debug service that connects
  /// to chrome via the extension debugger.
  /// Can be `null` for local debug service, which finds the tab with the
  /// correct `dartAppInstanceId` automatically.
  String? get tabUrl;

  /// Designates this as a request to send back the DevTools URI instead of
  /// opening DevTools in a new tab or window.
  ///
  /// Only available on requests coming from the Dart Debug Extension. Is `null`
  /// for local debug service.
  bool? get uriOnly;

  /// Identifies the client that DWDS is attaching to.
  ///
  /// This could be Cider, DevTools (as a standalone app), or DevTools (embedded
  /// in Chrome DevTools).
  String? get client;
}

/// A response to a [DevToolsRequest].
abstract class DevToolsResponse
    implements Built<DevToolsResponse, DevToolsResponseBuilder> {
  static Serializer<DevToolsResponse> get serializer =>
      _$devToolsResponseSerializer;

  factory DevToolsResponse([Function(DevToolsResponseBuilder) updates]) =
      _$DevToolsResponse;

  DevToolsResponse._();

  bool get success;

  bool get promptExtension;

  String? get error;
}
