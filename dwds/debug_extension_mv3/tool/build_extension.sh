#!/bin/bash

# Copyright 2022 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# INSTRUCTIONS:

# Builds the unminifed dart2js app (see DDC issue: https://github.com/dart-lang/sdk/issues/49869):
# ./tool/build_extension.sh

# Builds the dart2js app for release:
# ./tool/build_extension.sh prod

prod="false"
dev="true"

case "$1" in
    prod)
        prod="true"
        dev="false"
        shift;;
esac

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Building dart2js-compiled extension to /compiled directory."
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
dart run build_runner build web --output build --release --define is_dev=$dev

if [ $prod == false ]; then
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "Updating dev files in /compiled directory."
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    dart tool/update_dev_files.dart
fi
