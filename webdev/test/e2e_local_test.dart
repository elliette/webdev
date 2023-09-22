// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'package:test/test.dart';

import 'e2e_common.dart';

void main() {
  testAll(useWebdevFromPub: false);
}
