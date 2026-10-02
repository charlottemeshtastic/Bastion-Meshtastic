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
