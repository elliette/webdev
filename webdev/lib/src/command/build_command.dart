// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show Directory;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:logging/logging.dart' as logging;

import '../daemon_client.dart';
import '../logging.dart';
import '../pubspec.dart';
import 'configuration.dart';
import 'shared.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends Command<int> {
  @override
  final argParser = ArgParser(usageLineLength: lineLength);

  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  BuildCommand() {
    addSharedArgs(argParser, outputDefault: 'web:build');
  }

  @override
  Future<int> run() async {
    final extraArgs = argResults?.rest ?? [];
    final unsupported = extraArgs.where((arg) => !arg.startsWith('-')).toList();
    if (unsupported.isNotEmpty) {
      throw UsageException(
          'Arguments were provided that are not supported: '
          '"${unsupported.join(' ')}".',
          argParser.usage);
    }
    final validExtraArgs =
        extraArgs.where((arg) => arg.startsWith('-')).toList();

    final configuration = Configuration.fromArgs(argResults);
    configureLogWriter(configuration.verbose);

    List<String> arguments;
    try {
      await validatePubspecLock(configuration);
      arguments = buildRunnerArgs(configuration)..addAll(validExtraArgs);
    } on PackageException catch (e) {
      logWriter(logging.Level.SEVERE, 'Pubspec errors: ',
          error: '${e.details}');
      rethrow;
    }

    try {
      logWriter(logging.Level.INFO, 'Connecting to the build daemon...');
      final client = await connectClient(
        Directory.current.path,
        arguments,
        (serverLog) {
          logWriter(toLoggingLevel(serverLog.level), serverLog.message,
              error: serverLog.error,
              loggerName: serverLog.loggerName,
              stackTrace: serverLog.stackTrace);
        },
      );
      OutputLocation? outputLocation;
      final outputInput = configuration.outputInput;
      if (configuration.outputPath != null) {
        outputLocation = OutputLocation((b) => b
          ..output = configuration.outputPath
          ..useSymlinks = false
          ..hoist = outputInput != null && outputInput.isNotEmpty);
      }
      client.registerBuildTarget(DefaultBuildTarget((b) => b
        ..target = configuration.outputInput
        ..outputLocation = outputLocation?.toBuilder()));
      client.startBuild();
      var exitCode = 0;
      var gotBuildStart = false;
      await for (final result in client.buildResults) {
        final targetResult = result.results.firstWhereOrNull(
            (buildResult) => buildResult.target == configuration.outputInput);
        if (targetResult == null) continue;
        // We ignore any builds that happen before we get a `started` event,
        // because those could be stale (from some other client).
        gotBuildStart =
            gotBuildStart || targetResult.status == BuildStatus.started;
        if (!gotBuildStart) continue;

        // Shouldn't happen, but being a bit defensive here.
        if (targetResult.status == BuildStatus.started) continue;

        if (targetResult.status == BuildStatus.failed) {
          exitCode = 1;
        }

        final error = targetResult.error ?? '';
        if (error.isNotEmpty) {
          logWriter(logging.Level.SEVERE, error);
        }
        break;
      }
      await client.close();
      return exitCode;
    } on OptionsSkew catch (_) {
      logWriter(
          logging.Level.SEVERE,
          'Incompatible options with current running build daemon.\n\n'
          'Please stop other WebDev instances running in this directory '
          'before starting a new instance with these options.\n\n');
      return 1;
    }
  }
}
