import AVFoundation
import Flutter
import Foundation
import UIKit

/// Native audio extract + dub export for iOS (AVFoundation).
/// MKV softsub demux still goes through Dart media_kit harvest when needed.
final class AudioToolsPlugin: NSObject, FlutterPlugin {
  private var cancelledRequests = Set<String>()
  private let lock = NSLock()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.shadowing.english/audio_tools",
      binaryMessenger: registrar.messenger()
    )
    let instance = AudioToolsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ffmpegAvailable":
      result(false)
    case "runFfmpeg":
      result(
        FlutterError(
          code: "unsupported",
          message: "iOS uses AVFoundation for extract/export; softsubs use media_kit.",
          details: nil
        )
      )
    case "extractPronunciationAudio":
      handleExtract(call, result: result)
    case "cancelPronunciationAudioExtraction":
      if let requestId = (call.arguments as? [String: Any])?["requestId"] as? String {
        lock.lock()
        cancelledRequests.insert(requestId)
        lock.unlock()
        result(true)
      } else {
        result(false)
      }
    case "exportDubbedVideo":
      handleExportDub(call, result: result)
    case "captureFrameAt":
      handleCaptureFrame(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isCancelled(_ requestId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelledRequests.contains(requestId)
  }

  private func clearCancelled(_ requestId: String) {
    lock.lock()
    cancelledRequests.remove(requestId)
    lock.unlock()
  }

  private func intArg(_ args: [String: Any], _ key: String) -> Int? {
    if let v = args[key] as? Int { return v }
    if let v = args[key] as? NSNumber { return v.intValue }
    return nil
  }

  private func handleExtract(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let requestId = args["requestId"] as? String,
      let sourcePath = args["sourcePath"] as? String,
      let startMs = intArg(args, "startMs"),
      let endMs = intArg(args, "endMs"),
      endMs > startMs,
      endMs - startMs <= 60_000
    else {
      result(FlutterError(code: "bad_args", message: "Invalid pronunciation audio range.", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let path = try self.extractPronunciationAudio(
          requestId: requestId,
          sourcePath: sourcePath,
          startMs: startMs,
          endMs: endMs
        )
        DispatchQueue.main.async {
          self.clearCancelled(requestId)
          result(path)
        }
      } catch {
        DispatchQueue.main.async {
          self.clearCancelled(requestId)
          result(
            FlutterError(
              code: "pronunciation_extract_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func handleCaptureFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let sourcePath = args["sourcePath"] as? String,
      !sourcePath.isEmpty
    else {
      result(FlutterError(code: "bad_args", message: "sourcePath is required.", details: nil))
      return
    }
    let positionMs = intArg(args, "positionMs") ?? 0
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let jpeg = try self.captureFrameJpeg(sourcePath: sourcePath, positionMs: positionMs)
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: jpeg)) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "capture_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func captureFrameJpeg(sourcePath: String, positionMs: Int) throws -> Data {
    let url = URL(fileURLWithPath: sourcePath)
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1280, height: 1280)
    let time = CMTime(value: CMTimeValue(max(0, positionMs)), timescale: 1000)
    var actual = CMTime.zero
    let cgImage = try generator.copyCGImage(at: time, actualTime: &actual)
    let image = UIImage(cgImage: cgImage)
    guard let data = image.jpegData(compressionQuality: 0.85) else {
      throw NSError(domain: "AudioTools", code: 20, userInfo: [
        NSLocalizedDescriptionKey: "unable to encode jpeg frame",
      ])
    }
    return data
  }

  private func extractPronunciationAudio(
    requestId: String,
    sourcePath: String,
    startMs: Int,
    endMs: Int
  ) throws -> String {
    let url = URL(fileURLWithPath: sourcePath)
    let ext = url.pathExtension.lowercased()
    // Fail fast: AVFoundation rarely opens MKV/WebM — Dart will use FFmpegKit.
    if ["mkv", "webm", "avi", "flv", "ts", "m2ts", "wmv"].contains(ext) {
      throw NSError(domain: "AudioTools", code: 0, userInfo: [
        NSLocalizedDescriptionKey: "container requires ffmpeg",
      ])
    }
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "AudioTools", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "no audio track found",
      ])
    }

    let start = CMTime(value: CMTimeValue(startMs), timescale: 1000)
    let duration = CMTime(value: CMTimeValue(endMs - startMs), timescale: 1000)
    let range = CMTimeRange(start: start, duration: duration)

    let reader = try AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: 16_000,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw NSError(domain: "AudioTools", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "cannot add reader output",
      ])
    }
    reader.add(output)
    reader.timeRange = range
    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "AudioTools", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "reader failed to start",
      ])
    }

    var pcm = Data()
    while reader.status == .reading {
      if isCancelled(requestId) {
        reader.cancelReading()
        throw NSError(domain: "AudioTools", code: 4, userInfo: [
          NSLocalizedDescriptionKey: "cancelled",
        ])
      }
      guard let sample = output.copyNextSampleBuffer() else { break }
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      var length = 0
      var dataPointer: UnsafeMutablePointer<Int8>?
      CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
      if let dataPointer, length > 0 {
        pcm.append(Data(bytes: dataPointer, count: length))
      }
    }
    if reader.status == .failed {
      throw reader.error ?? NSError(domain: "AudioTools", code: 5, userInfo: [
        NSLocalizedDescriptionKey: "reader failed",
      ])
    }
    if pcm.isEmpty {
      throw NSError(domain: "AudioTools", code: 6, userInfo: [
        NSLocalizedDescriptionKey: "empty pcm",
      ])
    }

    let outDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("pronunciation_\(requestId)", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let outURL = outDir.appendingPathComponent("reference.wav")
    try writeWav(pcm16Mono: pcm, sampleRate: 16_000, to: outURL)
    return outURL.path
  }

  private func handleExportDub(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let sourcePath = args["sourcePath"] as? String,
      let outputPath = args["outputPath"] as? String,
      let startMs = intArg(args, "startMs"),
      let endMs = intArg(args, "endMs"),
      endMs > startMs,
      let rawTakes = args["takes"] as? [[String: Any]]
    else {
      result(FlutterError(code: "bad_args", message: "Invalid dubbed export args.", details: nil))
      return
    }
    let accompanimentPath = args["accompanimentPath"] as? String
    let takes: [(startMs: Int, endMs: Int, wavPath: String)] = rawTakes.compactMap { row in
      let s: Int? = {
        if let v = row["startMs"] as? Int { return v }
        if let v = row["startMs"] as? NSNumber { return v.intValue }
        return nil
      }()
      let e: Int? = {
        if let v = row["endMs"] as? Int { return v }
        if let v = row["endMs"] as? NSNumber { return v.intValue }
        return nil
      }()
      guard let s, let e, let wav = row["wavPath"] as? String, e > s else { return nil }
      return (s, e, wav)
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let path = try self.exportDubbedVideo(
          sourcePath: sourcePath,
          outputPath: outputPath,
          startMs: startMs,
          endMs: endMs,
          takes: takes,
          accompanimentPath: accompanimentPath
        )
        DispatchQueue.main.async { result(path) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "export_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func exportDubbedVideo(
    sourcePath: String,
    outputPath: String,
    startMs: Int,
    endMs: Int,
    takes: [(startMs: Int, endMs: Int, wavPath: String)],
    accompanimentPath: String?
  ) throws -> String {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let ext = sourceURL.pathExtension.lowercased()
    if ["mkv", "webm", "avi", "flv", "ts", "m2ts", "wmv"].contains(ext) {
      throw NSError(domain: "AudioTools", code: 0, userInfo: [
        NSLocalizedDescriptionKey: "container requires ffmpeg",
      ])
    }
    let asset = AVURLAsset(url: sourceURL)
    let start = CMTime(value: CMTimeValue(startMs), timescale: 1000)
    let duration = CMTime(value: CMTimeValue(endMs - startMs), timescale: 1000)
    let range = CMTimeRange(start: start, duration: duration)

    let composition = AVMutableComposition()
    guard
      let videoTrack = asset.tracks(withMediaType: .video).first,
      let compVideo = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw NSError(domain: "AudioTools", code: 10, userInfo: [
        NSLocalizedDescriptionKey: "missing video track",
      ])
    }
    try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)

    // Mix bed: accompaniment WAV if present, else source audio (ducked during takes).
    let mixInputParams = NSMutableArray()

    if let accompanimentPath,
       !accompanimentPath.isEmpty,
       FileManager.default.fileExists(atPath: accompanimentPath),
       let compAudio = composition.addMutableTrack(
         withMediaType: .audio,
         preferredTrackID: kCMPersistentTrackID_Invalid
       )
    {
      let accomp = AVURLAsset(url: URL(fileURLWithPath: accompanimentPath))
      if let aTrack = accomp.tracks(withMediaType: .audio).first {
        let aDur = min(duration, accomp.duration)
        try compAudio.insertTimeRange(
          CMTimeRange(start: .zero, duration: aDur),
          of: aTrack,
          at: .zero
        )
        let p = AVMutableAudioMixInputParameters(track: compAudio)
        p.setVolume(1.0, at: .zero)
        mixInputParams.add(p)
      }
    } else if let sourceAudio = asset.tracks(withMediaType: .audio).first,
              let compAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              )
    {
      try compAudio.insertTimeRange(range, of: sourceAudio, at: .zero)
      let p = AVMutableAudioMixInputParameters(track: compAudio)
      // Duck during each take window.
      p.setVolume(1.0, at: .zero)
      for take in takes {
        let localStart = max(0, take.startMs - startMs)
        let localEnd = max(localStart, take.endMs - startMs)
        let t0 = CMTime(value: CMTimeValue(localStart), timescale: 1000)
        let t1 = CMTime(value: CMTimeValue(localEnd), timescale: 1000)
        p.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.05, timeRange: CMTimeRange(start: t0, duration: CMTime(value: 1, timescale: 100)))
        p.setVolume(0.05, at: t0)
        p.setVolumeRamp(fromStartVolume: 0.05, toEndVolume: 1.0, timeRange: CMTimeRange(start: t1, duration: CMTime(value: 1, timescale: 100)))
      }
      mixInputParams.add(p)
    }

    for take in takes {
      let wavAsset = AVURLAsset(url: URL(fileURLWithPath: take.wavPath))
      guard let wavTrack = wavAsset.tracks(withMediaType: .audio).first,
            let compTake = composition.addMutableTrack(
              withMediaType: .audio,
              preferredTrackID: kCMPersistentTrackID_Invalid
            )
      else { continue }
      let delayMs = max(0, take.startMs - startMs)
      let insertAt = CMTime(value: CMTimeValue(delayMs), timescale: 1000)
      let takeDur = CMTime(
        value: CMTimeValue(max(1, take.endMs - take.startMs)),
        timescale: 1000
      )
      let available = min(takeDur, wavAsset.duration)
      try compTake.insertTimeRange(
        CMTimeRange(start: .zero, duration: available),
        of: wavTrack,
        at: insertAt
      )
      let p = AVMutableAudioMixInputParameters(track: compTake)
      p.setVolume(1.0, at: .zero)
      mixInputParams.add(p)
    }

    let mix = AVMutableAudioMix()
    mix.inputParameters = mixInputParams as? [AVAudioMixInputParameters] ?? []

    let outURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outURL)
    try FileManager.default.createDirectory(
      at: outURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    guard let export = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw NSError(domain: "AudioTools", code: 11, userInfo: [
        NSLocalizedDescriptionKey: "export session unavailable",
      ])
    }
    export.outputURL = outURL
    export.outputFileType = .mp4
    export.audioMix = mix
    export.timeRange = CMTimeRange(start: .zero, duration: duration)

    let semaphore = DispatchSemaphore(value: 0)
    export.exportAsynchronously { semaphore.signal() }
    semaphore.wait()

    if export.status != .completed {
      throw export.error ?? NSError(domain: "AudioTools", code: 12, userInfo: [
        NSLocalizedDescriptionKey: "export failed",
      ])
    }
    return outURL.path
  }

  private func writeWav(pcm16Mono data: Data, sampleRate: Int, to url: URL) throws {
    var header = Data()
    func appendUInt32(_ v: UInt32) {
      var le = v.littleEndian
      header.append(Data(bytes: &le, count: 4))
    }
    func appendUInt16(_ v: UInt16) {
      var le = v.littleEndian
      header.append(Data(bytes: &le, count: 2))
    }
    let dataSize = UInt32(data.count)
    header.append(contentsOf: Array("RIFF".utf8))
    appendUInt32(36 + dataSize)
    header.append(contentsOf: Array("WAVE".utf8))
    header.append(contentsOf: Array("fmt ".utf8))
    appendUInt32(16)
    appendUInt16(1) // PCM
    appendUInt16(1) // mono
    appendUInt32(UInt32(sampleRate))
    appendUInt32(UInt32(sampleRate * 2))
    appendUInt16(2)
    appendUInt16(16)
    header.append(contentsOf: Array("data".utf8))
    appendUInt32(dataSize)
    try (header + data).write(to: url)
  }
}
