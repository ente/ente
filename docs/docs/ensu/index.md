---
title: Ensu
description: >
    Ensu is Ente's private, on-device AI chat app that runs locally with no cloud dependency for inference
---

# Ensu

Ensu is Ente's local-first AI chat app. It runs a large language model (LLM) directly on your device, so your conversations stay completely private. There are no accounts required, no tracking, no usage limits, and no cost.

Think of it as a ChatGPT-like experience, except nothing ever leaves your device. It works offline, and it is free and open source.

For the full backstory on why we built Ensu and where it is headed, read the launch post: [Ensu - Ente's Local LLM app](https://ente.com/blog/ensu/).

## What Ensu is for

People use Ensu when they want an AI they can think alongside without sending their thoughts anywhere:

- **Private reflection and journaling**, with a model that has nowhere to phone home.
- **Offline use** on flights, in remote areas, or anywhere without connectivity.
- **Discussing books and ideas.** Even the smaller default model knows classics like the Gita and the Bible quite well.
- **Quick everyday questions** where the answer does not need a web search and you would rather not paste your context into someone else's logs.

It is not a replacement for the largest cloud models. The model that runs on your phone is much smaller than the ones that power ChatGPT or Claude, so very long, highly technical, or multi-step reasoning tasks can be harder for it. The trade-off is privacy by design instead of by policy.

## How it works in one paragraph

When you first launch Ensu, it downloads a small language model and runs it locally from then on. Inference happens on your CPU and GPU, in the same app, with no calls to Ente or anyone else. Your conversations, voice input, and image attachments are processed on-device. Learn more in [How it works](/ensu/how-it-works).

## Install

Download Ensu from [ente.com/ensu](https://ente.com/ensu) or pick a platform below.

| Platform                | Where to get it                                                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| iOS                     | [App Store](https://apps.apple.com/app/ensu-entes-local-llm/id6758197006)                                                                   |
| Android                 | [Google Play](https://play.google.com/store/apps/details?id=io.ente.ensu) / [GitHub releases](https://github.com/ente/ente/releases?q=ensu) |
| macOS / Windows / Linux | [GitHub releases](https://github.com/ente/ente/releases?q=ensu)                                                                             |
| Web                     | [ensu.ente.com](https://ensu.ente.com) (experimental)                                                                                       |

If you install the Android APK directly from GitHub releases, verify it against the published signing certificate. Learn more in [Verify the Ensu Android APK](/ensu/faq/android-apk-signature).

The desktop apps auto-update on macOS, Linux, and Windows, so once installed you do not need to keep visiting the releases page.

## Send your first message

1. Open Ensu.
2. Type into the chat composer at the bottom of the screen.
3. Send. The model loads (a few seconds the first time, faster on later messages) and starts streaming a response.

That is the entire flow. There is no sign-in, no model picker to choose from, no "system" to configure. Each app keeps a sidebar of your previous chat sessions on the left, grouped by recency. Start a new chat at any time from the sidebar.

You can attach images and, on iOS and Android, dictate your message instead of typing. Learn more in [Features](/ensu/features/).

## What to try

If you are new to local LLMs, a few prompts that usually go well even on the smaller default model:

- "Summarize this paragraph in one sentence." (paste a paragraph)
- "I'm thinking about [something]. Help me work through it." (private reflection)
- "Translate the following into [language]: …"
- "Explain [a concept you half-remember] like I'm in a hurry."
- A photo of a sign in another language, with "What does this say?"

If the model gets confused on a long technical task or struggles with a multi-step math problem, that is the model's limit, not a bug. Local models are getting better quickly. Learn more about the gap in the [FAQ](/ensu/faq/#comparison-with-chatgpt).

## Current status

Ensu is currently an **Ente Labs** project. We are actively iterating on the product and its direction, and we have not committed to a fixed price or stability guarantee just yet. It is already useful for many things, and it is free for now, with no limits.

For recent updates, see the [Changelog](/ensu/changelog).

## Read next

- [How it works](/ensu/how-it-works): on-device inference, what is stored where, and how Ensu stays private without a server.
- [Features](/ensu/features/): an overview of what Ensu can do on each platform.
- [FAQ](/ensu/faq/): common questions about privacy, models, sync, and troubleshooting.

## Getting help

- **Discord**: join the `#ensu` channel on [Discord](https://ente.com/discord).
- **Email**: write to [team@ente.com](mailto:team@ente.com) with feedback or questions.
- **GitHub**: report bugs or request features on [GitHub](https://github.com/ente/ente/issues).
