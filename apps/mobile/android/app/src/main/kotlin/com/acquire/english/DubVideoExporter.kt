package com.acquire.english

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

/**
 * Best-effort dubbed clip exporter:
 * - Copies the video track for [startMs, endMs]
 * - Builds a ducked / take-overlaid PCM bed then encodes AAC
 *
 * When accompanimentPath is set, that WAV replaces the source bed
 * (趣配音 keep-BGM path). Otherwise dialogue windows are heavily ducked.
 */
object DubVideoExporter {
    data class Take(
        val startMs: Int,
        val endMs: Int,
        val wavPath: String,
    )

    fun export(
        sourcePath: String,
        outputPath: String,
        startMs: Int,
        endMs: Int,
        takes: List<Take>,
        accompanimentPath: String?,
    ): String {
        require(endMs > startMs) { "invalid range" }
        val source = File(sourcePath)
        require(source.exists()) { "video file not found" }
        val output = File(outputPath)
        output.parentFile?.mkdirs()
        if (output.exists()) {
            output.delete()
        }

        val durationMs = endMs - startMs
        val sampleRate = 44100
        val bed = FloatArray((durationMs / 1000.0 * sampleRate).toInt().coerceAtLeast(sampleRate / 10))

        if (!accompanimentPath.isNullOrBlank() && File(accompanimentPath).exists()) {
            overlayWav(bed, accompanimentPath, sampleRate, 0, 1f, sourceStartMs = startMs)
        } else {
            // Silence bed with light tone so AAC isn't empty; ducking path
            // primarily relies on user takes. Video keeps picture.
            bed.fill(0.02f)
            for (take in takes) {
                val localStart = (take.startMs - startMs).coerceAtLeast(0)
                val localEnd = (take.endMs - startMs).coerceAtMost(durationMs)
                val from = (localStart / 1000.0 * sampleRate).toInt()
                val to = (localEnd / 1000.0 * sampleRate).toInt().coerceAtMost(bed.size)
                for (i in from until to) {
                    bed[i] *= 0.05f
                }
            }
        }
        for (take in takes) {
            val delayMs = (take.startMs - startMs).coerceAtLeast(0)
            overlayWav(bed, take.wavPath, sampleRate, delayMs, 1f)
        }

        val pcm = ShortArray(bed.size)
        for (i in bed.indices) {
            val v = (bed[i] * 32767f).toInt().coerceIn(-32768, 32767)
            pcm[i] = v.toShort()
        }

        val muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(source.absolutePath)
            val videoTrack = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("video/") == true
            } ?: error("no video track")
            val videoFormat = extractor.getTrackFormat(videoTrack)
            extractor.selectTrack(videoTrack)
            val startUs = startMs.toLong() * 1000L
            val endUs = endMs.toLong() * 1000L
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val videoIndex = muxer.addTrack(videoFormat)

            val aacFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1)
            aacFormat.setInteger(MediaFormat.KEY_BIT_RATE, 128000)
            aacFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, 2)
            aacFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder.configure(aacFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            var audioTrackIndex = -1
            var muxerStarted = false
            fun ensureStarted() {
                if (!muxerStarted) {
                    muxer.start()
                    muxerStarted = true
                }
            }

            // Feed PCM → AAC, then interleave with video copy.
            var pcmOffset = 0
            val inBufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var presentationUs = 0L
            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = encoder.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val input = encoder.getInputBuffer(inIndex)!!
                        input.clear()
                        val capacityShorts = input.capacity() / 2
                        val remaining = pcm.size - pcmOffset
                        if (remaining <= 0) {
                            encoder.queueInputBuffer(
                                inIndex,
                                0,
                                0,
                                presentationUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            val count = min(capacityShorts, remaining)
                            for (i in 0 until count) {
                                input.putShort(pcm[pcmOffset + i])
                            }
                            val bytes = count * 2
                            encoder.queueInputBuffer(inIndex, 0, bytes, presentationUs, 0)
                            pcmOffset += count
                            presentationUs += (count * 1_000_000L) / sampleRate
                        }
                    }
                }
                val outIndex = encoder.dequeueOutputBuffer(inBufferInfo, 10000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        audioTrackIndex = muxer.addTrack(encoder.outputFormat)
                        ensureStarted()
                    }
                    outIndex >= 0 -> {
                        if (audioTrackIndex < 0) {
                            audioTrackIndex = muxer.addTrack(encoder.outputFormat)
                            ensureStarted()
                        }
                        val outBuf = encoder.getOutputBuffer(outIndex)!!
                        if (inBufferInfo.size > 0) {
                            outBuf.position(inBufferInfo.offset)
                            outBuf.limit(inBufferInfo.offset + inBufferInfo.size)
                            muxer.writeSampleData(audioTrackIndex, outBuf, inBufferInfo)
                        }
                        val eos = inBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        encoder.releaseOutputBuffer(outIndex, false)
                        if (eos) {
                            outputDone = true
                        }
                    }
                }
            }
            encoder.stop()
            encoder.release()

            ensureStarted()
            val buffer = ByteBuffer.allocate(1 shl 20)
            val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                val timeUs = extractor.sampleTime
                if (timeUs > endUs) break
                if (timeUs >= startUs) {
                    info.offset = 0
                    info.size = sampleSize
                    info.presentationTimeUs = timeUs - startUs
                    info.flags = extractor.sampleFlags
                    muxer.writeSampleData(videoIndex, buffer, info)
                }
                extractor.advance()
            }
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                muxer.stop()
            } catch (_: Exception) {
            }
            try {
                muxer.release()
            } catch (_: Exception) {
            }
        }
        require(output.exists() && output.length() > 0) { "export produced empty file" }
        return output.absolutePath
    }

    private fun overlayWav(
        bed: FloatArray,
        wavPath: String,
        sampleRate: Int,
        delayMs: Int,
        gain: Float,
        sourceStartMs: Int = 0,
    ) {
        val file = File(wavPath)
        if (!file.exists()) return
        val raf = RandomAccessFile(file, "r")
        try {
            if (raf.readInt() != 0x52494646) return // RIFF
            raf.skipBytes(4)
            if (raf.readInt() != 0x57415645) return // WAVE
            var dataSize = 0
            var wavRate = sampleRate
            var channels = 1
            var bits = 16
            while (raf.filePointer < raf.length() - 8) {
                val chunkId = raf.readInt()
                val chunkSize = Integer.reverseBytes(raf.readInt())
                when (chunkId) {
                    0x666d7420 -> { // fmt
                        val audioFormat = java.lang.Short.reverseBytes(raf.readShort()).toInt()
                        channels = java.lang.Short.reverseBytes(raf.readShort()).toInt()
                        wavRate = Integer.reverseBytes(raf.readInt())
                        raf.skipBytes(6)
                        bits = java.lang.Short.reverseBytes(raf.readShort()).toInt()
                        val consumed = 16
                        if (chunkSize > consumed) raf.skipBytes(chunkSize - consumed)
                        if (audioFormat != 1 || bits != 16) return
                    }
                    0x64617461 -> { // data
                        dataSize = chunkSize
                        break
                    }
                    else -> raf.skipBytes(chunkSize)
                }
            }
            if (dataSize <= 0) return
            if (channels <= 0 || wavRate <= 0) return
            val dataOffset = raf.filePointer
            val frameBytes = channels * 2
            val frameCount = min(dataSize.toLong(), raf.length() - dataOffset) / frameBytes
            val start = (delayMs / 1000.0 * sampleRate).toInt()
            val step = wavRate.toDouble() / sampleRate
            val buffer = ByteArray((65536 / frameBytes).coerceAtLeast(1) * frameBytes)
            val pcm = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN)
            var bufferFrame = -1L
            var bufferFrames = 0
            var src = sourceStartMs / 1000.0 * wavRate
            var dst = start
            while (dst < bed.size && src.toLong() < frameCount) {
                val frame = src.toLong()
                if (frame < bufferFrame || frame >= bufferFrame + bufferFrames) {
                    bufferFrame = frame
                    bufferFrames = min(frameCount - frame, (buffer.size / frameBytes).toLong()).toInt()
                    raf.seek(dataOffset + frame * frameBytes)
                    raf.readFully(buffer, 0, bufferFrames * frameBytes)
                }
                val offset = (frame - bufferFrame).toInt() * frameBytes
                var sample = 0
                for (c in 0 until channels) {
                    sample += pcm.getShort(offset + c * 2).toInt()
                }
                sample /= channels
                bed[dst] = (bed[dst] + (sample / 32768f) * gain).coerceIn(-1f, 1f)
                dst += 1
                src += step
            }
        } finally {
            raf.close()
        }
    }
}
