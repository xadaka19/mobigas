plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}

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
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt is com.android.build.gradle.BaseExtension) {
                if (androidExt.namespace == null) {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifest = manifestFile.readText()
                        val pkg = Regex("""package\s*=\s*"([^"]+)"""").find(manifest)?.groupValues?.get(1)
                        if (pkg != null) androidExt.namespace = pkg
                    }
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
