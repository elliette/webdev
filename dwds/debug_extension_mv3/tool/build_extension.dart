// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// INSTRUCTIONS:

// Builds the unminifed dart2js extension (see DDC issue:
// see DDC issue: https://github.com/dart-lang/sdk/issues/49869).

// Run from the extension root directory:
//    - For dev: dart run tool/build_extension.dart
//    - For prod: dart run tool/build_extension.dart prod

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const prodFlag = 'prod';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(prodFlag, negatable: true, defaultsTo: false);
  final argResults = parser.parse(arguments);

  exitCode = await run(isProd: argResults[prodFlag] as bool);
  if (exitCode != 0) {
    logWarning('Run terminated unexpectedly with exit code: $exitCode');
  }
}

Future<int> run({required bool isProd}) async {
  logStep('Building extension for ${isProd ? 'prod' : 'dev'}');
  logStep('Compiling extension with dart2js to /compiled directory');
  final compileStep = await Process.start(
    'dart',
    ['run', 'build_runner', 'build', 'web', '--output', 'build', '--release'],
  );
  final compileExitCode = await _handleProcess(compileStep);
  // Terminate early if compilation failed:
  if (compileExitCode != 0) {
    return compileExitCode;
  }
  logStep('Updating manifest.json in /compiled directory.');
  final updateStep = await Process.start(
    'dart',
    [p.join('tool', 'update_dev_files.dart')],
  );
  final updateExitCode = await _handleProcess(updateStep);
  // Terminate early if updating dev files failed:
  if (updateExitCode != 0) {
    return updateExitCode;
  }
  // Return 0 to indicate success:
  return 0;
}

Future<int> _handleProcess(Process process) async {
  _handleOutput(process.stdout);
  _handleOutput(process.stderr);
  return process.exitCode;
}

void _handleOutput(Stream<List<int>> output) {
  output
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(_handleOutputLine);
}

void _handleOutputLine(String line, {bool isStdout = true}) {
  final outputName = isStdout ? 'stdout' : 'stderr';
  if (line.toUpperCase().contains('SEVERE') ||
      line.toUpperCase().contains('ERROR')) {
    final error = 'Unexpected error in $outputName: $line';
    logWarning(error);
    throw Exception(error);
  }
  if (line.isNotEmpty) {
    print('$outputName: $line');
  }
}

void logStep(String message) {
  print('[BUILD STEP] $message');
}

void logWarning(String message) {
  print('[WARNING] $message');
}

void logOutput(dynamic output) {
  final outputList = output is List ? output : [output ?? ''];
  print(outputList.map((output) => '$output').join('\n'));
}
