---
title: Ensu FAQ
description: >
    Frequently asked questions about Ensu, Ente's private on-device AI chat app
---

# Ensu FAQ

Ensu is Ente's local-first AI chat app that runs entirely on your device. For a full overview of what Ensu is and why it exists, see the [introduction](/ensu/) or read the [launch blog post](https://ente.com/blog/ensu/).

Below are answers to the most common questions.

## General

### What is Ensu? {#what-is-ensu}

Ensu is an AI chat app made by Ente that runs a language model (LLM) directly on your phone, tablet, or computer. Unlike ChatGPT or similar cloud-based apps, Ensu does not send your messages to any server. Everything happens locally on your device.

It is free, open source, and works offline after the initial model download.

For the full story behind Ensu, including why we think local LLMs matter, read the [launch blog post](https://ente.com/blog/ensu/).

### Which platforms does Ensu support? {#supported-platforms}

Ensu is available for:

- **iOS** (iPhone and iPad)
- **Android**
- **macOS**
- **Windows**
- **Linux**
- **Web** (experimental, runs in your browser)

You can download it from [ente.com/ensu](https://ente.com/ensu).

### Does Ensu require an internet connection? {#offline-usage}

Only for the first launch, when the model needs to be downloaded (roughly 1 GB depending on the model). After that, Ensu works fully offline. You can chat on a flight, in a remote area, or anywhere else without connectivity.

### Is Ensu free? {#pricing}

Yes. Ensu is completely free to use with no usage limits. It is currently an Ente Labs project, which means we are still figuring out its long-term direction. There is no subscription or payment required.

### Is Ensu open source? {#open-source}

Yes. Ensu is fully open source, just like all other Ente products. The code lives in the same [GitHub repository](https://github.com/ente/ente) as Ente Photos, Auth, and Locker. The core inference logic is written in Rust, with native apps for mobile (Swift/Kotlin) and desktop (Tauri).

## Privacy and Security

### How private is Ensu? {#privacy}

Completely private. The AI model runs on your device, and your conversations never leave it. Ente does not collect, transmit, or have access to anything you type or any images you attach.

There are no accounts required and no analytics or tracking. This is private by design, not by policy.

### Can Ente see my conversations? {#can-ente-see-chats}

No. All processing happens locally on your device. Your messages are not sent to any server. Ente has zero access to your conversations.

### Is my data end-to-end encrypted? {#encryption}

Your local conversations are stored on your device and are not sent anywhere, so encryption in transit is not applicable in the default setup.

When encrypted sync and backup arrive (see [below](#sync)), your chats will be end-to-end encrypted using the same encryption that Ente Photos, Auth, and Locker use. This means even on the server, your data will be unreadable to anyone except you.

## Models

### What model does Ensu use? {#default-model}

Ensu picks a default model based on your device:

- **macOS with 16 GB or more RAM**: Gemma 4 E4B (Q4_K_M), a 4-billion parameter model by Deepmind. This offers higher quality responses on machines that can handle it.
- **All other platforms** (Android, iOS, Windows, Linux, lower-memory macOS, and web): LFM 2.5 VL 1.6B (Q4_0), a 1.6-billion parameter multimodal model by Liquid AI. This is compact enough to run well on phones and less powerful computers.

The model downloads automatically on first launch and is around 1 GB in size (varies by model).

> We may change the default models in future releases as better options become available.

### Can I run multiple models at the same time? {#multiple-models}

No. Ensu loads one model at a time. Running a language model uses a significant amount of your device's memory (RAM), and loading two models simultaneously would exceed what most consumer devices can handle.

The ability to switch between models is not available in the current release, but it is something we may enable in a future update.

### Can I use a different model? {#custom-model}

Not in the current release. Ensu ships with a fixed default model for each platform. The ability to choose or bring your own model is something we might consider for a future update.

## Features

### Can I attach images? {#image-attachments}

Yes. Ensu supports image attachments on iOS, Android, and desktop. You can attach photos from your device and ask the model about them. The model processes the image locally, and the image is never uploaded anywhere.

Image attachments are not supported on the web version at this time.

### Can I talk to Ensu instead of typing? {#voice-input}

Yes, on iOS and Android. Tap the microphone in the chat composer and speak your prompt. Ensu transcribes it locally on your device, so your voice input is not sent to Ente or any external transcription service.

This voice input feature is not available on the web and desktop version.

### Does Ensu support web search? {#web-search}

No, Ensu does not have web search. The model answers based on what it learned during training, not by looking things up on the internet.

We are open to feedback on this. The challenge is that adding web search would require relying on an external service to process your queries, and there is no guarantee that such a service would handle your searches privately. This goes against Ensu's core design principle of keeping everything on your device.

If you have thoughts on how we should approach this, let us know on [Discord](https://ente.com/discord) in the `#ensu` channel or at [team@ente.com](mailto:team@ente.com).

### Can Ensu do everything ChatGPT can? {#comparison-with-chatgpt}

Not yet. Ensu runs a much smaller model on your device compared to the large models that power ChatGPT or Claude, which run on powerful servers. This means:

- Ensu is great for everyday conversations, brainstorming, explaining concepts, discussing books, and private reflection.
- It may struggle with highly technical, multi-step reasoning or very long and complex prompts.

The gap between local and cloud models is closing every day. As smaller models improve, Ensu will get better too.

### Does Ensu remember previous conversations? {#conversation-history}

Within a single chat session, Ensu remembers what you have talked about and can refer back to it. However, if the conversation gets very long, older parts may fall out of the model's context window (the amount of text it can hold in memory at once), and it may lose track of things said much earlier.

Across different sessions, Ensu does not carry over memory. Each session is independent, so the model will not recall something you discussed in a previous chat.

Your chat history is saved locally on your device, so you can always scroll back and read older messages yourself, or delete sessions you no longer need.

## Sync and Backup

### Can I sync chats across devices? {#sync}

Encrypted sync and backup have been built and are ready, but they are not enabled in the current release. We want to gather feedback on the product direction before finalizing the sync architecture.

When sync does arrive, it will use your existing Ente account with full end-to-end encryption, and it will be self-hostable just like Ente Photos. Your existing local chats will be backed up and synced automatically.

### Will my local chats be lost when sync is enabled? {#local-chats-migration}

No. When sync arrives, your existing local conversations will be picked up and backed up. Nothing will be lost.

### Does Ensu use my Ente account? {#ente-account}

Currently, Ensu does not require an Ente account. You can use it without signing in. When sync is enabled in a future release, connecting your Ente account will be optional and will allow you to back up and sync your chats across devices.

## Troubleshooting

### The model download is taking a long time {#slow-download}

The default model is roughly 1 GB. Download speed depends on your internet connection. If the download stalls or fails, Ensu will automatically retry and resume from where it left off (up to 3 attempts).

Make sure you have a stable connection and enough free storage on your device.

### The app feels slow or the model takes a long time to respond {#slow-responses}

Response speed depends on your device's hardware. On older phones or computers with limited RAM, the model may take longer to generate text. A few things you can try:

- Close other memory-heavy apps while using Ensu.
- On Android, make sure battery optimization is not restricting Ensu.

### The model failed to load {#model-load-failure}

This usually happens when your device does not have enough free RAM or storage. Try:

1. Closing other apps to free up memory.
2. Restarting the app.
3. Making sure you have at least 2 GB of free storage for the model file.

If the problem persists, export your logs from the app settings and share them with us at [team@ente.com](mailto:team@ente.com).

### How do I remove downloaded models and local data? {#uninstall}

Learn more at [Uninstall Ensu](/ensu/faq/uninstall).

## Feedback and Support

### How can I give feedback? {#feedback}

We would love to hear from you. The future direction of Ensu is still taking shape, and your input directly influences what we build next.

- **Discord**: Join the `#ensu` channel on [Discord](https://ente.com/discord).
- **Email**: Write to [team@ente.com](mailto:team@ente.com).
- **GitHub**: Open an issue or discussion on [GitHub](https://github.com/ente/ente).

### Where can I report bugs? {#bug-reports}

You can report bugs on [GitHub](https://github.com/ente/ente/issues) or by emailing [team@ente.com](mailto:team@ente.com). If possible, include your device model, OS version, and any logs exported from the app settings.

---

**Can't find what you're looking for?**

- Read the [Ensu introduction](/ensu/) for an overview
- Read the [launch blog post](https://ente.com/blog/ensu/) for the full story
- Join [Discord](https://ente.com/discord) and head to the `#ensu` channel
- Write to [team@ente.com](mailto:team@ente.com)
