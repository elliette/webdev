// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdev/src/util.dart';

import '../test_utils.dart';

const isRPCError = TypeMatcher<RPCError>();

final Matcher throwsRPCError = throwsA(isRPCError);

Future<void> exitWebdev(TestProcess webdev) async {
  webdev.stdin.add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
  await webdev.exitCode;
}

Future<String> waitForAppId(TestProcess webdev) async {
  var appId = '';
  while (await webdev.stdout.hasNext) {
    var line = await webdev.stdout.next;
    if (line.startsWith('[{"event":"app.started"')) {
      line = line.substring(1, line.length - 1);
      var message = json.decode(line) as Map<String, dynamic>;
      appId = message['params']['appId'] as String;
      break;
    }
  }
  assert(appId.isNotEmpty);
  return appId;
}

Future<String> prepareWorkspace() async {
  var relativeDirPath =
      p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSmoke'));
  var absoluteDirPath = absolutePath(pathFromFixtures: '_webdevSmoke');
  final dirPath = relativeDirPath;
  final notDirPath = absoluteDirPath;
  print('========= RUNNING dart pub upgrade IN $dirPath');
  print('========= (not running it in $notDirPath');

  var process = await TestProcess.start(dartPath, ['pub', 'upgrade'],
      workingDirectory: dirPath, environment: getPubEnvironment());

  await process.shouldExit(0);

  final generatedWebPath = p.join(
      dirPath, '.dart_tool', 'build', 'generated', '_webdev_smoke', 'web');
  final generatedWebDir = Directory(generatedWebPath);
  if (generatedWebDir.existsSync()) {
    final files = await generatedWebDir.list().toList();
    for (final file in files) {
      if (file.path.contains('main.unsound.ddc.js')) {
        print('-- ${file.path}');
        if (file.path.contains('errors')) {
          final errorFile = File(file.path);
          final lines = errorFile.readAsLinesSync();
          for (final line in lines) {
            print(line);
          }
        }
      }
    }
  } else {
    print('$generatedWebPath does not exist.');
  }

  return dirPath;
}

String? getDebugServiceUri(String line) {
  var regex = RegExp(r'Debug service listening on (?<wsUri>[^\s^\\]*)');
  var match = regex.firstMatch(line);
  if (match != null) {
    var wsUri = match.namedGroup('wsUri');
    return wsUri;
  }
  return null;
}

Future<int> findBreakpointLine(VmService vmService, String breakpointId,
    String isolateId, ScriptRef scriptRef) async {
  var script = await vmService.getObject(isolateId, scriptRef.id!) as Script;
  var lines = LineSplitter.split(script.source!).toList();
  var lineNumber =
      lines.indexWhere((l) => l.endsWith('// Breakpoint: $breakpointId'));
  if (lineNumber == -1) {
    throw StateError('Unable to find breakpoint in ${scriptRef.uri} with id '
        '$breakpointId');
  }
  return lineNumber + 1;
}
