// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:async/async.dart';
import 'package:dwds/src/debugging/metadata/module_metadata.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// A provider of metadata in which data is collected through DDC outputs.
class MetadataProvider {
  final AssetReader _assetReader;
  final _logger = Logger('MetadataProvider');
  final String entrypoint;
  final List<String> _libraries = [];
  final Map<String, String> _scriptToModule = {};
  final Map<String, String> _moduleToSourceMap = {};
  final Map<String, String> _modulePathToModule = {};
  final Map<String, String> _moduleToModulePath = {};
  final Map<String, List<String>> _scripts = {};
  final _metadataMemoizer = AsyncMemoizer();
  // Whether to use the `name` provided in the module metadata.
  final bool _useModuleName;

  /// Implicitly imported libraries in any DDC component.
  ///
  /// Currently dart_sdk module does not come with the metadata.
  /// To allow evaluation of expressions that use libraries and
  /// types from the SDK (such as a dart Type object), add the
  /// metadata for dart_sdk manually.
  ///
  /// TODO: Generate sdk module metadata to be consumed by debugger.
  /// Issue: https://github.com/dart-lang/sdk/issues/45477
  List<String> get sdkLibraries => const [
    'dart:_runtime',
    'dart:_debugger',
    'dart:_foreign_helper',
    'dart:_interceptors',
    'dart:_internal',
    'dart:_isolate_helper',
    'dart:_js_helper',
    'dart:_js_primitives',
    'dart:_metadata',
    'dart:_native_typed_data',
    'dart:_rti',
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:developer',
    'dart:io',
    'dart:isolate',
    'dart:js',
    'dart:js_util',
    'dart:math',
    'dart:typed_data',
    'dart:indexed_db',
    'dart:html',
    'dart:html_common',
    'dart:svg',
    'dart:web_audio',
    'dart:web_gl',
    'dart:ui',
  ];

  MetadataProvider(
    this.entrypoint,
    this._assetReader, {
    required bool useModuleName,
  }) : _useModuleName = useModuleName;

  /// A sound null safety mode for the whole app.
  ///
  /// All libraries have to agree on null safety mode.
  @Deprecated('Only sound null safety is supported as of Dart 3.0')
  Future<bool> get soundNullSafety async {
    await _initialize();
    return true;
  }

  /// A list of all libraries in the Dart application.
  ///
  /// Example:
  ///
  ///  [
  ///     dart:web_gl,
  ///     dart:math,
  ///     org-dartlang-app:///web/main.dart
  ///  ]
  ///
  Future<List<String>> get libraries async {
    await _initialize();
    return _libraries;
  }

  /// A map of library uri to dart scripts.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   { web/main.dart  }
  /// }
  ///
  Future<Map<String, List<String>>> get scripts async {
    await _initialize();
    return _scripts;
  }

  /// A map of script to containing module.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main
  /// }
  ///
  /// If [_useModuleName] is false, the values will be the module paths instead
  /// of the name except for 'dart_sdk'.
  Future<Map<String, String>> get scriptToModule async {
    await _initialize();
    return _scriptToModule;
  }

  /// A map of module name to source map path.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main.ddc.js.map
  /// }
  ///
  /// If [_useModuleName] is false, the keys will be the module paths instead of
  /// the name.
  Future<Map<String, String>> get moduleToSourceMap async {
    await _initialize();
    return _moduleToSourceMap;
  }

  /// A map of module path to module name.
  ///
  /// Example:
  ///
  /// {
  ///   web/main.ddc.js :
  ///   web/main
  /// }
  ///
  /// If [_useModuleName] is false, the values will be the module paths instead
  /// of the name, making this an identity map.
  Future<Map<String, String>> get modulePathToModule async {
    await _initialize();
    return _modulePathToModule;
  }

  /// A map of module to module path.
  ///
  /// Example:
  ///
  /// {
  ///   web/main
  ///   web/main.ddc.js :
  /// }
  ///
  /// If [_useModuleName] is false, the keys will be the module paths instead of
  /// the name, making this an identity map.
  Future<Map<String, String>> get moduleToModulePath async {
    await _initialize();
    return _moduleToModulePath;
  }

  /// A list of module ids.
  ///
  /// Example:
  ///
  /// [
  ///   web/main,
  ///   web/foo/bar
  /// ]
  ///
  /// If [_useModuleName] is false, this will be the set of module paths
  /// instead.
  Future<List<String>> get modules async {
    await _initialize();
    return _moduleToModulePath.keys.toList();
  }

  Future<void> _initialize() async {
    await _metadataMemoizer.runOnce(() async {
      // The merged metadata resides next to the entrypoint.
      // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
      if (entrypoint.endsWith('.bootstrap.js')) {
        _logger.info('Loading debug metadata...');
        final serverPath = entrypoint.replaceAll(
          '.bootstrap.js',
          '.ddc_merged_metadata',
        );
        final merged = await _assetReader.metadataContents(serverPath);
        if (merged != null) {
          _addSdkMetadata();
          for (final contents in merged.split('\n')) {
            try {
              if (contents.isEmpty ||
                  contents.startsWith('// intentionally empty:')) {
                continue;
              }
              final moduleJson = json.decode(contents);
              final metadata = ModuleMetadata.fromJson(
                moduleJson as Map<String, dynamic>,
              );
              _addMetadata(metadata);
              final moduleName =
                  _useModuleName ? metadata.name : metadata.moduleUri;
              _logger.fine('Loaded debug metadata for module: $moduleName');
            } catch (e) {
              _logger.warning('Failed to read metadata: $e');
              rethrow;
            }
          }
        }
      }
    });
  }

  void _addMetadata(ModuleMetadata metadata) {
    final modulePath = stripLeadingSlashes(metadata.moduleUri);
    final sourceMapPath = stripLeadingSlashes(metadata.sourceMapUri);
    // DDC library bundle module format does not provide names for library
    // bundles, and therefore we use the URI instead to represent a library
    // bundle.
    final moduleName = _useModuleName ? metadata.name : modulePath;

    _moduleToSourceMap[moduleName] = sourceMapPath;
    _modulePathToModule[modulePath] = moduleName;
    _moduleToModulePath[moduleName] = modulePath;

    for (final library in metadata.libraries.values) {
      if (library.importUri.startsWith('file:/')) {
        throw AbsoluteImportUriException(library.importUri);
      }
      _libraries.add(library.importUri);
      _scripts[library.importUri] = [];

      _scriptToModule[library.importUri] = moduleName;
      for (final path in library.partUris) {
        // Parts in metadata are relative to the library Uri directory.
        final partPath = p.url.join(p.dirname(library.importUri), path);
        _scripts[library.importUri]!.add(partPath);
        _scriptToModule[partPath] = moduleName;
      }
    }
  }

  void _addSdkMetadata() {
    final moduleName = 'dart_sdk';

    for (final lib in sdkLibraries) {
      _libraries.add(lib);
      _scripts[lib] = [];
      // TODO(srujzs): It feels weird that we add this mapping to only this map
      // and not any of the other module maps. We should maybe handle this
      // differently.
      _scriptToModule[lib] = moduleName;
    }
  }
}

class AbsoluteImportUriException implements Exception {
  final String importUri;
  AbsoluteImportUriException(this.importUri);

  @override
  String toString() => "AbsoluteImportUriError: '$importUri'";
}
