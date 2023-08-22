// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

abstract class LoadStrategy {
  final AssetReader _assetReader;
  final _providers = <String, MetadataProvider>{};
  String? _packageConfigPath;

  LoadStrategy(this._assetReader);

  /// The ID for this strategy.
  ///
  /// This ID is passed to the injected client so that it can react accordingly.
  String get id;

  /// Module format for JS generated by the compiler.
  ///
  /// Module format is passed to the expression compilation worker during
  /// expression evaluation.
  String get moduleFormat;

  /// Module containing code for loading libraries.
  ///
  /// Used for preventing stepping into the library loading code.
  String get loadLibrariesModule;

  /// Returns a snippet of JS code that can be used to load a JS module.
  ///
  /// The snippet should be a reference to a function that takes a single
  /// argument which is the module name to load.
  String get loadModuleSnippet;

  /// The reload configuration for this strategy, e.g. liveReload.
  ReloadConfiguration get reloadConfiguration;

  /// The URI for the app's entrypoint file, which is usually `main.dart`. It
  /// should be a package URI, e.g. `package:myapp/main.dart`.
  Uri? get appEntrypoint;

  /// Returns the bootstrap required for this [LoadStrategy].
  ///
  /// The bootstrap is appended to the end of the entry point module.
  Future<String> bootstrapFor(String entrypoint);

  /// A handler for strategy specific requests.
  ///
  /// Used as a part of the injected_handler middleware.
  Handler get handler;

  /// JS code snippet for loading the injected client script.
  String loadClientSnippet(String clientScript);

  /// Returns the module for the corresponding server path.
  ///
  /// For example:
  ///
  /// /packages/path/path.ddc.js -> packages/path/path
  ///
  Future<String?> moduleForServerPath(String entrypoint, String serverPath);

  /// Returns the server path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js
  ///
  Future<String?> serverPathForModule(String entrypoint, String module);

  /// Returns the source map path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js.map
  ///
  Future<String?> sourceMapPathForModule(String entrypoint, String module);

  /// Returns a map from module id to module info for the provided entrypoint.
  ///
  /// For example:
  ///
  ///   web/main -> {main.ddc.full.dill, main.ddc.dill}
  ///
  Future<Map<String, ModuleInfo>> moduleInfoForEntrypoint(String entrypoint);

  /// Returns the server path for the app uri.
  ///
  /// For example:
  ///
  ///   org-dartlang-app://web/main.dart -> main.dart
  ///
  /// Will return `null` if the provided uri is not
  /// an app URI.
  String? serverPathForAppUri(String appUri);

  /// Returns the absolute path to the app's package config, determined by the
  /// app's [entrypoint] path.
  ///
  /// Example:
  ///
  ///  main_module.bootstrap.js
  ///   -> /Users/john_doe/my_dart_app/.dart_tool/package_config.json
  ///
  String? packageConfigLocator(String entrypoint);

  /// Returns the relative path in google3, determined by the [absolutePath].
  ///
  /// Returns `null` if not a google3 app.
  String? g3RelativePath(String absolutePath);

  /// The absolute path to the app's package config, or null if not provided by
  /// [packageConfigLocator].
  String get packageConfigPath {
    return _packageConfigPath ?? _defaultPackageConfigPath;
  }

  /// The default package config path, if none is provided by the load strategy.
  String get _defaultPackageConfigPath => p.join(
        DartUri.currentDirectory,
        '.dart_tool',
        'package_config.json',
      );

  /// Returns the [MetadataProvider] for the application located at the provided
  /// [entrypoint].
  MetadataProvider metadataProviderFor(String entrypoint) {
    if (_providers.containsKey(entrypoint)) {
      return _providers[entrypoint]!;
    } else {
      throw StateError('No metadata provider for $entrypoint');
    }
  }

  /// Initializes a [MetadataProvider] for the application located at the
  /// provided [entrypoint].
  void trackEntrypoint(String entrypoint) {
    final metadataProvider = MetadataProvider(entrypoint, _assetReader);
    _packageConfigPath = packageConfigLocator(entrypoint);
    _providers[metadataProvider.entrypoint] = metadataProvider;
  }
}

enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }
