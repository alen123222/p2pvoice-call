# ProGuard / R8 混淆与瘦身规则

# ----------------------------------------------------
# Flutter 引擎与插件
# ----------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.**

# ----------------------------------------------------
# WebRTC 核心与 flutter_webrtc 插件
# ----------------------------------------------------
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**

# ----------------------------------------------------
# 本工程应用原生类、组件与模型类
# ----------------------------------------------------
-keep class com.p2p.call.client.** { *; }
-keepclassmembers class com.p2p.call.client.** { *; }

# ----------------------------------------------------
# 原生反射、注解与核心属性保留
# ----------------------------------------------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Exceptions
-keepattributes SourceFile,LineNumberTable

# 保护 JNI / 本地 Native 方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 序列化与 Parcelable 保护
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ----------------------------------------------------
# 常用第三方与系统库警告忽略
# ----------------------------------------------------
-dontwarn androidx.**
-dontwarn javax.annotation.**
