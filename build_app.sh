
#!/data/data/com.termux/files/usr/bin/bash
set -e

# ---------- CONFIG ----------
APP_NAME="MyNDKApp"

P_DIR="$(pwd)"

ANDROID_JAR="$P_DIR/android.jar"

KEYSTORE="$P_DIR/mykey.keystore"
KEY_ALIAS="myalias"
KEY_PASS="123456"
MIN_SDK=24
TARGET_SDK=34

SRC_DIR="$P_DIR/src/main"
CPP_DIR="$SRC_DIR/cpp"
RES_DIR="$SRC_DIR/res"
BUILD_DIR="$P_DIR/build"

# الأدوات (يُفترض أنها متوفرة في PATH)
ZIPALIGN="zipalign"
APKSIGNER="apksigner"
D8_TOOL="d8"
AAPT2="aapt2"
KEYTOOL="keytool"
CLANG="clang++"

# مجلدات البناء
GEN_JAVA_SRC_DIR="$BUILD_DIR/gen_java_src"
BUILD_CLASSES_DIR="$BUILD_DIR/classes"
DEX_FILE="$BUILD_DIR/classes.dex"
APK_UNSIGNED="$BUILD_DIR/${APP_NAME}-unsigned.apk"
APK_UNSIGNED_ALIGNED="$BUILD_DIR/${APP_NAME}-unsigned-aligned.apk"
APK_SIGNED="$BUILD_DIR/${APP_NAME}-signed.apk"

# ---------- [تنظيف المجلدات السابقة] ----------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/lib/arm64-v8a" "$GEN_JAVA_SRC_DIR" "$BUILD_CLASSES_DIR"

echo "[*] Compiling native code..."
"$CLANG" -shared -fPIC \
  --target=aarch64-linux-android \
  "$CPP_DIR/native-lib.cpp" \
  "$CPP_DIR/android_native_app_glue.c" \
  -o "$BUILD_DIR/lib/arm64-v8a/libnative-lib.so" \
  -Wl,--disable-new-dtags -llog -landroid -lEGL -lGLESv1_CM -lGLESv2 -lc++_shared
  # /system/lib64/libEGL.so /system/lib64/libGLESv1_CM.so  /system/lib64/libGLESv2.so 

# ---------- [إضافة المكتبات النظامية مباشرة إلى APK] ----------
echo "[*] Copying system libraries directly to APK lib folder..."
LIBCXX_SHARED="$($CLANG --target=aarch64-linux-android -print-file-name=libc++_shared.so)"
cp "$LIBCXX_SHARED" "$BUILD_DIR/lib/arm64-v8a/"


echo "[*] Compiling resources and generating R.java..."
"$AAPT2" compile --dir "$RES_DIR" -o "$BUILD_DIR"
"$AAPT2" link \
  -o "$APK_UNSIGNED" \
  -I "$ANDROID_JAR" \
  --manifest "$SRC_DIR/AndroidManifest.xml" \
  --java "$GEN_JAVA_SRC_DIR" \
  --min-sdk-version $MIN_SDK \
  --target-sdk-version $TARGET_SDK \
  "$BUILD_DIR"/*.flat

echo "[*] Compiling R.java and creating DEX file..."
find "$GEN_JAVA_SRC_DIR" -name "*.java" > "$BUILD_DIR/java_sources.txt"
javac -d "$BUILD_CLASSES_DIR" -classpath "$ANDROID_JAR" --release 8 @"$BUILD_DIR/java_sources.txt"
CLASS_FILES=$(find "$BUILD_CLASSES_DIR" -name "*.class")
"$D8_TOOL" --output "$BUILD_DIR" --lib "$ANDROID_JAR" --min-api $MIN_SDK $CLASS_FILES

echo "[*] Adding classes.dex and native libs to the APK..."
zip -uj "$APK_UNSIGNED" "$DEX_FILE"
(cd "$BUILD_DIR" && zip -ur "$APK_UNSIGNED" "lib")

# ---------- [محاذاة الـ APK] ----------
echo "[*] Aligning the APK..."
"$ZIPALIGN" -v 4 "$APK_UNSIGNED" "$APK_UNSIGNED_ALIGNED"

# ---------- [توقيع الـ APK] ----------
echo "[*] Signing the aligned APK..."
if [ ! -f "$KEYSTORE" ]; then
  echo "[*] Generating keystore..."
  "$KEYTOOL" -genkeypair -v -keystore "$KEYSTORE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Unknown, OU=Unknown, O=Unknown, L=Unknown, ST=Unknown, C=Unknown" \
    -storepass "$KEY_PASS" -keypass "$KEY_PASS"
fi

"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass pass:"$KEY_PASS" \
  --key-pass pass:"$KEY_PASS" \
  --out "$APK_SIGNED" \
  "$APK_UNSIGNED_ALIGNED"

# ---------- تنظيف الملفات الوسيطة ----------
rm -f "$APK_UNSIGNED" "$APK_UNSIGNED_ALIGNED"

echo "[✔] Build finished successfully!"
echo "[→] Final APK: $APK_SIGNED"

