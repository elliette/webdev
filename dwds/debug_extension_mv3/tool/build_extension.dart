// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// INSTRUCTIONS:

// Builds the unminifed dart2js extension (see DDC issue:
// see DDC issue: https://github.com/dart-lang/sdk/issues/49869).

// Run from the extension root directory:
//    - For default (dev-mode, MV2): dart run tool/build_extension.dart
//    - For prod: dart run tool/build_extension.dart --prod
//    - For MV3: dart run tool/build_extension.dart --mv3

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const prodFlag = 'prod';
const mv3Flag = 'mv3';

void main(List<String> arguments) {
  exitCode = 0; // presume success
  final parser = ArgParser()
    ..addFlag(prodFlag, negatable: true, defaultsTo: false)
    ..addFlag(mv3Flag, negatable: true, defaultsTo: false);
  final argResults = parser.parse(arguments);

  run(
    isProd: argResults[prodFlag] as bool,
    isMV3: argResults[mv3Flag] as bool,
  );
}

Future<void> run({required bool isProd, required bool isMV3}) async {
  logInfo(
      'Building Manifest ${isMV3 ? 'V3' : 'V2'} extension for ${isProd ? 'prod' : 'dev'}');
  logInfo('Compiling extension with dart2js to /compiled directory');
  logOutput(
    await Process.run(
      'dart',
      ['run', 'build_runner', 'build', 'web', '--output', 'build', '--release'],
    ),
  );
  final manifestFileName = isMV3 ? 'manifest_mv3' : 'manifest_mv2';
  logInfo('Copying manifest.json to /compiled directory');
  logOutput(
    await Process.run(
      'cp',
      [
        p.join('web', '$manifestFileName.json'),
        p.join('compiled', 'manifest.json'),
      ],
    ),
  );
  logInfo('Updating manifest.json in /compiled directory.');
  logOutput(
    await Process.run(
      'dart',
      [p.join('tool', 'update_dev_files.dart')],
    ),
  );
}

void logInfo(String message) {
  print('[BUILD STEP] $message');
}

void logOutput(ProcessResult result) {
  final output = result.stdout;
  final outputList = output is List ? output : [output ?? ''];
  print(outputList.map((output) => '$output').join('\n'));
}
