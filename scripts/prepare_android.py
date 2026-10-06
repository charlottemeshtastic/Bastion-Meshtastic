# Run after flutter create to add BLE permissions and app label.
from pathlib import Path
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
if 'android.permission.INTERNET' not in s:
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET" />')
if 'android.permission.BLUETOOTH_SCAN' not in s:
    permissions = '''    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
'''
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'+permissions)
s=s.replace('android:label="bastion_meshtastic"', 'android:label="Bastion Meshtastic"')
p.write_text(s)
print('Prepared Android manifest')

# Immediate Android alert notifications and explicit connected-device service.
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
if 'android.permission.POST_NOTIFICATIONS' not in s:
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                  '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />')
p.write_text(s)

p = Path('android/app/build.gradle.kts')
s = p.read_text()
s = s.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
s = s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
s = s.replace('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17')
if 'isCoreLibraryDesugaringEnabled = true' not in s:
    s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
if 'desugar_jdk_libs' not in s:
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
p.write_text(s)

# Preserve the dedicated monochrome notification icon in release builds.
resources = Path('android/app/src/main/res')
(resources / 'drawable').mkdir(parents=True, exist_ok=True)
(resources / 'drawable/ic_stat_bastion.xml').write_text('''<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M2,20L8,9L12,15L16,6L22,20Z" />
    <path android:fillColor="#FFFFFFFF" android:pathData="M15,2L17,2L17,5L15,5Z" />
</vector>\n''')
(resources / 'raw').mkdir(parents=True, exist_ok=True)
(resources / 'raw/keep.xml').write_text('''<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_bastion" />\n''')
print('Prepared Android notifications, SDK and desugaring')

# Reproducible Android host, service, offline import and foreground-only GPS.
import shutil
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
for permission in ['FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_CONNECTED_DEVICE', 'WAKE_LOCK', 'ACCESS_COARSE_LOCATION']:
    name = 'android.permission.' + permission
    if name not in s:
        s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="' + name + '" />')
s = s.replace('android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"',
    'android:name="android.permission.ACCESS_FINE_LOCATION"')
if '.BastionConnectionService' not in s:
    s = s.replace('</application>', '<service android:name=".BastionConnectionService" android:exported="false" android:foregroundServiceType="connectedDevice" android:stopWithTask="true" />\n    </application>')
p.write_text(s)
native = Path('android/app/src/main/kotlin/app/bastion/bastion_meshtastic')
native.mkdir(parents=True, exist_ok=True)
for source in Path('android_support').glob('*.kt'):
    shutil.copyfile(source, native / source.name)
print('Prepared explicit screen-off service, map importer and location capture')
