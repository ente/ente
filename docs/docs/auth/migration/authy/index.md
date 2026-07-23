---
title: Migrating from Authy
description: Guide for importing your existing Authy 2FA tokens into Ente Auth
---

# Migrating from Authy

A guide written by Green, an ente.io lover

> [!WARNING]
>
> Authy has dropped all support for its desktop apps. It is no longer possible to export data from Authy using methods 1 and 2. You will need either an iOS device and computer (method 4) or a rooted Android phone (method 3) to follow this guide.

---

Migrating from Authy can be tiring, as you cannot export your 2FA codes through the app, meaning that you would have to reconfigure 2FA for all of your accounts for your new 2FA authenticator. However, easier ways exist to export your codes out of Authy. This guide will cover two of the most used methods for migrating from Authy to Ente Authenticator.

> [!CAUTION]
>
> Under any circumstances, do **NOT** share any JSON and TXT files generated using this guide, as they contain your **unencrypted** TOTP secrets!
>
> Also, there is **NO GUARANTEE** that these methods will export ALL of your codes. Make sure that all your accounts have been imported successfully before deleting any codes from your Authy account!

---

## Method 1: Use Neeraj's export tool

**Who should use this?** General users who want to save time by skipping the hard (and rather technical) parts of the process.<br><br>

One way to export is to [use this tool by Neeraj](https://github.com/ua741/authy-export/releases/tag/v0.0.4) to simplify the process and skip directly to importing to Ente Authenticator.

To export from Authy, download the tool for your specific OS, then type the following in your terminal:

```
./<binary-name> <path_to_export_file>
```

Assuming the filename of the binary remains unmodified and the working directory of the terminal is the location of the binary, you should type this for MacOS:

> [!NOTE]
>
> On Apple Silicon devices, Rosetta 2 may be required to run the binary.

```
./authy-export-darwin-amd64 authy_codes.txt
```

For Linux:

```
./authy-export-linux-amd64 authy_codes.txt
```

For Windows:

```
./authy-export-windows-amd64.exe authy_codes.txt
```

This will generate a text file called `authy_codes.txt`, which contains your Authy codes in Ente's plaintext export format. You can now import this to Ente Authenticator!

## Method 2: Use gboudreau's GitHub guide

**Who should use this?** Power users who have spare time on their hands and prefer a more "known and established" solution to exporting Authy codes.<br><br>

A user on GitHub (gboudreau) wrote a guide to export codes from Authy (morpheus on Discord found this and showed it to us), so we are going to be using that for the migration.

To export your data, please follow [this guide](https://gist.github.com/gboudreau/94bb0c11a6209c82418d01a59d958c93).

This will create a JSON file called `authy-to-bitwarden-export.json`, which contains your Authy codes in Bitwarden's export format. You can now import this to Ente Authenticator!

### Method 2.1: If the export worked, but the import didn't

> [!NOTE]
>
> This is intended only for users who successfully exported their codes using the guide in method 2, but could not import it to Ente Authenticator for whatever reason. If the import was successful, or you haven't tried to import the codes yet, ignore this section.
>
> If the export itself failed, try using [**method 1**](#method-1-use-neeraj-s-export-tool) instead.

Usually, you should be able to import Bitwarden exports directly into Ente Authenticator. In case this didn't work for whatever reason, I've written a program in Python that converts the JSON file into a TXT file that Ente Authenticator can use, so you can try importing using plain text import instead.

You can download my program [here](https://github.com/gweeeen/ducky/blob/main/duckys_other_stuff/authy_to_ente.py), or you can copy the program below:

```py
import json
import os

totp = []

accounts = json.load(open('authy-to-bitwarden-export.json','r',encoding='utf-8'))

for account in accounts['items']:
    totp.append(account['login']['totp']+'\n')

writer = open('auth_codes.txt','w+',encoding='utf-8')
writer.writelines(totp)
writer.close()

print('Saved to ' + os.getcwd() + '/auth_codes.txt')
```

To convert the file with this program, you will need to install [Python](https://www.python.org/downloads/) on your computer.

Before you run the program, make sure that both the Python program and the JSON file are in the same directory, otherwise this will not work!

To run the Python program, open it in your IDE and run the program, or open your terminal and type `python3 authy_to_ente.py` (MacOS/Linux, or any other OS that uses bash) or `py -3 authy_to_ente.py` (Windows). Once you run it, a new TXT file called `auth_codes.txt` will be generated. You can now import your data to Ente Authenticator!

---

You should now have a TXT file (method 1, method 2.1) or a JSON file (method 2) that countains your TOTP secrets, which can now be imported into Ente Authenticator. To import your codes, please follow one of the steps below, depending on which method you used to export your codes.

## Method 3

**Who should use this?** Power users who have spare time on their hands and who have a rooted android phone running android 6 or newer that passes Play Integrity.

This way of exporting your data will require a rooted phone.

### Exporting codes using Android OTP Extractor

This uses the tool [Android OTP Extractor](https://github.com/puddly/android-otp-extractor) from [puddly](https://github.com/puddly) on GitHub

1. Install python 3 and adb to your computer you can download binaries for it from [Google](https://developer.android.com/tools/releases/platform-tools)
2. Add adb to your path. 2.1. On windows search for "Edit the system environment variables" 2.2. Click "Environment Variables" 2.3. At the top in "User variables" click the "path" variable and then click "Edit" 2.4. Click "New" and type the path to where you extracted the Platform Tools
3. Enable USB debugging on the Android Phone 3.1. Open settings 3.2. Open "About phone" (Might say tablet depending on what device you use) (skip steps 3.2 and 3.3 if you already have developer options enabled) 3.3. Tap "Build Number" 7 or more times 3.4. Go to the main settings page 3.5. Open "System Settings" 3.6. Open "Developer options" 3.7. Enable "USB Debugging" 3.8. On your computer verify the phone is connected by running `adb devices` (You may need to tap "Allow" on the device to allow the computer to access it)
4. Install Android OTP Extractor using pip
    ```
    pip install git+https://github.com/puddly/android-otp-extractor
    ```
5. Install Authy from the playstore and login to your account
6. Run the command below to export the TOTP to QRCodes and URLS
    ```
    python -m android_otp_extractor --prepend-issuer --include authy
    ```

### Exporting codes using Aegis Authenticator

This uses the tool [Aegis Authenticator](https://getaegis.app/) from [beemdevelopment](https://github.com/beemdevelopment).

1. Install Authy and login on your rooted phone.
2. Install Aegis Authenticator from the [Google Play Store](https://play.google.com/store/apps/details?id=com.beemdevelopment.aegis).
3. In the app, click the three dots in the top right corner and click "Import & Export".
4. Click "Import from another app" and choose Authy.
5. The app will ask for root permissions, then automatically import your codes from Authy.
6. Then export the codes from Aegis Authenticator to `json` or `txt` using the "Export to file" option in the "Import & Export" menu.

## Method 4: Authy-iOS-MiTM

**Who should use this?** Technical iOS users of Authy that cannot export their tokens with methods 1 or 2 (due to those methods being patched) or method 3 (due to that method requiring a rooted Android device).

This method works by intercepting the data the Authy app receives while logging in for the first time, which contains your encrypted authenticator tokens. After the encrypted authenticator tokens are dumped, you can decrypt them using your backup password and convert them to an Ente token file.

For an up-to-date guide of how to retrieve the encrypted authenticator tokens and decrypt them, please see

- A newer, updated version of the [Authy-iOS-MiTM guide](https://github.com/AlexTech01/Authy-iOS-MiTM).
- The [original Authy-iOS-MiTM guide](https://github.com/BrenoFariasdaSilva/Authy-iOS-MiTM). To convert the `decrypted_tokens.json` file from that guide into a format Ente Authenticator can recognize, use [this](https://gist.github.com/gboudreau/94bb0c11a6209c82418d01a59d958c93?permalink_comment_id=5317087#gistcomment-5317087) Python script. Once you have the `ente_auth_import.plain` file from that script, transfer it to your device and follow the instructions below to import it into Ente Authenticator.

## Importing to Ente Authenticator (Method 1, method 2.1, method 4)

1. Copy the TXT file to one of your devices with Ente Authenticator.
2. Log in to your account (if you haven't already), or press "Use without backups".
3. Open the navigation menu (hamburger button on the top left), then press "Data", then press "Import codes".
4. Select the "Plain text" option.
5. Select the TXT file that was made earlier.

## Importing to Ente Authenticator (Method 2)

1. Copy the JSON file to one of your devices with Ente Authenticator.
2. Log in to your account (if you haven't already), or press "Use without backups".
3. Open the navigation menu (hamburger button on the top left), then press "Data", then press "Import codes".
4. Select the "Bitwarden" option.
5. Select the JSON file that was made earlier.

If this didn't work, refer to [**method 2.1**](#method-2-1-if-the-export-worked-but-the-import-didn-t).<br><br>

## Importing to Ente Authenticator (Method 3)

1. Open Ente Authenticator on your phone
2. Log in to your account (if you haven't already), or press "Use without backups".
3. Click the add button in the bottom right of the app.
4. Select "Scan a QR code" and scan the code from the browser.

Now that your secrets are safely stored, I recommend you delete the unencrypted JSON and TXT files that were made during the migration process for security.
