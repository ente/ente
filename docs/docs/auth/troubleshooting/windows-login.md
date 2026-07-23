---
title: Unable to login on Windows Desktop
description: Troubleshooting when you are not able to login or register on Ente Auth app on Windows
---

# Windows Login Error

### HandshakeException: Handshake error in client

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
