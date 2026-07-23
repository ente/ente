---
title: How it works
description: On-device inference, where models live, what is stored, and why nothing leaves your device
---

# How it works

Ensu is a chat app that runs a language model on your device instead of in the cloud. This page covers what that means in practice: what the app is doing while you chat, what is stored where, and which assumptions you can rely on.

None of this is required reading. If you just want to chat, the [Introduction](/ensu/) is enough. This page is for the curious and the privacy-conscious.

## The shape of it

Every popular AI chat app (ChatGPT, Claude, Gemini, and friends) follows the same shape: a thin client on your device talks to a model running on a server. The model is too large to fit on a phone, so the heavy lifting happens elsewhere. The trade-off is that everything you type ends up on someone else's machine.

Ensu inverts that:

- The model is small enough to fit on your device.
- The chat UI and the model run together, inside the same app, on the same machine.
- There is no server in the loop for inference.

Smaller models are not as capable as the largest cloud models, but they are good enough for many everyday uses, and they keep getting better. Ensu's job is to make the local version of this experience as friction-free as the cloud one.

## What runs on your device

Ensu is built on a shared **Rust core** that handles model loading, prompting, and token generation. The same core is wrapped in a native app per platform:

- **iOS and Android** ship the Rust core as a native library, with a Swift / Kotlin UI on top.
- **macOS, Windows, and Linux** ship as a [Tauri](https://tauri.app) app: the Rust core for inference, a small native shell, and the Ensu web UI rendered inside it.
- The **web** version runs everything in your browser. The model runs as WebAssembly, and the model file is cached in the browser's [Origin Private File System](https://web.dev/origin-private-file-system/) so you do not redownload it on every visit.

The underlying inference engine is based on [llama.cpp](https://github.com/ggerganov/llama.cpp) on native platforms and a WebAssembly build of it in the browser. Ensu wraps that engine so the chat UI, model downloads, and settings work the same way on every platform.

All of this is open source. The full source lives in [Ente's monorepo on GitHub](https://github.com/ente/ente), alongside Photos, Auth, Locker, and the other Ente apps.

## The model file

The model itself is a single file, usually 600 MB to 2 GB on phones and a few GB on desktops with enough RAM. It is in the [**GGUF**](https://huggingface.co/docs/hub/en/gguf) format, the same format used by llama.cpp. Multimodal models also ship with a separate **mmproj** file that contains the vision projector for processing images.

When Ensu opens for the first time, it picks a default model based on your device and downloads it from [Hugging Face](https://huggingface.co):

- **Desktop (MacOS, Windows, Linux) with 16 GB or more RAM**: Gemma 4 E4B (Q4_K_M), a 4-billion parameter multimodal model by DeepMind, around 6 GB.
- **Everywhere else** (Android, iOS, lower-memory desktop, and web): LFM 2.5 VL 1.6B (Q4_0), a 1.6-billion parameter multimodal model by Liquid AI, around 700 MB.

Native downloads are resumable: if the download is interrupted, Ensu picks it up from where it stopped the next time you launch the app. Downloads happen in parallel where possible, and retry automatically.

## What happens when you send a message

When you press send:

1. The composer hands the message, your image attachments (if any), and the recent chat history to the local model.
2. Ensu prepends the system prompt and any past messages still in context, then asks the model to continue the conversation.
3. The model streams tokens back to the app. You see them appear one chunk at a time.
4. When the model finishes (or you stop it), the final message is saved to local storage alongside the rest of the chat.

Nothing in this flow makes a network request. The only network traffic Ensu produces during a chat is what your operating system does on its own (DNS, OS background tasks). There is no Ente endpoint involved.

You can verify this for yourself by putting your device in airplane mode after the model is downloaded. Ensu keeps working.

## What is stored, and where

Ensu stores everything related to a chat on your device. There is no Ente account by default, so there is nowhere on Ente's servers for this data to live.

Local data includes:

- **The model file** (and the mmproj file for multimodal models). This is the largest item.
- **Voice transcription models** on iOS and Android, if you use voice input.
- **Your chat history**: messages, attachments, session titles, and branch metadata.
- **Settings**: your system prompt, model choice, and other preferences.
- **Logs**, for debugging. These do not include your chat content and are only used when you choose to export them.

Storage locations:

- **macOS**: `~/Library/Application Support/io.ente.ensu/`
- **Windows**: `%APPDATA%\io.ente.ensu\`
- **Linux**: `~/.local/share/io.ente.ensu/` (or `$XDG_DATA_HOME/io.ente.ensu/`)
- **iOS**: inside the app's sandbox; cleared when you delete the app
- **Android**: in the app's internal and external files directories; cleared when you uninstall
- **Web**: in your browser's [Origin Private File System](https://web.dev/origin-private-file-system/) for the model, and IndexedDB for chat history

To remove all of this, see [Uninstall Ensu](/ensu/faq/uninstall).

## What is not stored

What never leaves your device:

- The text you type into the composer.
- The voice you record for voice input (which is transcribed locally).
- The images you attach (which are processed locally by the multimodal projector).
- The model's responses.

What Ensu does not do:

- No accounts are required to chat. The login flow exists for future sync but is optional.
- No analytics or telemetry track what you ask the model.
- No background uploads of any kind.

What is sent over the network at all:

- The chat model download from Hugging Face on first launch (and when you switch models or update Ensu and a model version changes).
- On iOS and Android, the Parakeet transcription model and Silero VAD model download from `models.ente.io` the first time voice input is used, unless they are already cached.
- Software update checks, which the platform's app store or the desktop auto-updater handles.
- If you sign in for the future sync feature (see below), the standard authentication exchange.

You can confirm any of this by running Ensu offline once the required models are downloaded, or by inspecting [the source](https://github.com/ente/ente).

## Sync and backup (in development)

The current release does not sync your chats anywhere. Each device's history is independent.

Encrypted sync and backup have been built and are ready, but not enabled in this release: we want feedback on the product direction before finalizing the architecture. When sync ships:

- It will use your existing Ente account, so you can opt in or out at any time.
- It will be end-to-end encrypted with the same library and the same key derivation that Ente Photos, Auth, and Locker use. Ente's servers will see ciphertext only.
- It will be self-hostable, like the rest of Ente.
- Your existing local chats will be picked up and backed up. Nothing already on your device will be lost.

Learn more in the [FAQ](/ensu/faq/#sync).

## Trust model

Ensu's privacy is structural rather than promised:

- The model runs on your device, so the plaintext never has to leave.
- There is no Ente account in the loop by default, so there is nothing on the server side to compromise.
- The app is open source, so you can confirm any of this independently.

What Ensu does **not** defend against:

- A compromised device. If something on your phone or computer can read app data, it can read your chat history. Use device-level protections (full-disk encryption, app lock, screen lock).
- Bugs in the model itself. Local models can still hallucinate or give wrong answers. Treat the output the way you would treat any other AI's output.
- Inference from prompts. If you paste a sensitive document into a chat and ask the model to summarize it, the document is on your device, but it is also now part of your local chat history. The protection is from third parties, not from yourself or anyone with access to the same device.

For the privacy guarantees of future cloud sync, see [Sync and backup](#sync-and-backup-in-development) above.

## Related topics

- [Introduction](/ensu/): install, send your first message, and prompts to try.
- [Features](/ensu/features/): everything Ensu can do, organized by feature.
- [FAQ](/ensu/faq/): privacy, models, sync, and troubleshooting.
- [Source code on GitHub](https://github.com/ente/ente): the full Ensu source, including the Rust core, the platform UIs, and the web app.
