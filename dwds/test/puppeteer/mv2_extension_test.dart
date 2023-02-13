// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@OnPlatform({
  // TODO(elliette): Enable on Windows.
  'windows': Skip('https://github.com/dart-lang/webdev/issues/1724'),
  // TODO(elliette): Enable on Linux.
  'linux': Skip('https://github.com/dart-lang/webdev/issues/1787'),
})
@Timeout(Duration(minutes: 2))

import 'package:test/test.dart';

import 'extension_common.dart';

enum Panel { debugger, inspector }

void main() {
  testAll(isMV3: false);
}
