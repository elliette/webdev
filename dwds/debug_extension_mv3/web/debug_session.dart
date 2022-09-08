// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_session;

import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/sockets.dart';
import 'package:dwds/src/utilities/batched_stream.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

class DebugSession {
  // The tab ID that contains the running Dart application.
  final int tabId;

  // Debug info for the running Dart application.
  final DebugInfo debugInfo;

  // Socket client for communication with dwds extension backend.
  SocketClient? _socketClient;

  // How often to send batched events.
  static const int _batchDelayMilliseconds = 1000;

  Debuggee get debuggee {
    return Debuggee(tabId: tabId);
  }

  void set socketClient(SocketClient client) {
    _socketClient = client;
    _sendBatchedEventsToServer();
  }

  // Collect events into batches to be send periodically to the server.
  final _batchController =
      BatchedStreamController<ExtensionEvent>(delay: _batchDelayMilliseconds);
  late final StreamSubscription<List<ExtensionEvent>> _batchSubscription;

  DebugSession(this.tabId, {required this.debugInfo});

  void sendEvent(ExtensionEvent event) {
    if (_socketClient != null) {
      _socketClient!.sink.add(jsonEncode(serializers.serialize(event)));
    }
  }

  void sendBatchedEvent(ExtensionEvent event) {
    _batchController.sink.add(event);
  }

  void close() {
    if (_socketClient != null) {
      _socketClient!.close();
    }
    _batchSubscription.cancel();
    _batchController.close();
  }

  void _sendBatchedEventsToServer() {
    // Collect extension events and send them periodically to the server.
    _batchSubscription = _batchController.stream.listen((events) {
      if (_socketClient != null) {
        _socketClient!.sink.add(jsonEncode(serializers.serialize(BatchedEvents(
            (b) => b.events = ListBuilder<ExtensionEvent>(events)))));
      }
    });
  }
}