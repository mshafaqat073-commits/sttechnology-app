import java.util.Properties
import java.io.FileInputStream

// Loads signing details from the key.properties file — NEVER commit this
// file to git/version control, it contains your keystore passwords.
// Create android/key.properties with:
//   storePassword=<your keystore password>
//   keyPassword=<your key password>
//   keyAlias=<your key alias>
//   storeFile=<path to your .jks file>
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
   id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.sttechnology.schoolmanagement"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
         isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.sttechnology.schoolmanagement"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // FAIL FAST instead of silently signing with the debug key.
            // The previous fallback to the debug signingConfig here was the
            // root cause of "App not installed as package conflicts with an
            // existing package" errors on update: any release APK built
            // without key.properties present got silently signed with a
            // machine-specific debug key instead of the real release key,
            // producing a signature mismatch against previously installed
            // (correctly signed) versions. Failing the build here forces
            // key.properties to be present for every release build, so a
            // wrongly-signed APK can never be produced or published by
            // accident.
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Release build aborted: android/key.properties not found. " +
                    "A release build MUST be signed with the real release " +
                    "keystore — building without key.properties would silently " +
                    "fall back to the debug key and break updates for users " +
                    "already on a properly signed version. Create " +
                    "android/key.properties (see comment at the top of this " +
                    "file for the required fields) before building a release APK."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.15.0"))
    implementation("com.google.firebase:firebase-firestore")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
