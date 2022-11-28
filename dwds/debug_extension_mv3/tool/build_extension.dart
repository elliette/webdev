// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

const prodFlagName = 'prod';

// This script must be executed from the root of debug_extension_mv3.
//   - build dev extension: dart tool/build_extension.dart
//   - build prod extension: dart tool/build_extension.dart --prod

void main(List<String> arguments) async {
  exitCode = 0; // presume success

  // Parse command-line arguments:
  final parser = ArgParser()
    ..addFlag(
      prodFlagName,
      negatable: true,
      defaultsTo: false,
      abbr: 'p',
    );
  final argResults = parser.parse(arguments);
  final isProd = argResults[prodFlagName] as bool;
  print('Building ${isProd ? 'prod' : 'dev'} extension to /compiled directory');
  // Build the Dart Debug Extension:
  final result = Process.runSync(
    'dart',
    [
      'run',
      'build_runner',
      'build',
      'web',
      '--output',
      'build',
      '--release',
      _defineArg(isProd),
    ],
    workingDirectory: Directory.current.path,
  );
  print(result.stdout);
  print('err:');
  print(result.stderr);

  if (!isProd) {
    print('Updating dev files');
    await _updateManifestJson();
  }
}

/// Adds the Googler extension key.
Future<void> _updateManifestJson() async {
  final manifestJson = File('compiled/manifest.json');
  final extensionKeyTxt = File('extension_key.txt');
  final extensionKey = await extensionKeyTxt.exists()
      ? await extensionKeyTxt.readAsString()
      : null;
  return _transformDevFile(manifestJson, (line) {
    if (_matchesKey(line: line, key: 'name')) {
      return [
        line,
        if (extensionKey != null)
          _newKeyValue(
            oldLine: line,
            newKey: 'key',
            newValue: extensionKey,
          ),
      ];
    } else {
      return [line];
    }
  });
}

Future<void> _transformDevFile(
    File devFile, List<String> Function(String) transformLine) async {
  final lines = devFile.readAsLinesSync();
  final newLines = <String>[];
  for (final line in lines) {
    newLines.addAll(transformLine(line));
  }
  final content = newLines.joinWithNewLine();
  return devFile.writeAsStringSync(content);
}

bool _matchesKey({required String line, required String key}) {
  return line.trimLeft().startsWith('"$key":');
}

String _newKeyValue({
  required String oldLine,
  String? newKey,
  String? newValue,
}) {
  final lineStart = oldLine.leftPadding();
  final key = newKey != null ? '"$newKey": ' : '';
  final value = newValue != null ? '"$newValue"' : '';
  final lineEnd = oldLine.trim().endsWith(',') ? ',' : '';
  return '$lineStart$key$value$lineEnd';
}

extension LeftPaddingExtension on String {
  String leftPadding() {
    String padding = '';
    int idx = 0;
    while (idx < length && this[idx] == ' ') {
      padding += ' ';
      idx++;
    }
    return padding;
  }
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}

String _defineArg(bool isProd) {
  final envName = isProd ? 'prod' : 'dev';
  final jsonArgs = '["-Denv=$envName", "--csp"]';
  return "--define='build_web_compilers|entrypoint=dart2js_args=$jsonArgs'";
}
