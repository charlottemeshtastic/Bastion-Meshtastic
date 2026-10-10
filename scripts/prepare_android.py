# Run after flutter create to add BLE permissions and app label.
from pathlib import Path
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
if 'android.permission.BLUETOOTH_SCAN' not in s:
    permissions = '''    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.INTERNET" />
'''
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'+permissions)
s=s.replace('android:label="bastion"', 'android:label="Bastion"')
# Foreground service that keeps the BLE link alive in the background.
if 'flutter_foreground_task.service.ForegroundService' not in s:
    service = '''        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="connectedDevice"
            android:stopWithTask="true"
            android:exported="false" />
    </application>'''
    s=s.replace('    </application>', service, 1)
p.write_text(s)

# flutter_local_notifications needs core library desugaring.
g=Path('android/app/build.gradle.kts')
gradle=g.read_text()
if 'isCoreLibraryDesugaringEnabled' not in gradle:
    gradle=gradle.replace('    compileOptions {\n', '    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n', 1)
    gradle=gradle.replace('\nflutter {', '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n\nflutter {', 1)
    if 'isCoreLibraryDesugaringEnabled' not in gradle or 'desugar_jdk_libs' not in gradle:
        raise SystemExit('Could not enable desugaring in build.gradle.kts')
    g.write_text(gradle)

# Keep the launcher icon used for notifications through R8 resource shrinking.
keep=Path('android/app/src/main/res/raw/keep.xml')
keep.parent.mkdir(parents=True, exist_ok=True)
keep.write_text('<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources xmlns:tools="http://schemas.android.com/tools"\n'
    '    tools:keep="@mipmap/ic_launcher" />\n')
print('Prepared Android manifest and Gradle')
