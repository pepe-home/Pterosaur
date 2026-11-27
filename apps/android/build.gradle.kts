// 根项目：只把各模块共用的插件版本集中声明（apply false），避免 :app 与 :core 各自带版本加载插件。
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
