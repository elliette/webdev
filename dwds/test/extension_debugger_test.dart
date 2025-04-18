// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:test/test.dart';

import 'fixtures/debugger_data.dart';
import 'fixtures/fakes.dart';

late FakeSseConnection connection;
late ExtensionDebugger extensionDebugger;

void main() async {
  setUp(() async {
    connection = FakeSseConnection();
    extensionDebugger = ExtensionDebugger(connection);
  });

  tearDown(() {
    connection.controllerIncoming.close();
    connection.controllerOutgoing.close();
  });

  group('can receive', () {
    test('an ExtensionResponse', () async {
      final extensionResponse = ExtensionResponse(
        (b) =>
            b
              ..result = jsonEncode({
                'result': {'value': 3.14},
              })
              ..id = 0
              ..success = true,
      );
      final resultCompleter = Completer();
      unawaited(
        extensionDebugger
            .sendCommand('Runtime.evaluate', params: {'expression': '\$pi'})
            .then(resultCompleter.complete),
      );
      connection.controllerIncoming.sink.add(
        jsonEncode(serializers.serialize(extensionResponse)),
      );
      final response = await resultCompleter.future;
      expect(response.result['result']['value'], 3.14);
    });

    test('an ExtensionEvent', () async {
      final extensionEvent = ExtensionEvent(
        (b) =>
            b
              ..method = jsonEncode('Debugger.paused')
              ..params = jsonEncode(frames1Json[0]),
      );
      connection.controllerIncoming.sink.add(
        jsonEncode(serializers.serialize(extensionEvent)),
      );
      final wipEvent = await extensionDebugger.onNotification.first;
      expect(wipEvent.method, 'Debugger.paused');
      expect(wipEvent.params, frames1Json[0]);
    });

    test('a BatchedEvents', () async {
      final event1 = ExtensionEvent(
        (b) =>
            b
              ..method = jsonEncode('Debugger.scriptParsed')
              ..params = jsonEncode(scriptParsedParams),
      );
      final event2 = ExtensionEvent(
        (b) =>
            b
              ..method = jsonEncode('Debugger.scriptParsed')
              ..params = jsonEncode(scriptParsedParams),
      );
      final batch = BatchedEvents(
        (b) => b.events = ListBuilder([event1, event2]),
      );
      connection.controllerIncoming.sink.add(
        jsonEncode(serializers.serialize(batch)),
      );
      final wipEvent = await extensionDebugger.onNotification.first;
      expect(wipEvent.method, 'Debugger.scriptParsed');
      expect(wipEvent.params, scriptParsedParams);
    });

    test('a DevToolsRequest', () async {
      final devToolsRequest = DevToolsRequest(
        (b) =>
            b
              ..tabUrl = 'pi/calculus'
              ..appId = '3.14'
              ..instanceId = '6.28',
      );
      connection.controllerIncoming.sink.add(
        jsonEncode(serializers.serialize(devToolsRequest)),
      );
      final request = await extensionDebugger.devToolsRequestStream.first;
      expect(request.tabUrl, 'pi/calculus');
      expect(request.appId, '3.14');
      expect(request.instanceId, '6.28');
    });
  });

  group('can send', () {
    test('a request with empty params', () async {
      final extensionRequest = ExtensionRequest(
        (b) =>
            b
              ..id = 0
              ..command = 'Debugger.pause'
              ..commandParams = jsonEncode({}),
      );
      unawaited(extensionDebugger.pause());
      final request = serializers.deserialize(
        jsonDecode(await connection.controllerOutgoing.stream.first),
      );
      expect(request, extensionRequest);
    });

    test('a request with some params', () async {
      final params = {
        'location': {'scriptId': '555', 'lineNumber': 28},
      };
      final extensionRequest = ExtensionRequest(
        (b) =>
            b
              ..id = 0
              ..command = 'Debugger.setBreakpoint'
              ..commandParams = jsonEncode(params),
      );
      unawaited(
        extensionDebugger.sendCommand('Debugger.setBreakpoint', params: params),
      );
      final request = serializers.deserialize(
        jsonDecode(await connection.controllerOutgoing.stream.first),
      );
      expect(request, extensionRequest);
    });
  });
  group('when closed', () {
    test('DebugExtension.detached event closes the connection', () async {
      final extensionEvent = ExtensionEvent(
        (b) =>
            b
              ..method = jsonEncode('DebugExtension.detached')
              ..params = jsonEncode({}),
      );

      connection.controllerIncoming.sink.add(
        jsonEncode(serializers.serialize(extensionEvent)),
      );
      // Expect the connection to receive a close event:
      expect(await extensionDebugger.onClose.first, isNotNull);
    });

    test(
      'gracefully handles trying to send events after the connection is closed',
      () async {
        // Close the connection:
        final extensionEvent = ExtensionEvent(
          (b) =>
              b
                ..method = jsonEncode('DebugExtension.detached')
                ..params = jsonEncode({}),
        );
        connection.controllerIncoming.sink.add(
          jsonEncode(serializers.serialize(extensionEvent)),
        );
        // Wait for it to be closed:
        await extensionDebugger.onClose.first;
        // Try to send an event:
        Future<void> callToSendCommand() => extensionDebugger.sendCommand(
          'Debugger.setBreakpoint',
          params: {
            'location': {'scriptId': '555', 'lineNumber': 28},
          },
        );
        // Should not throw any errors:
        expect(callToSendCommand, returnsNormally);
      },
    );
  });
}
