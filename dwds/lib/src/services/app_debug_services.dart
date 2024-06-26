// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/dwds_vm_client.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart'
    show ChromeProxyService;
import 'package:dwds/src/services/debug_service.dart';

/// A container for all the services required for debugging an application.
class AppDebugServices {
  final DebugService debugService;
  final DwdsVmClient dwdsVmClient;
  final DwdsStats dwdsStats;
  final Uri? ddsUri;

  ChromeProxyService get chromeProxyService =>
      debugService.chromeProxyService as ChromeProxyService;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  /// The instance ID for the currently connected application, if there is one.
  ///
  /// We only allow a given app to be debugged in a single tab at a time.
  String? connectedInstanceId;

  AppDebugServices(
    this.debugService,
    this.dwdsVmClient,
    this.dwdsStats,
    this.ddsUri,
  );

  Future<void> close() =>
      _closed ??= Future.wait([debugService.close(), dwdsVmClient.close()]);
}
