import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hnd_viewer/src/recording/recording_writer.dart';

/// Returns the absolute path of [executable] resolved against the `PATH`
/// environment variable, or `null` when the executable is not available.
///
/// A candidate must be a regular file with the execute bit set (on POSIX).
/// This is used by [FfmpegMp4Writer] to locate `ffmpeg`, and by callers/tests
/// that want to skip gracefully when ffmpeg is not installed.
Future<String?> findExecutableOnPath(String executable) async {
  final String? pathEnv = Platform.environment['PATH'];
  if (pathEnv == null || pathEnv.isEmpty) return null;
  String exe = executable;
  if (Platform.isWindows && !exe.toLowerCase().endsWith('.exe')) {
    exe = '$exe.exe';
  }
  // PATH *list* entries are separated by ':' on POSIX and ';' on Windows
  // (Platform.pathSeparator is the file-path separator, not this).
  final String separator = Platform.isWindows ? ';' : ':';
  for (final String dir in pathEnv.split(separator)) {
    if (dir.isEmpty) continue;
    final File candidate = File('$dir${Platform.pathSeparator}$exe');
    try {
      if (!await candidate.exists()) continue;
      if (!Platform.isWindows) {
        // POSIX execute bit for owner/group/others; exists() is true even for
        // non-executable files.
        final int mode = candidate.statSync().mode;
        if (mode & 0x49 == 0) continue;
      }
      return candidate.absolute.path;
    } on FileSystemException {
      // Unreadable directory entry; keep scanning.
      continue;
    }
  }
  return null;
}

/// A [RecordingWriter] that transcodes JPEG frames into an H.264 MP4 file by
/// spawning the system `ffmpeg` binary.
///
/// Encoding happens as a single ffmpeg process that reads the JPEG frames as a
/// raw MJPEG stream on stdin (`-f mjpeg -framerate <rate> -i pipe:0`) and
/// muxes H.264 into a faststart MP4. The ffmpeg binary is resolved from
/// `PATH` unless an explicit [ffmpegPath] is supplied.
///
/// ## Timing / duration
///
/// Frames arrive with an `elapsed` timestamp and may be jittery or replayed
/// much faster than real time, so a writer that streamed frames to ffmpeg at a
/// *fixed* nominal rate could only produce a container whose duration is
/// `frameCount / nominalRate` — typically not the recorded duration. To make
/// the resulting duration track the recording, frames (and their elapsed
/// times) are buffered during [writeFrame] and piped to ffmpeg in [finish],
/// once the frame count and final elapsed are known. The input framerate is
/// then derived as `frameCount / finalElapsed`, which yields an MP4 whose
/// container duration equals the final frame's elapsed time. [nominalFps] is
/// used when elapsed carries no usable timing (fewer than two frames, or a
/// zero duration).
///
/// Buffered frames are stored by reference (no copy); the caller's
/// [RecordingSession] already holds the JPEG bytes in memory, so this writer
/// adds no additional frame payload copies.
///
/// ## Output
///
/// The MP4 is written to [outputPath] (default: a fresh file in the system
/// temp directory). [start] deletes any previous file at that path and
/// [finish] returns its absolute path. If ffmpeg exits non-zero, or the
/// pipeline fails for any other reason, the child process is killed (when
/// still running) and a descriptive exception is thrown, leaving no partial
/// file behind.
class FfmpegMp4Writer implements RecordingWriter {
  FfmpegMp4Writer({
    String? outputPath,
    this.ffmpegPath,
    this.resolutionHint,
    double nominalFps = 12.0,
  })  : outputPath = outputPath ?? _defaultOutputPath(),
        nominalFps = nominalFps > 0 ? nominalFps : 12.0;

  /// Absolute path of the `.mp4` file to produce (created/overwritten by
  /// [start]).
  final String outputPath;

  /// Path to the ffmpeg executable, or `null` to resolve `ffmpeg` from
  /// `PATH`.
  final String? ffmpegPath;

  /// Optional output resolution hint such as `480x480`; when provided it is
  /// applied as an ffmpeg `scale` filter. When `null` (default) the native
  /// resolution of the JPEG frames is preserved.
  final String? resolutionHint;

  /// Nominal input framerate used when elapsed timestamps carry no usable
  /// timing information (fewer than two frames or a zero total duration).
  final double nominalFps;

  final List<Uint8List> _frames = [];
  Duration _lastElapsed = Duration.zero;
  String? _activePath;
  bool _started = false;

  @override
  Future<void> start() async {
    _frames.clear();
    _lastElapsed = Duration.zero;
    final File out = File(outputPath).absolute;
    _activePath = out.path;
    await out.parent.create(recursive: true);
    if (await out.exists()) {
      await out.delete();
    }
    _started = true;
  }

  @override
  Future<void> writeFrame(Uint8List jpeg, Duration elapsed) async {
    _ensureStarted();
    _frames.add(jpeg);
    if (elapsed > _lastElapsed) {
      _lastElapsed = elapsed;
    }
  }

  @override
  Future<String> finish() async {
    _ensureStarted();
    if (_frames.isEmpty) {
      throw StateError(
          'FfmpegMp4Writer.finish() called before any frames were written.');
    }

    final String ffmpeg = await _resolveFfmpeg();
    final String outPath = _activePath!;
    final double fps = _encodeFps();
    final List<String> args = _buildArgs(outPath, fps);

    Process? process;
    final StringBuffer stderrLog = StringBuffer();
    try {
      process = await Process.start(ffmpeg, args);
      // Drain stdout and collect stderr so ffmpeg never blocks on a full
      // pipe; stderr is used to build descriptive failure messages.
      process.stdout.listen((_) {});
      process.stderr
          .transform(utf8.decoder)
          .listen(stderrLog.write, onError: (Object _) {});

      // Feed the buffered frames in order, close stdin so ffmpeg finalizes
      // the file, then wait for it to exit.
      await process.stdin.addStream(Stream.fromIterable(_frames));
      await process.stdin.close();
      final int exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw ProcessException(ffmpeg, args,
            _failureMessage(exitCode, stderrLog.toString()), exitCode);
      }
      return outPath;
    } on ProcessException {
      // Either a non-zero exit or a spawn failure. On a non-zero exit ffmpeg
      // has already terminated; remove any partial file it may have left.
      await _removePartialFile(outPath);
      rethrow;
    } catch (error) {
      // I/O failure while pumping frames or waiting (e.g. ffmpeg died early).
      // Kill the child so no orphan process leaks, then report.
      await _killChild(process);
      await _removePartialFile(outPath);
      final String tail = stderrLog.toString().trimRight();
      throw ProcessException(
          ffmpeg, args, 'ffmpeg pipeline failed: $error\n$tail', -1);
    }
  }

  void _ensureStarted() {
    if (!_started) {
      throw StateError(
          'FfmpegMp4Writer.start() must be called before writeFrame()/finish().');
    }
  }

  /// Resolves the ffmpeg executable to an absolute path, failing with a
  /// descriptive exception when it cannot be found.
  Future<String> _resolveFfmpeg() async {
    final String? configured = ffmpegPath;
    if (configured != null && configured.isNotEmpty) {
      final File file = File(configured);
      if (!await file.exists()) {
        throw FileSystemException(
            'FfmpegMp4Writer: ffmpeg binary not found at the configured '
            'ffmpegPath',
            configured);
      }
      return file.absolute.path;
    }
    final String? found = await findExecutableOnPath('ffmpeg');
    if (found != null) return found;
    throw FileSystemException(
        'FfmpegMp4Writer: "ffmpeg" was not found on PATH; install ffmpeg or '
        'pass the binary location via the ffmpegPath constructor argument');
  }

  /// Chooses the input framerate that makes the container duration track the
  /// recorded duration.
  ///
  /// With the mjpeg demuxer ffmpeg produces a constant-frame-rate stream of
  /// `n` frames whose container duration is `n / fps`. To make that equal the
  /// final frame's elapsed time `e`, the rate must be `n / e`. It can only be
  /// computed once the last frame has arrived, hence buffering until
  /// [finish]. Falls back to [nominalFps] when elapsed is unusable.
  double _encodeFps() {
    final int n = _frames.length;
    final int micros = _lastElapsed.inMicroseconds;
    if (n >= 2 && micros > 0) {
      final double measured = n * 1000000.0 / micros;
      // Guard against degenerate timing producing absurd rates.
      if (measured >= 1.0 && measured <= 240.0) return measured;
    }
    return nominalFps;
  }

  List<String> _buildArgs(String outPath, double fps) {
    final List<String> args = <String>[
      '-y',
      '-v', 'error',
      '-f', 'mjpeg',
      '-framerate', fps.toStringAsFixed(6),
      '-i', 'pipe:0',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      outPath,
    ];
    final String? hint = resolutionHint;
    if (hint != null && hint.isNotEmpty) {
      args.insert(args.length - 1, '-vf');
      args.insert(args.length - 1, 'scale=$hint');
    }
    return args;
  }

  String _failureMessage(int exitCode, String log) {
    final String tail = log.trimRight();
    return tail.isEmpty
        ? 'ffmpeg exited with code $exitCode (no error output captured)'
        : 'ffmpeg exited with code $exitCode:\n$tail';
  }

  Future<void> _killChild(Process? process) async {
    if (process == null) return;
    if (!process.kill(ProcessSignal.sigkill)) return; // already terminated
    try {
      await process.exitCode; // reap so the child cannot linger.
    } on ProcessException {
      // Nothing left to reap; the original failure is what the caller sees.
    }
  }

  Future<void> _removePartialFile(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup only.
    }
  }

  static String _defaultOutputPath() {
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'hnd_recording_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }
}
