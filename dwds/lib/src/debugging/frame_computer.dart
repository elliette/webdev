// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/utilities/synchronized.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class FrameComputer {
  final Debugger debugger;

  // To ensure that the frames are computed only once, we use an atomic queue
  // to guard the work. Frames are computed sequentially.
  final _queue = AtomicQueue();

  final List<WipCallFrame> _callFrames;
  final List<Frame> _dartFrames = [];
  final List<Frame> _jsFrames = [];

  var _frameIndex = 0;

  StackTrace? _asyncStackTrace;
  List<CallFrame>? _asyncFramesToProcess;

  FrameComputer(this.debugger, this._callFrames, {StackTrace? asyncStackTrace})
      : _asyncStackTrace = asyncStackTrace;

  /// Given a frame index, return the corresponding JS frame.
  WipCallFrame? jsFrameForIndex(int frameIndex) {
    // Clients can send us indices greater than the number of JS frames as async
    // frames don't have corresponding WipCallFrames.
    return frameIndex < _callFrames.length ? _callFrames[frameIndex] : null;
  }

  /// Translates Chrome callFrames contained in [DebuggerPausedEvent] into Dart
  /// [Frame]s.
  Future<List<Frame>> calculateFrames({int? limit}) async {
    return _queue.run(() async {
      if (limit != null && _dartFrames.length >= limit) {
        return _dartFrames.take(limit).toList();
      }
      // TODO(grouma) - We compute the frames sequentially. Consider computing
      // frames in parallel batches.
      await _collectSyncFrames(limit: limit);
      await _collectAsyncFrames(limit: limit);

      // Remove any trailing kAsyncSuspensionMarker frame.
      if (limit == null &&
          _dartFrames.isNotEmpty &&
          _dartFrames.last.kind == FrameKind.kAsyncSuspensionMarker) {
        _dartFrames.removeLast();
      }

      // Only show JS frames if we were unable to calculate any Dart frames.
      if (_dartFrames.isEmpty && _jsFrames.isNotEmpty) {
        return _jsFrames.take(limit ?? _jsFrames.length).toList();
      }

      return _dartFrames;
    });
  }

  Future<void> _collectSyncFrames({int? limit}) async {
    while (_frameIndex < _callFrames.length) {
      if (limit != null && _dartFrames.length == limit) return;

      final callFrame = _callFrames[_frameIndex];
      final dartFrame =
          await debugger.calculateDartFrameFor(callFrame, _frameIndex);
      if (dartFrame != null) {
        _dartFrames.add(dartFrame);
      } else {
        final jsFrame = debugger.calculateJsFrameFor(callFrame, _frameIndex);
        if (jsFrame != null) {
          _jsFrames.add(jsFrame);
        }
      }
      _frameIndex += 1;
    }
  }

  Future<void> _collectAsyncFrames({int? limit}) async {
    if (_asyncStackTrace == null) return;

    while (_asyncStackTrace != null) {
      final asyncStackTrace = _asyncStackTrace!;
      if (limit != null && _dartFrames.length == limit) {
        return;
      }

      // We are processing a new set of async frames, add a suspension marker.
      if (_asyncFramesToProcess == null) {
        if (_dartFrames.isNotEmpty &&
            _dartFrames.last.kind != FrameKind.kAsyncSuspensionMarker) {
          _dartFrames.add(Frame(
              index: _frameIndex++, kind: FrameKind.kAsyncSuspensionMarker));
        }
        _asyncFramesToProcess = asyncStackTrace.callFrames;
      } else {
        final asyncFramesToProcess = _asyncFramesToProcess!;
        // Process a single async frame.
        if (asyncFramesToProcess.isNotEmpty) {
          final callFrame = asyncFramesToProcess.removeAt(0);
          final location = WipLocation.fromValues(
              callFrame.scriptId, callFrame.lineNumber,
              columnNumber: callFrame.columnNumber);

          final tempWipFrame = WipCallFrame({
            'url': callFrame.url,
            'functionName': callFrame.functionName,
            'location': location.json,
            'scopeChain': [],
          });

          final frame = await debugger.calculateDartFrameFor(
            tempWipFrame,
            _frameIndex,
            populateVariables: false,
          );
          if (frame != null) {
            frame.kind = FrameKind.kAsyncCausal;
            _dartFrames.add(frame);
          } else {
            final jsFrame = debugger.calculateJsFrameFor(
              tempWipFrame,
              _frameIndex,
              isAsync: true,
            );
            if (jsFrame != null) {
              _dartFrames.add(jsFrame);
            }
          }
          _frameIndex += 1;
        }
      }

      // Async frames are no longer on the stack - we don't have local variable
      // information for them.
      if (_asyncFramesToProcess!.isEmpty) {
        _asyncStackTrace = asyncStackTrace.parent;
        _asyncFramesToProcess = null;
      }
    }
  }
}
