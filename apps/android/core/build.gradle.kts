// :core —— 协议层（ADR-066）。纯 JVM 模块，不依赖 Android SDK：契约测试在 Windows 本机即可跑。
// 本模块不得引入 Android 依赖；只有它能请求上游（ADR-064）。
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    `java-library`
}

kotlin { jvmToolchain(21) }

dependencies {
    // 契约是 JSON；网络请求用 JDK 自带的 java.net.http.HttpClient（不引入 OkHttp）
    api(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test"))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    // Gradle 测试的缺省工作目录即本模块根（apps/android/core/），契约在 ../../../packages/contract
    systemProperty("pterosaur.contract", file("../../../packages/contract").canonicalPath)
}


// 真实上游体检（手动运行，需联网）：`gradle :core:liveCheck`
// 放在独立 task 里而不是 test——它验证「签名是否被上游接受」，与 CI 的离线测试互补。
tasks.register<JavaExec>("liveCheck") {
    group = "verification"
    description = "对真实网易云上游发匿名请求，验证签名与请求形态（需联网）"
    classpath = sourceSets["main"].runtimeClasspath
    mainClass.set("im.xrl.pterosaur.core.cli.LiveCheckKt")
}
