---
title: Windows troubleshooting
description: Troubleshoot Windows Hello and login errors in Ente Auth
---

# Windows Troubleshooting

## Ente Auth cannot start because MSVCP140.dll is missing {#missing-msvcp140-dll}

This error indicates that a Microsoft Visual C++ runtime dependency needed by the app is missing or unavailable.

1. Open Microsoft's [supported Visual C++ Redistributable downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170).
2. Install or repair the supported Redistributable that matches the architecture of the Ente Auth build you installed. The package must match the app's architecture, which may differ from the operating system's architecture.
3. Follow the installer's instructions, restart Windows if requested, and try opening Ente Auth again.

On a shared or managed computer, ask your administrator to install or repair the runtime. Do not download individual DLL files from third-party sites, and do not delete Auth's data to address this error.

If you are unsure which package is needed or the error remains, contact [support@ente.com](mailto:support@ente.com) with your Windows version, Auth version, and the exact error message.

## Windows Hello Prompt Does Not Appear

Ente Auth uses Windows Hello when an action requires system authentication.

If Ente Auth asks you to authenticate but Windows does not display a security
prompt:

1. Open **Windows Settings → Accounts → Sign-in options**.
2. Verify that your Windows Hello PIN is configured and works.
3. If Windows reports a PIN as configured but it does not work, use the Windows
   PIN recovery options to reset or recreate it.
4. Restart Ente Auth and try again.

## HandshakeException During Login

This error usually happens when the Trusted Root certificates on your Windows machine are outdated.

To update the Trusted Root Certificates on Windows, you can use the `certutil` command. Here are the steps to do so:

1. **Open Command Prompt as Administrator**:
    - Press `Windows + X` and select `Command Prompt (Admin)` or `Windows PowerShell (Admin)`.

2. **Run the following command to update the root certificates**:

    ```bash
    certutil -generateSSTFromWU roots.sst
    ```

    This command will generate a file named `roots.sst` that contains the latest root certificates from Windows Update.

3. **Install the new root certificates**:

    ```bash
    certutil -addstore -f ROOT roots.sst
    ```

    This command will add the certificates from the `roots.sst` file to the Trusted Root Certification Authorities store.

4. **Clean up**: After the installation, you can delete the `roots.sst` file if you no longer need it:
    ```bash
    del roots.sst
    ```

Make sure to restart your application after updating the certificates to ensure the changes take effect.

If the above steps don't resolve the issue, please follow [this guide](https://woshub.com/updating-trusted-root-certificates-in-windows-10/#h2_3) to update your trusted root certicates, and try again.
