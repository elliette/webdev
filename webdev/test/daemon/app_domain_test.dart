// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../test_utils.dart';
import 'utils.dart';

void main() {
  late String exampleDirectory;

  final testRunner = TestRunner();
  setUpAll(() async {
    await testRunner.setUpAll();
    exampleDirectory = await testRunner.prepareWorkspace();
  });

  tearDownAll(testRunner.tearDownAll);

  group('AppDomain', () {
    group('Events', () {
      test('.start', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.start"')));
        await exitWebdev(webdev);
      });

      test('.started', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.started"')));
        await exitWebdev(webdev);
      });

      test('.debugPort', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(webdev.stdout,
            emitsThrough(startsWith('[{"event":"app.debugPort"')));
        await exitWebdev(webdev);
      });

      test('.log', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        final appId = await waitForAppId(webdev);
        // The example app does an initial print.
        await expectLater(
            webdev.stdout,
            emitsThrough(
                startsWith('[{"event":"app.log","params":{"appId":"$appId",'
                    '"log":"Initial Print\\n"}}')));
        await exitWebdev(webdev);
      });
    });

    group('Methods', () {
      test(
        '.callServiceExtension',
        () async {
          final webdev = await testRunner
              .runWebDev(['daemon'], workingDirectory: exampleDirectory);
          final appId = await waitForAppId(webdev);
          if (Platform.isWindows) {
            // Windows takes a bit longer to run the application and register
            // the service extension.
            await Future.delayed(const Duration(seconds: 5));
          }
          final extensionCall = '[{"method":"app.callServiceExtension","id":0,'
              '"params" : { "appId" : "$appId", "methodName" : "ext.print"}}]';
          webdev.stdin.add(utf8.encode('$extensionCall\n'));
          // The example app sets up a service extension for printing.
          await expectLater(
              webdev.stdout,
              emitsThrough(
                  startsWith('[{"event":"app.log","params":{"appId":"$appId",'
                      '"log":"Hello World\\n"}}')));
          await exitWebdev(webdev);
        },
        timeout: const Timeout(
          Duration(minutes: 2),
        ),
      );

      test(
        '.reload',
        () async {
          final webdev = await testRunner
              .runWebDev(['daemon'], workingDirectory: exampleDirectory);
          final appId = await waitForAppId(webdev);
          final extensionCall = '[{"method":"app.restart","id":0,'
              '"params" : { "appId" : "$appId", "fullRestart" : false}}]';
          webdev.stdin.add(utf8.encode('$extensionCall\n'));
          await expectLater(
            webdev.stdout,
            emitsThrough(startsWith(
              '[{"id":0,"result":{"code":1,"message":"hot reload not yet supported',
            )),
          );
          await exitWebdev(webdev);
        },
        timeout: const Timeout(
          Duration(minutes: 2),
        ),
      );

      test(
        '.restart',
        () async {
          final webdev = await testRunner
              .runWebDev(['daemon'], workingDirectory: exampleDirectory);
          final appId = await waitForAppId(webdev);
          final extensionCall = '[{"method":"app.restart","id":0,'
              '"params" : { "appId" : "$appId", "fullRestart" : true}}]';
          webdev.stdin.add(utf8.encode('$extensionCall\n'));
          await expectLater(
              webdev.stdout,
              emitsThrough(startsWith(
                  '[{"event":"app.progress","params":{"appId":"$appId","id":"1",'
                  '"message":"Performing hot restart..."')));
          await expectLater(
              webdev.stdout,
              emitsThrough(startsWith(
                  '[{"event":"app.progress","params":{"appId":"$appId","id":"1",'
                  '"finished":true')));
          await exitWebdev(webdev);
        },
        timeout: const Timeout(
          Duration(minutes: 2),
        ),
      );

      test(
        '.stop',
        () async {
          final webdev = await testRunner
              .runWebDev(['daemon'], workingDirectory: exampleDirectory);
          final appId = await waitForAppId(webdev);
          final stopCall = '[{"method":"app.stop","id":0,'
              '"params" : { "appId" : "$appId"}}]';
          webdev.stdin.add(utf8.encode('$stopCall\n'));
          await expectLater(
              webdev.stdout,
              emitsThrough(startsWith(
                  '[{"event":"app.stop","params":{"appId":"$appId"}}')));
          // This should cause webdev to exit.
          expect(await webdev.exitCode, equals(0));
        },
        timeout: const Timeout(
          Duration(minutes: 2),
        ),
      );
    });
  });
}
