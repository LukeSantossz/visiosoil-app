allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Aligns JVM target across plugin modules. Library plugins (e.g. tflite_flutter)
// leave Java at 11 while Kotlin follows the JDK (21), and the mismatch fails the
// Android build. Pin Java to 17 on those modules and Kotlin to 17 everywhere.
subprojects {
    // Registered during root configuration (before plugin subprojects evaluate),
    // so this afterEvaluate runs before AGP finalizes compileOptions and can raise
    // Java to 17. ":app" is already evaluated (evaluationDependsOn above) and is
    // skipped — it already targets 17 in its own build.gradle.kts.
    if (!state.executed) {
        afterEvaluate {
            (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
        }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
