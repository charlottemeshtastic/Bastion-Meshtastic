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
'''
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'+permissions)
s=s.replace('android:label="bastion_meshtastic"', 'android:label="Bastion Meshtastic"')
p.write_text(s)
print('Prepared Android manifest')

# Universal BLE 2.x uses AGP 9's built-in Kotlin DSL on Android.
# Flutter's generated project currently disables it, which leaves the plugin
# without a Kotlin extension during Gradle configuration.
gradle_properties = Path('android/gradle.properties')
g = gradle_properties.read_text()
g = g.replace('android.builtInKotlin=false', 'android.builtInKotlin=true')
if 'android.builtInKotlin=' not in g:
    g += '\\nandroid.builtInKotlin=true\\n'
gradle_properties.write_text(g)
print('Enabled AGP built-in Kotlin for BLE plugin compatibility')
