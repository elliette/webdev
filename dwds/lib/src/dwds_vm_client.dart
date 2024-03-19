// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:dwds/src/utilities/synchronized.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

final _logger = Logger('DwdsVmClient');

// A client of the vm service that registers some custom extensions like
// hotRestart.
class DwdsVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object?>> _responseController;

  static const int kFeatureDisabled = 100;
  static const String kFeatureDisabledMessage = 'Feature is disabled.';

  static const String _flutterListViewsMethod = '_flutter.listViews';

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  /// Synchronizes hot restarts to avoid races.
  final _hotRestartQueue = AtomicQueue();

  DwdsVmClient(this.client, this._requestController, this._responseController);

  Future<void> close() => _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<DwdsVmClient> create(
    DebugService debugService,
    DwdsStats dwdsStats,
    Uri? ddsUri,
  ) {
    final chromeProxyService =
        debugService.chromeProxyService as ChromeProxyService;
    final requestController = StreamController<Map<String, Object>>();
    final responseController = StreamController<Map<String, Object?>>();

    _setUpVmServerConnection(
      chromeProxyService: chromeProxyService,
      debugService: debugService,
      requestController: requestController,
      responseController: responseController,
    );

    if (ddsUri == null) {
      return _setUpVmClient(
        requestController: requestController,
        responseController: responseController,
        chromeProxyService: chromeProxyService,
        dwdsStats: dwdsStats,
      );
    }

    return _setUpDdsClient(
      ddsUri: ddsUri,
      requestController: requestController,
      responseController: responseController,
      chromeProxyService: chromeProxyService,
      dwdsStats: dwdsStats,
    );
  }

  /// Establishes a VM service client that is connected via DDS and registers
  /// the service extensions on that client.
  static Future<DwdsVmClient> _setUpDdsClient({
    required Uri ddsUri,
    required StreamController<Map<String, Object>> requestController,
    required StreamController<Map<String, Object?>> responseController,
    required ChromeProxyService chromeProxyService,
    required DwdsStats dwdsStats,
  }) async {
    final webSocketClient = WebSocketChannel.connect(ddsUri);
    final client = VmService(
      webSocketClient.stream,
      webSocketClient.sink.add,
    );

    final dwdsDdsClient =
        DwdsVmClient(client, requestController, responseController);

    await _registerServiceExtensions(
      client: client,
      chromeProxyService: chromeProxyService,
      dwdsDdsClient: dwdsDdsClient,
      dwdsStats: dwdsStats,
    );

    return dwdsDdsClient;
  }

  /// Establishes a VM service client that bypasses DDS and registers service
  /// extensions on that client.
  ///
  /// Note: This is only used in the rare cases where DDS is disabled.
  static Future<DwdsVmClient> _setUpVmClient({
    required StreamController<Map<String, Object>> requestController,
    required StreamController<Map<String, Object?>> responseController,
    required ChromeProxyService chromeProxyService,
    required DwdsStats dwdsStats,
  }) async {
    final client =
        VmService(responseController.stream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _logger.warning(
            'Attempted to send a request but the connection is closed:\n\n'
            '$request');
        return;
      }
      requestController.sink.add(Map<String, Object>.from(jsonDecode(request)));
    });

    final dwdsVmClient =
        DwdsVmClient(client, requestController, responseController);

    await _registerServiceExtensions(
      client: client,
      chromeProxyService: chromeProxyService,
      dwdsDdsClient: dwdsVmClient,
      dwdsStats: dwdsStats,
    );

    return dwdsVmClient;
  }

  /// Establishes a direct connection with the VM Server.
  ///
  /// This is currently only necessary to register the `_flutter.listViews`
  /// service extension. Because it is a namespaced service extension that is
  /// supposed to be registered by the engine, we need to register it on the VM
  /// server connection instead of via DDS.
  ///
  /// TODO(https://github.com/dart-lang/webdev/issues/1315): Ideally the engine
  /// should register all Flutter service extensions. However, to do so we will
  /// need to implement the missing isolate-related dart:developer APIs so that
  /// the engine has access to this information.
  static void _setUpVmServerConnection({
    required ChromeProxyService chromeProxyService,
    required DebugService debugService,
    required StreamController<Map<String, Object>> requestController,
    required StreamController<Map<String, Object?>> responseController,
  }) {
    responseController.stream.listen((request) async {
      final method = request['method'];
      if (method == _flutterListViewsMethod) {
        final response =
            await _flutterListViewsHandler(request, chromeProxyService);
        requestController.sink.add(response);
      }
    });

    final vmServerConnection = VmServerConnection(
      requestController.stream,
      responseController.sink,
      debugService.serviceExtensionRegistry,
      debugService.chromeProxyService,
    );

    debugService.serviceExtensionRegistry
        .registerExtension(_flutterListViewsMethod, vmServerConnection);
  }

  static Future<Map<String, Object>> _flutterListViewsHandler(
    Map<String, Object?> request,
    ChromeProxyService chromeProxyService,
  ) async {
    final requestId = request['id'] as String;
    final vm = await chromeProxyService.getVM();
    final isolates = vm.isolates;
    return <String, Object>{
      'result': <String, Object>{
        'views': <Object>[
          for (var isolate in isolates ?? [])
            <String, Object>{
              'id': isolate.id,
              'isolate': isolate.toJson(),
            },
        ],
      },
      'id': requestId,
      // This is necessary even though DWDS doesn't use package:json_rpc_2.
      // Without it, the response will be treated as invalid:
      // https://github.com/dart-lang/json_rpc_2/blob/639857be892050159f5164c749d7947694976a4a/lib/src/server.dart#L252
      'jsonrpc': '2.0',
    };
  }

  static Future<void> _registerServiceExtensions({
    required VmService client,
    required ChromeProxyService chromeProxyService,
    required DwdsVmClient dwdsDdsClient,
    required DwdsStats dwdsStats,
  }) async {
    client.registerServiceCallback(
      'hotRestart',
      (request) => captureElapsedTime(
        () => dwdsDdsClient.hotRestart(chromeProxyService, client),
        (_) => DwdsEvent.hotRestart(),
      ),
    );
    await client.registerService('hotRestart', 'DWDS');

    client.registerServiceCallback(
      'fullReload',
      (request) => captureElapsedTime(
        () => _fullReload(chromeProxyService),
        (_) => DwdsEvent.fullReload(),
      ),
    );
    await client.registerService('fullReload', 'DWDS');

    client.registerServiceCallback('ext.dwds.screenshot', (_) async {
      await chromeProxyService.remoteDebugger.enablePage();
      final response = await chromeProxyService.remoteDebugger
          .sendCommand('Page.captureScreenshot');
      return {'result': response.result};
    });
    await client.registerService('ext.dwds.screenshot', 'DWDS');

    client.registerServiceCallback('ext.dwds.sendEvent', (event) async {
      _processSendEvent(event, dwdsStats);
      return {'result': Success().toJson()};
    });
    await client.registerService('ext.dwds.sendEvent', 'DWDS');

    client.registerServiceCallback('ext.dwds.emitEvent', (event) async {
      emitEvent(
        DwdsEvent(
          event['type'] as String,
          event['payload'] as Map<String, dynamic>,
        ),
      );
      return {'result': Success().toJson()};
    });
    await client.registerService('ext.dwds.emitEvent', 'DWDS');
  }

  Future<Map<String, dynamic>> hotRestart(
    ChromeProxyService chromeProxyService,
    VmService client,
  ) {
    return _hotRestartQueue.run(() => _hotRestart(chromeProxyService, client));
  }
}

void _processSendEvent(
  Map<String, dynamic> event,
  DwdsStats dwdsStats,
) {
  final type = event['type'] as String?;
  final payload = event['payload'] as Map<String, dynamic>?;
  switch (type) {
    case 'DevtoolsEvent':
      {
        _logger.finest('Received DevTools event: $event');
        final action = payload?['action'] as String?;
        final screen = payload?['screen'] as String?;
        if (screen != null && action == 'pageReady') {
          _recordDwdsStats(dwdsStats, screen);
        } else {
          _logger.finest('Ignoring unknown event: $event');
        }
      }
  }
}

void _recordDwdsStats(DwdsStats dwdsStats, String screen) {
  if (dwdsStats.isFirstDebuggerReady) {
    final devToolsStart = dwdsStats.devToolsStart;
    final debuggerStart = dwdsStats.debuggerStart;
    if (devToolsStart != null) {
      final devToolLoadTime =
          DateTime.now().difference(devToolsStart).inMilliseconds;
      emitEvent(DwdsEvent.devToolsLoad(devToolLoadTime, screen));
      _logger.fine('DevTools load time: $devToolLoadTime ms');
    }
    if (debuggerStart != null) {
      final debuggerReadyTime =
          DateTime.now().difference(debuggerStart).inMilliseconds;
      emitEvent(DwdsEvent.debuggerReady(debuggerReadyTime, screen));
      _logger.fine('Debugger ready time: $debuggerReadyTime ms');
    }
  } else {
    _logger.finest('Debugger and DevTools stats are already recorded.');
  }
}

Future<int> tryGetContextId(
  ChromeProxyService chromeProxyService, {
  int retries = 3,
}) async {
  const waitInMs = 50;
  for (var retry = 0; retry < retries; retry++) {
    final tryId = await chromeProxyService.executionContext.id;
    if (tryId != null) return tryId;
    await Future.delayed(const Duration(milliseconds: waitInMs));
  }
  throw StateError('No context with the running Dart application.');
}

Future<Map<String, dynamic>> _hotRestart(
  ChromeProxyService chromeProxyService,
  VmService client,
) async {
  _logger.info('Attempting a hot restart');

  chromeProxyService.terminatingIsolates = true;
  await _disableBreakpointsAndResume(client, chromeProxyService);
  try {
    _logger.info('Attempting to get execution context ID.');
    await tryGetContextId(chromeProxyService);
    _logger.info('Got execution context ID.');
  } on StateError catch (e) {
    // We couldn't find the execution context. `hotRestart` may have been
    // triggered in the middle of a full reload.
    return {
      'error': {
        'code': RPCErrorKind.kInternalError.code,
        'message': e.message,
      },
    };
  }
  // Start listening for isolate create events before issuing a hot
  // restart. Only return success after the isolate has fully started.
  final stream = chromeProxyService.onEvent('Isolate');
  try {
    // If we should pause isolates on start, then only run main once we get a
    // resume event.
    final pauseIsolatesOnStart = chromeProxyService.pauseIsolatesOnStart;
    if (pauseIsolatesOnStart) {
      _waitForResumeEventToRunMain(chromeProxyService);
    }
    // Generate run id to hot restart all apps loaded into the tab.
    final runId = const Uuid().v4().toString();
    _logger.info('Issuing \$dartHotRestartDwds request');
    await chromeProxyService.inspector.jsEvaluate(
      '\$dartHotRestartDwds(\'$runId\', $pauseIsolatesOnStart);',
      awaitPromise: true,
    );
    _logger.info('\$dartHotRestartDwds request complete.');
  } on WipError catch (exception) {
    final code = exception.error?['code'];
    final message = exception.error?['message'];
    // This corresponds to `Execution context was destroyed` which can
    // occur during a hot restart that must fall back to a full reload.
    if (code != RPCErrorKind.kServerError.code) {
      return {
        'error': {
          'code': code,
          'message': message,
          'data': exception,
        },
      };
    }
  } on ChromeDebugException catch (exception) {
    // Exceptions thrown by the injected client during hot restart.
    return {
      'error': {
        'code': RPCErrorKind.kInternalError.code,
        'message': '$exception',
      },
    };
  }
  _logger.info('Waiting for Isolate Start event.');
  await stream.firstWhere((event) => event.kind == EventKind.kIsolateStart);
  chromeProxyService.terminatingIsolates = false;

  _logger.info('Successful hot restart');
  return {'result': Success().toJson()};
}

void _waitForResumeEventToRunMain(
  ChromeProxyService chromeProxyService,
) {
  final issuedReadyToRunMainCompleter = Completer<void>();

  final resumeEventsSubscription =
      chromeProxyService.resumeAfterHotRestartEventsStream.listen((_) async {
    await chromeProxyService.inspector.jsEvaluate('\$dartReadyToRunMain();');
    if (!issuedReadyToRunMainCompleter.isCompleted) {
      issuedReadyToRunMainCompleter.complete();
    }
  });

  safeUnawaited(
    issuedReadyToRunMainCompleter.future.then((_) {
      resumeEventsSubscription.cancel();
    }),
  );
}

Future<Map<String, dynamic>> _fullReload(
  ChromeProxyService chromeProxyService,
) async {
  _logger.info('Attempting a full reload');
  await chromeProxyService.remoteDebugger.enablePage();
  await chromeProxyService.remoteDebugger.pageReload();
  _logger.info('Successful full reload');
  return {'result': Success().toJson()};
}

Future<void> _disableBreakpointsAndResume(
  VmService client,
  ChromeProxyService chromeProxyService,
) async {
  _logger.info('Attempting to disable breakpoints and resume the isolate');
  final vm = await client.getVM();
  final isolates = vm.isolates;
  if (isolates == null || isolates.isEmpty) {
    throw StateError('No active isolate to resume.');
  }
  final isolateId = isolates.first.id;
  if (isolateId == null) {
    throw StateError('No active isolate to resume.');
  }
  await chromeProxyService.disableBreakpoints();
  try {
    // Any checks for paused status result in race conditions or hangs
    // at this point:
    //
    // - `getIsolate()` and check for status:
    //    the app might still pause on existing breakpoint.
    //
    // - `pause()` and wait for `Debug.paused` event:
    //   chrome does not send the `Debug.Paused `notification
    //   without shifting focus to chrome.
    //
    // Instead, just try resuming and
    // ignore failures indicating that the app is already running:
    //
    // WipError -32000 Can only perform operation while paused.
    await client.resume(isolateId);
  } on RPCError catch (e, s) {
    if (!e.message.contains('Can only perform operation while paused')) {
      _logger.severe('Hot restart failed to resume exiting isolate', e, s);
      rethrow;
    }
  }
  _logger.info('Successfully disabled breakpoints and resumed the isolate');
}
