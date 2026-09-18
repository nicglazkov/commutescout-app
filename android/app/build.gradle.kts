import java.util.Properties

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.kotlinAndroid)
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

android {
    namespace = "com.commutescout.drive"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.commutescout.drive"
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Each UI test in its own process: the map's native state does not
        // survive many launches in one process on the emulator.
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        targetSdk = 36
        versionCode = (project.findProperty("versionCode") as String?)?.toInt() ?: 1
        versionName = "0.2.5"
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
    }
}

dependencies {
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
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
    implementation(libs.maplibre.compose)
    implementation(libs.play.services.location)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.messaging)
    implementation(libs.credentials)
    implementation(libs.credentials.play)
    implementation(libs.googleid)
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
