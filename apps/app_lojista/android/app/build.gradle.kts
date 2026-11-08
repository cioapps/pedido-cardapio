import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (push): só ativa quando o android/app/google-services.json existir.
// Sem ele o app funciona normalmente, apenas sem aviso com o app fechado.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Chave de upload da Play Store (android/key.properties, fora do Git).
// Sem o arquivo, o release assina com a chave de debug (só para testes).
val propriedadesChave = Properties()
val arquivoChave = rootProject.file("key.properties")
if (arquivoChave.exists()) {
    propriedadesChave.load(FileInputStream(arquivoChave))
}

android {
    namespace = "com.cioapps.app_lojista"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // exigido pelo flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identidade do app na Play Store: NUNCA mude (senão vira outro app)
        applicationId = "com.cioapps.app_lojista"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (arquivoChave.exists()) {
                keyAlias = propriedadesChave["keyAlias"] as String
                keyPassword = propriedadesChave["keyPassword"] as String
                storeFile = file(propriedadesChave["storeFile"] as String)
                storePassword = propriedadesChave["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (arquivoChave.exists()) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
