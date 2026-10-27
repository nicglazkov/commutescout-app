# On-device neural voices

CommuteScout Drive can speak directions with neural voices that run on the
phone. A user downloads a voice pack once. After that, speech needs no network
and no account. The system voices stay available as the fallback.

This page covers the voice packs, their licenses, how the apps use them, and how
to add a voice. The machine-readable catalog is
[`shared/voices.json`](../shared/voices.json). Both apps read it.

## Voice packs

The packs are assets on the
[`voices-v1` release](https://github.com/nicglazkov/commutescout-app/releases/tag/voices-v1).
Each pack is a zip archive and is also available as individual files named
`<pack id>.<file name>`. Every pack includes its `LICENSE` and `NOTICE`.

| Pack | Engine | Download | Sample rate | License |
|---|---|---|---|---|
| `supertonic2-en` (Fast voices) | Supertonic 2, int8 with a float16 vocoder | 121.2 MB of files, 108.5 MB zip | 44.1 kHz | BigScience OpenRAIL-M |
| `kokoro-en-v1_0` (Natural voices) | Kokoro v1.0, int8 with a float32 generator | 188.0 MB of files, 149.7 MB zip | 24 kHz | Apache-2.0 |

The October 2026 builds replaced `model.int8.onnx` with `model.mixed.onnx`
and `vocoder.int8.onnx` with `vocoder.fp16.onnx` to remove audible artifacts;
see [Quality checks](#quality-checks). The zips of these builds are
`<pack id>.v2.zip`, and the preview clips are `preview.<voice id>.v2.m4a`.

### Listed voices

A pack holds more speakers than the app lists. The catalog lists the voices that
scored best for driving prompts. The display names belong to CommuteScout.

| Voice | Pack | Speaker id | Upstream name | Accent | Gender |
|---|---|---|---|---|---|
| Nora (default) | `supertonic2-en` | 2 | F3 | US | Female |
| Clara | `supertonic2-en` | 1 | F2 | US | Female |
| Theo | `supertonic2-en` | 7 | M3 | US | Male |
| Owen | `supertonic2-en` | 5 | M1 | US | Male |
| Harper | `kokoro-en-v1_0` | 3 | af_heart | US | Female |
| Ruby | `kokoro-en-v1_0` | 2 | af_bella | US | Female |
| Miles | `kokoro-en-v1_0` | 16 | am_michael | US | Male |
| Grant | `kokoro-en-v1_0` | 14 | am_fenrir | US | Male |
| Imogen | `kokoro-en-v1_0` | 22 | bf_isabella | UK | Female |
| Emma | `kokoro-en-v1_0` | 21 | bf_emma | UK | Female |
| George | `kokoro-en-v1_0` | 26 | bm_george | UK | Male |
| Oliver | `kokoro-en-v1_0` | 25 | bm_fable | UK | Male |

### Default voice

Use **Nora** (`supertonic2-en`, speaker id 2) as the default neural voice:

- It is fast enough to speak a prompt as soon as it is needed (see
  [Speed](#speed)).
- It reads raw text, so it handles street names that are not in any lexicon,
  such as Sepulveda and Figueroa.
- It had the lowest word error rate of the fast voices in our tests.

Offer the Kokoro voices to users who want a UK accent or a more natural voice.
They need text normalization and are slower, so pre-render their prompts (see
[Kokoro text rules](#kokoro-text-rules)).

Before you ship Supertonic, complete the terms update in
[Supertonic 2 license](#supertonic-2-openrail-m).

## Licenses

All shipped files allow commercial use. Show each pack's `NOTICE` in the app's
licenses screen once the pack is downloaded.

### Supertonic 2: OpenRAIL-M

The model is © Supertone Inc. under the
[BigScience OpenRAIL-M license](https://huggingface.co/Supertone/supertonic-2/blob/main/LICENSE).
Commercial use is allowed. The license has these conditions:

- **Terms (paragraph 4a).** The use restrictions in Attachment A must be an
  enforceable provision of the terms that govern the app, and users must be
  told that the model is subject to them. Add the Attachment A list, or a link
  to it, to the app's terms of use before release.
- **Disclosure (Attachment A, item e).** Generated content must not be placed
  in a context without disclosing that it is machine generated. Turn-by-turn
  speech in a navigation app is plainly synthetic, but the voice picker should
  still label these voices as computer generated.
- **Notices (paragraph 4b to 4d).** Ship `LICENSE` and keep the notices. Three
  ONNX files are the int8 build from the sherpa-onnx project; the vocoder is
  Supertone's float32 vocoder converted to float16. `NOTICE` states those
  changes.

Supertone does not publish the training data for Supertonic 2.

### Kokoro v1.0: Apache-2.0

The Kokoro-82M weights by hexgrad are Apache-2.0. The pack's model is a
derivative: it was re-quantized and trimmed to the English speakers, and
`NOTICE` states both changes. `NOTICE` also carries:

- The attributions the Kokoro model card lists for CC BY training audio.
- The misaki lexicon credit (Apache-2.0).
- The CMU Pronouncing Dictionary license, which must be reproduced. The
  `*-extra.txt` lexicons are generated from it.

The Kokoro model card describes its training audio as permissive,
public-domain, or synthetic audio from other TTS systems.

### GPL and espeak-ng

sherpa-onnx 2.0.0 removed espeak-ng and piper-phonemize. No GPL code is linked
into either app. The packs do not use the GPL `espeak-ng-data` directory.

Two groups of models were left out because of license terms:

- **Most Piper voices.** Most English Piper voices are fine-tuned from the
  `lessac` voice, whose source data is licensed for non-commercial use only.
  Some others, such as `ryan`, are CC BY-NC-SA.
- **Models that need espeak IPA input.** Piper, Matcha, and Kitten models
  expect espeak-ng phonemes. The `lexicon-en-us.txt` file that sherpa-onnx
  publishes for them is built partly from espeak-ng's `en_list`, which is
  GPL-3.0. Reading a GPL data file does not make the app GPL, but shipping that
  file means shipping it under GPL-3.0 terms, with its license and source. The
  catalog avoids it.

## How the apps use a pack

### Download

1. Read `shared/voices.json`, bundled with the app.
2. Download each entry in the pack's `files` list into the app's support
   directory:
   - iOS: `Application Support/voices/<pack id>/`. Set
     `isExcludedFromBackup` on the folder.
   - Android: `context.noBackupFilesDir/voices/<pack id>/`.
3. Write each file to `<name>.part` first. GitHub release assets support HTTP
   range requests, so a paused or interrupted download resumes with
   `Range: bytes=<bytes on disk>-`.
4. When a file is complete, check its byte size and sha256 against the
   catalog. On a mismatch, delete the `.part` file and start that file again.
   Rename it to its final name only after it passes.
5. When all files pass, write a `pack.ok` marker and delete any file in the
   folder that the catalog does not name. The app treats a pack as installed
   only when the marker exists.

Use the per-file assets rather than the zip. Neither platform needs an unzip
step, and a failure costs one file, not the whole pack. The `archive` entry
exists for desktop tools and manual installs.

Other rules:

- **Cancel.** Cancel the request and keep the `.part` files so the user can
  resume. If the user removes the pack, delete them.
- **Delete.** Remove the pack directory. If the active voice was in it, switch
  to the system voice.
- **Space.** Check free space for `download_size` plus 10% before starting.
- **Network.** Use Wi-Fi by default, and ask before using cellular data.
- **Update.** At launch, a pack that has the marker but no longer matches the
  catalog, because a new app version ships new files or a file was damaged,
  loses the marker, deletes the files the catalog no longer names, and
  downloads only the missing files, on Wi-Fi unless the user allowed cellular
  data for that pack before. The chosen voice stays chosen, and the system
  voice speaks until the pack is complete again.

### Synthesis

- Create one `OfflineTts` per pack, or per accent for Kokoro, and keep it for
  the drive. Loading takes 0.3 s for Supertonic and 0.8 s for Kokoro on an M1
  Max, so do not reload it for every prompt.
- Use `numThreads = 2` to leave cores for the map and routing. On the emulator,
  4 threads was about 1.5 times faster than 2.
- Supertonic: set `numSteps = 5` and `extra = ["lang": "en"]`, and pass the
  speaker id as `sid`. Pass the raw prompt text.
- Kokoro: build one `OfflineTts` for US voices with
  `lexicon = "lexicon-us-en.txt,lexicon-us-en-extra.txt"` and one for UK voices
  with the `gb` pair. Normalize the text first.
- Run synthesis off the main thread, then play the samples through the same
  audio session the system voice uses, so ducking and Bluetooth routing still
  work.
- Clean every clip before it plays, as
  [`scripts/voices/clean.py`](../scripts/voices/clean.py) does: a 30 Hz
  high-pass, a gain that brings speech to -20 dBFS RMS (at most 4 times and
  never past a 0.95 peak), and 5 ms fades at both ends. Kokoro's output sits on
  a DC offset of about 0.025 in every build, float32 included, which clicks
  where a clip starts and stops. The gain keeps every voice about as loud as
  the next.

### Fallback to system voices

Fall back to the system voice (`AVSpeechSynthesizer` on iOS, `TextToSpeech` on
Android) in these cases:

- The pack is not installed, or a file fails verification at load.
- `OfflineTts` creation throws.
- Synthesis returns no samples, returns non-finite samples, or does not finish
  within one second for a time-critical prompt.
- The voice is Kokoro and the normalized text still has a word in neither
  lexicon. Kokoro skips such words without any sound.

### Kokoro text rules

Kokoro reads words through its lexicons only. It has no rules for numbers,
abbreviations, or unknown words. Before synthesis, the app must:

- Expand route numbers the way drivers say them: `US 101` is "U S one oh one",
  `I-80` is "I eighty", and `CA 17` is "C A seventeen".
- Expand street and unit abbreviations, such as `St`, `Ave`, `Blvd`, `Rd`, `Dr`,
  `N`, `S`, `E`, `W`, `mph`, `mi`, `km`, and `ft`.
- Spell out all other numbers as words.

The reference is [`scripts/voices/norm.py`](../scripts/voices/norm.py). Port it
to Swift and Kotlin and test against its output. Do not apply these rules to
Supertonic: it reads digits well, and in our tests it misread "one oh one".

Kokoro's speed on phones is near real time (see [Speed](#speed)), so render
each upcoming instruction while the previous one plays. Render the next
maneuver as soon as the route step changes, and cache the audio by text.

## Speed

We timed the sentence "In half a mile, turn right onto Main Street. Police
reported ahead." with sherpa-onnx 2.0.0 on the CPU. The table shows the time
to first audio (TTFA) and the real-time factor (RTF), which is synthesis time
divided by audio length. Lower is better. Neither engine streams, so TTFA is
about the time for the whole sentence.

| Device | Threads | Supertonic 2 TTFA | Supertonic 2 RTF | Kokoro TTFA | Kokoro RTF |
|---|---|---|---|---|---|
| MacBook, M1 Max | 1 | 0.50 s | 0.10 | 2.18 s | 0.95 |
| MacBook, M1 Max | 2 | 0.29 s | 0.06 | 1.85 s | 0.82 |
| Windows, i9-13900KS | 2 | 0.51 s | 0.10 | 4.19 s | 1.83 |
| Android emulator, x86_64 | 2 | 1.0 to 1.4 s | 0.20 to 0.29 | 8.8 to 10.7 s | 2.3 to 2.8 |
| Android emulator, x86_64 | 4 | 0.6 to 0.7 s | 0.13 | 6.5 s | 1.72 |

The x86 numbers are pessimistic for int8 models. ONNX Runtime's int8
convolutions are slow on x86, and the emulator adds overhead.

Estimates for phones at 2 threads:

| Phone | Supertonic 2 | Kokoro |
|---|---|---|
| Recent iPhone (A16 or later) | 0.4 to 0.8 s, RTF 0.1 to 0.2 | 2 to 4 s, RTF 1 to 1.5 |
| Mid-range Android (2022 or later) | 0.8 to 1.5 s, RTF 0.2 to 0.4 | 4 to 8 s, RTF 2 to 3 |

### Quality checks

- **Intelligibility.** We synthesized 12 driving prompts and transcribed them
  with an ASR model. Word error rates were 3.1% for Nora, Theo, Harper,
  George, and Oliver; 4.1 to 7.2% for Ruby, Miles, Grant, Clara, and Imogen;
  9.3% for Owen; and 10.3% for Emma. Kokoro was scored on normalized text and
  Supertonic on raw text.
- **Stability.** The stock sherpa-onnx Kokoro int8 model returns NaN audio on
  ARM (k2-fsa/sherpa-onnx#4086): 124 of 140 short prompts broke on an M1 Max.
  The pack's re-quantized model and Supertonic 2 broke on none.
- **Spectrum.** We rendered 5 driving prompts in all 12 voices with each
  candidate build and compared spectrograms and long-term spectra against the
  float32 models. "Noise floor" is the median level in the quietest tenth of
  frames during speech; lower is cleaner.

  | Build | Size of the changed file | Noise floor | Steady tones |
  |---|---|---|---|
  | Kokoro float32 (reference) | 326 MB | -66.4 dB | none |
  | Kokoro int8, first pack build | 114 MB | about -63 dB | 4.8 and 9.6 kHz in 8 of 8 voices |
  | Kokoro int8 from sherpa-onnx | 114 MB | about -63 dB | 4.8 and 9.6 kHz |
  | Kokoro int8, per-channel | 115 MB | -62.3 dB | 4.8 and 9.6 kHz in 8 of 8 voices |
  | **Kokoro int8, generator in float32** | 157 MB | -66.3 dB | none |
  | Supertonic float32 vocoder (reference) | 101 MB | -73.3 dB | none |
  | Supertonic int8 vocoder, first pack build | 26 MB | about -66 dB | none |
  | **Supertonic float16 vocoder** | 51 MB | -73.5 dB | none |

  The Kokoro tones sit at a fifth and two fifths of the 24 kHz sample rate, 16
  to 23 dB above the speech around them and in nearly every frame. They come
  from quantizing the decoder's generator, the vocoder inside Kokoro. The
  Supertonic int8 vocoder raised the broadband noise under speech by 5 to 9
  dB, heard as hiss and a rough, recorded sound. Quantizing Supertonic's text
  encoder, duration predictor, and vector estimator made no measurable
  difference, so they stay int8.

  The new builds are also faster. At 2 threads on an M1 Max, Kokoro's time to
  first audio went from 3.25 s to 1.91 s (RTF 0.86 to 0.50), because ARM runs
  float32 convolutions faster than int8 ones. Supertonic stayed at RTF 0.07 to
  0.08. Neither broke on any of 140 short prompts.
- **Previews.** The first preview clips were 48 kbit/s AAC, which cut
  Supertonic at 16 kHz. The clips are now 96 kbit/s for 44.1 kHz voices and 64
  kbit/s for 24 kHz voices, the most the encoder takes at that rate.

## Integration

Both apps use **sherpa-onnx 2.0.0**.

### iOS

Add the Swift package `https://github.com/k2-fsa/sherpa-onnx`, exact version
`2.0.0`, product `sherpa-onnx`. It is a static xcframework that requires iOS 15
and pulls in `csukuangfj/onnxruntime-libs` 1.28.2. The SwiftPM checksum for
`sherpa-onnx-v2.0.0-ios-static.xcframework.zip` is
`95550cc9e2d9699eccbc41d6d7462fb83cdfc12dd070d937533f8d0383a38286`.

```swift
import SherpaOnnx

func makeSupertonic(dir: URL) -> SherpaOnnxOfflineTtsWrapper {
  func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
  let supertonic = sherpaOnnxOfflineTtsSupertonicModelConfig(
    durationPredictor: path("duration_predictor.int8.onnx"),
    textEncoder: path("text_encoder.int8.onnx"),
    vectorEstimator: path("vector_estimator.int8.onnx"),
    vocoder: path("vocoder.fp16.onnx"),
    ttsJson: path("tts.json"),
    unicodeIndexer: path("unicode_indexer.bin"),
    voiceStyle: path("voice.bin"))
  let model = sherpaOnnxOfflineTtsModelConfig(numThreads: 2, supertonic: supertonic)
  var config = sherpaOnnxOfflineTtsConfig(model: model)
  return SherpaOnnxOfflineTtsWrapper(config: &config)
}

let tts = makeSupertonic(dir: packDir)
let gen = SherpaOnnxGenerationConfigSwift(sid: 2, numSteps: 5, extra: ["lang": "en"])
let audio = tts.generateWithConfig(text: prompt, config: gen, callback: nil, arg: nil)
// audio.samples is [Float] at audio.sampleRate. Play it with AVAudioPlayerNode.
```

For Kokoro, build the model config with
`sherpaOnnxOfflineTtsKokoroModelConfig(model:voices:tokens:lexicon:)`, pass it
as `kokoro:`, and use `SherpaOnnxGenerationConfigSwift(sid:)`.

#### How the iOS app does it

- **Gate.** `VoiceCatalog.supertonicCleared` is `false` until the terms
  update in [Supertonic 2: OpenRAIL-M](#supertonic-2-openrail-m) ships. While
  it is `false`, the Supertonic pack is left out of the Voice page, out of
  Automatic, and out of the licenses page, so Kokoro is the only pack offered.
- **Files.** `VoicePacks` (`VoiceDownloads.swift`) downloads each per-file
  asset on a background `URLSession`. A cancelled or failed file keeps its
  resume data, or its `.part` file for a `Range` request. Each finished file is
  checked against its size and sha256 before it is renamed. Sizes are checked
  again at launch and before the engine loads; a file that fails loses the
  `pack.ok` marker and is downloaded again.
- **Automatic.** With a pack installed, Automatic uses that pack's default
  voice (Harper while Supertonic is gated). Otherwise it uses the best system
  voice, as before.
- **Render ahead.** Kokoro is too slow to speak on demand, so `NeuralVoices`
  renders ahead: every spoken instruction when a route starts (the first three
  while the route choices are on screen), and each road alert's sentences when
  the alert first becomes known. Jobs run one at a time, soonest first, on a
  utility queue with 2 threads. Audio is cached by voice, speed, and words.
- **Speak.** `NeuralSpeaker` plays cached audio with `AVAudioPlayer`, in queue
  order with every other sentence, and takes the same audio focus as the system
  voice (`SpeechFocus`). A sentence whose audio is not ready waits at most
  300 ms for a render in progress; otherwise the system voice says it. A
  missing pack, a model that fails to load, failed or non-finite synthesis, and
  a word in neither lexicon all fall back the same way, and each is noted in
  the drive log.
- **Speed and pitch.** The speed slider maps to the engine's `speed`. Pitch
  applies to system voices only, so the slider is disabled for neural voices.
- **Memory.** The engine is kept loaded while a trip or a drive runs. It is
  freed 30 seconds after the last sentence otherwise, in the background with no
  trip, and on a memory warning.

### Android

sherpa-onnx 2.0.0 is not on Maven Central, and the JitPack build of 2.0.0
failed. The last JitPack build, 1.13.8, still links espeak-ng, so do not use
it. Vendor the AAR from the sherpa-onnx release instead:

- File: `sherpa-onnx-2.0.0.aar`
- URL: `https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.0/sherpa-onnx-2.0.0.aar`
- Size: 49,236,482 bytes
- sha256: `f0f8716982d27cb4ce695e3934018b1342d9d3d6fdb6ef1f1658fe8bad50b4fc`

The app does not commit the AAR. `android/app/build.gradle.kts` downloads it
into `android/app/libs/` (gitignored) on the first Gradle run, checks the
sha256 on every configuration, and stops the build on a mismatch. CI downloads
it the same way. The build also drops `libsherpa-onnx-c-api.so` and
`libsherpa-onnx-cxx-api.so`: the Kotlin API loads only `libsherpa-onnx-jni.so`
and `libonnxruntime.so`. R8 needs `-keep class com.k2fsa.sherpa.onnx.** { *; }`
because the native code reads the config classes' fields by name.

The equivalent setup with the file in place:

```kotlin
android {
  defaultConfig {
    ndk { abiFilters += listOf("arm64-v8a", "x86_64") } // x86_64 for the emulator
  }
}
dependencies {
  implementation(files("libs/sherpa-onnx-2.0.0.aar"))
}
```

The ABI filter drops the 32-bit libraries from the APK.

```kotlin
import com.k2fsa.sherpa.onnx.*

fun makeSupertonic(dir: File): OfflineTts {
  fun path(name: String) = File(dir, name).absolutePath
  val model = OfflineTtsModelConfig(
    supertonic = OfflineTtsSupertonicModelConfig(
      durationPredictor = path("duration_predictor.int8.onnx"),
      textEncoder = path("text_encoder.int8.onnx"),
      vectorEstimator = path("vector_estimator.int8.onnx"),
      vocoder = path("vocoder.fp16.onnx"),
      ttsJson = path("tts.json"),
      unicodeIndexer = path("unicode_indexer.bin"),
      voiceStyle = path("voice.bin"),
    ),
    numThreads = 2,
  )
  return OfflineTts(config = OfflineTtsConfig(model = model)) // no AssetManager: files on disk
}

val audio = tts.generateWithConfig(prompt, GenerationConfig(sid = 2, numSteps = 5, extra = mapOf("lang" to "en")))
// audio.samples is a FloatArray at audio.sampleRate. Play it with AudioTrack (ENCODING_PCM_FLOAT).
```

For Kokoro, pass
`kokoro = OfflineTtsKokoroModelConfig(model, voices, tokens, lexicon = "<us>,<us-extra>")`
and use `GenerationConfig(sid = ...)`.

## Add a voice

1. Confirm from the primary source that the weights, the training data
   license, and every runtime file allow commercial use. Reject anything
   non-commercial, unclear, or built on espeak-ng data.
2. Test it with sherpa-onnx 2.0.0: speed on an ARM device, stability over many
   short prompts, and intelligibility of driving prompts.
3. If the voice is in a new pack, build a directory with only the runtime files
   plus `LICENSE` and a `NOTICE` that lists the source, the license, and every
   change you made.
4. Publish the files on a new release, such as `voices-v2`, or under new
   asset names on the current one. Do not replace an existing asset, because
   installed apps check the hashes.
5. Add the pack or voice to `shared/voices.json` with the sha256 and size of
   every file.

To add a speaker that is already in a pack, add a `voices` entry. No download
changes.

### Build scripts

- [`scripts/voices/requant.py`](../scripts/voices/requant.py) builds
  `model.mixed.onnx` from the float32 `kokoro-multi-lang-v1_0` model: int8
  except the decoder's generator, which stays float32, and only the 28 English
  speakers.
- [`scripts/voices/vocoder_fp16.py`](../scripts/voices/vocoder_fp16.py)
  converts Supertone's float32 vocoder to `vocoder.fp16.onnx`.
- [`scripts/voices/previews.py`](../scripts/voices/previews.py) renders the
  preview clips from the packs and prints their sizes and hashes for the
  catalog. It needs macOS for `afconvert`.
- [`scripts/voices/clean.py`](../scripts/voices/clean.py) is the reference for
  the clean-up every clip gets before it plays.
- [`scripts/voices/cmu2misaki.py`](../scripts/voices/cmu2misaki.py) builds the
  `*-extra.txt` lexicons from CMUdict.
- [`scripts/voices/norm.py`](../scripts/voices/norm.py) is the reference text
  normalizer for Kokoro.
