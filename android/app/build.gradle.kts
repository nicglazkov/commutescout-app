import java.net.URI
import java.security.MessageDigest
import java.util.Properties

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeCompiler)
    alias(libs.plugins.kotlinSerialization)
    alias(libs.plugins.googleServices) apply false
}

// google-services.json is machine-local (never committed); builds without
// it still work, with sign-in disabled.
if (file("google-services.json").exists()) {
    apply(plugin = libs.plugins.googleServices.get().pluginId)
}

// Release signing comes from keystore.properties (never committed):
// storeFile, storePassword, keyAlias, keyPassword.
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// On-device neural voices run on sherpa-onnx 2.0.0. It is not on Maven
// Central and its JitPack build is broken, so the AAR comes from the
// sherpa-onnx GitHub release. It is 49 MB, too big to keep in git: Gradle
// downloads it once into app/libs (gitignored) and checks its sha256
// before every build. A file that fails the check is never used.
val sherpaOnnxAar: File = file("libs/sherpa-onnx-2.0.0.aar")
run {
    val url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.0/sherpa-onnx-2.0.0.aar"
    val sha256 = "f0f8716982d27cb4ce695e3934018b1342d9d3d6fdb6ef1f1658fe8bad50b4fc"
    fun hashOf(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) { val n = input.read(buf); if (n < 0) break; md.update(buf, 0, n) }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
    if (sherpaOnnxAar.exists() && hashOf(sherpaOnnxAar) == sha256) return@run
    sherpaOnnxAar.parentFile.mkdirs()
    val part = File(sherpaOnnxAar.path + ".part")
    logger.lifecycle("Downloading sherpa-onnx 2.0.0 AAR from the k2-fsa/sherpa-onnx release")
    try {
        URI(url).toURL().openStream().use { input -> part.outputStream().use { input.copyTo(it) } }
    } catch (e: Exception) {
        part.delete()
        throw GradleException("Could not download $url. Put the file at $sherpaOnnxAar (sha256 $sha256).", e)
    }
    val got = hashOf(part)
    if (got != sha256) {
        part.delete()
        throw GradleException("sherpa-onnx AAR checksum mismatch: expected $sha256, got $got")
    }
    sherpaOnnxAar.delete()
    if (!part.renameTo(sherpaOnnxAar)) throw GradleException("Could not move $part to $sherpaOnnxAar")
}

/** Copies the shared voice catalog into the app's assets, so the app never fetches it. */
abstract class CopyVoiceCatalog : DefaultTask() {
    @get:InputFile abstract val catalog: RegularFileProperty
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @TaskAction fun copy() {
        val out = outputDir.get().asFile
        out.mkdirs()
        catalog.get().asFile.copyTo(File(out, "voices.json"), overwrite = true)
    }
}
val copyVoiceCatalog = tasks.register<CopyVoiceCatalog>("copyVoiceCatalog") {
    catalog.set(rootProject.file("../shared/voices.json"))
}
androidComponents {
    onVariants { variant -> variant.sources.assets?.addGeneratedSourceDirectory(copyVoiceCatalog, CopyVoiceCatalog::outputDir) }
}

android {
    namespace = "com.commutescout.drive"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.commutescout.drive"
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Each UI test in its own process: the map's native state does not
        // survive many launches in one process on the emulator.
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        targetSdk = 36
        versionCode = (project.findProperty("versionCode") as String?)?.toInt() ?: 1
        // One version for both apps: VERSION at the repo root.
        versionName = rootProject.file("../VERSION").readText().trim()
        // 64-bit only: the neural voice engine is 15 MB of native code per
        // ABI. x86_64 is for the emulator.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    signingConfigs {
        if (keystoreProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions { execution = "ANDROIDX_TEST_ORCHESTRATOR" }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
        // sherpa-onnx's Kotlin API loads only libsherpa-onnx-jni (and its
        // libonnxruntime); the C and C++ API libraries are for other bindings.
        jniLibs.excludes += listOf("**/libsherpa-onnx-c-api.so", "**/libsherpa-onnx-cxx-api.so")
    }
}

dependencies {
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.ferrostar.core)
    implementation(libs.ferrostar.ui.compose)
    implementation(libs.ferrostar.ui.maplibre)
    implementation(libs.ferrostar.google.play.services)
    // Ferrostar's generated route converter extends JNA types. JNA is
    // already on the runtime classpath through Ferrostar; declaring it
    // at the same version lets the compiler see it too, for the saved
    // trip (TripStore).
    compileOnly("net.java.dev.jna:jna:5.19.1@aar")
    implementation(libs.maplibre.compose)
    implementation(libs.play.services.location)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.messaging)
    implementation(libs.credentials)
    implementation(libs.credentials.play)
    implementation(libs.googleid)
    implementation(libs.androidx.security.crypto)
    // Live camera video: the agencies publish HLS.
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.exoplayer.hls)
    implementation(libs.media3.ui)
    // On-device neural voices (see the download above) and their pack downloads.
    implementation(files(sherpaOnnxAar))
    implementation(libs.androidx.work.runtime)
    // Instrumented UI tests (app/src/androidTest): every control on the emulator or a phone.
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
    androidTestUtil("androidx.test:orchestrator:1.5.1")
    testImplementation("junit:junit:4.13.2")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
