# Android dev without Android Studio

You don't need to install the full Android Studio for working on the Android app, you can instead just install a JDK and the Android command line tools and thereafter drive everything from the terminal.

```sh
# Install JDK
brew install openjdk@17
sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk

# Add the following to your .zshrc/.bashrc
export ANDROID_HOME=$(brew --prefix)/share/android-commandlinetools
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Install Android command-line tools
brew install --cask android-commandlinetools
flutter doctor --android-licenses # OR sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"

# Create emulator (on Intel Mac, use x86_64 instead of arm64-v8a)
sdkmanager "emulator" "system-images;android-36;google_apis;arm64-v8a"
avdmanager create avd -n pixel9-36 -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_9
emulator -avd pixel9-36

# Profit
flutter run --flavor independent -d sdk
```

The above is macOS-specific, but swap `brew` for your package manager (unless `brew` is your package manager) and skip the JDK symlink step and it should work on Linux too.

## App logs

With ADB authorized, open the app with `internalUser` enabled and unlock the device. Export up to 40 MiB of saved logs, newest files first:

```sh
adb shell dumpsys activity io.ente.photos/io.ente.photos.MainActivity --ente-logs > ente-logs.txt
```

For independent builds, change the package before `/` to `io.ente.photos.independent`. For Android logs, use `adb logcat -d`.
