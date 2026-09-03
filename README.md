<p align="center">
  <img src="docs/banner.jpg" alt="Crayon" width="100%">
</p>

<p align="center">
  <b>English</b> &nbsp;·&nbsp; <a href="README.ar.md">العربية</a>
</p>

<h1 align="center">Crayon</h1>

<p align="center">
  A personal AI image &amp; video studio for your phone, built directly on <a href="https://openrouter.ai">OpenRouter</a>.<br>
  No accounts, no backend, no middleman. Your key, your device, your files.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.7%2B-02569B?logo=flutter&logoColor=white">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey">
  <img alt="Powered by OpenRouter" src="https://img.shields.io/badge/powered%20by-OpenRouter-6467F2">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

Crayon is a thin, honest client for OpenRouter's image and video models. Every
control on the screen is generated from what the selected model actually reports
it supports, so a model the app has never seen still renders correctly. There is
no server in the middle: generations run straight from your device to OpenRouter,
and everything you make stays on the phone.

## What it does

- **Studio** — switch between Image and Video, pick a model, pick a task, write a
  prompt, generate. The controls are built from the model's declared
  capabilities, so Seedream shows its aspect ratios and 4K tier, Kling shows a
  length slider and an audio toggle, and a brand-new model just works.
- **Gallery** — infinite masonry of everything you have made, with search,
  image / video / saved filters, and live tiles for jobs still running.
- **Detail** — regenerate, clone the settings back into the studio, edit,
  outpaint, animate a still into video, upscale, save to your phone gallery,
  share, delete.
- **Characters** — create a person from a few reference photos, bake a single
  clean "model sheet" once, then reuse that one image for a consistent look
  across new generations at low cost.
- **Spend** — your live OpenRouter balance, what this app specifically has cost,
  a 30-day chart and a per-model breakdown.

## Setup

1. Build and install the app (see [Build](#build)), or run it from source.
2. **Settings → paste your OpenRouter key.** It is validated against the API
   before it is saved, and stored in the platform keystore. Keys look like
   `sk-or-v1-...` and are issued at
   [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys).
3. Generate.

### Building with a key already inside (optional)

`--dart-define-from-file=env.json` bakes a default key into the build so the app
works the moment it opens. `env.json` is gitignored; copy `env.example.json` and
fill in `OPENROUTER_KEY`.

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```

> **The key is extractable from any build made this way** — it is a string in the
> binary. That is fine for a build that only ever lives on your own phone. Do
> **not** publish such an APK, attach one to a release, or hand it to anyone:
> whoever holds it can spend your credit. Ship builds without the flag and let
> people paste their own key.

## Prompt enhancement

The biggest quality difference between a first-party app and raw API access is
that the first-party app does not send your text to the model — it rewrites it
first (the [Seedream 4.0 paper](https://arxiv.org/html/2509.20427v3) documents a
prompt-enhancement model with auto-thinking rewriting in the pipeline).

Crayon does the same, with one difference: **the rewrite is shown to you and you
choose whether to keep it.** An invisible rewrite means a bad result can never be
traced to whether the model failed or the words changed underneath you.

Tap the wand in the prompt editor. Any OpenRouter chat model can do the
rewriting, set in Settings. A rewrite costs a tiny fraction of a cent against
cents for an image, so it is effectively free.

## How tasks are decided

Nothing is hardcoded per model. Tasks come from declared capabilities:

| Capability reported by the model | Task the studio offers |
|---|---|
| always (unless a reference is mandatory) | Text to image |
| `input_references.max >= 1` | Image to image, Edit, Outpaint |
| `input_references.min >= 1` | text-to-image is **hidden**, a reference is required |
| always (video) | Text to video |
| `first_frame` | Image to video |
| `first_frame` + `last_frame` | First / last frame |
| a reference pricing SKU | Reference to video |
| a video-input pricing SKU | Video to video |
| model id contains `avatar` | Avatar / lipsync |
| model id contains `upscale` | Upscale |

Same for the controls: `supported_durations` becomes the length slider,
`supported_aspect_ratios` becomes the ratio picker, `generate_audio` becomes the
audio switch, and `allowed_passthrough_parameters` become the Advanced section.

## Honest limits

These are constraints of the OpenRouter image API, not missing work:

- **Inpainting is real, but not because of a mask API.** No model on OpenRouter
  exposes a `mask` parameter, and it hardly matters: even APIs that DO take a
  mask re-render the whole frame, and OpenAI's own forum says plainly that with
  gpt-image models ["you cannot have perfect preservation"](https://community.openai.com/t/gpt-image-api-how-can-i-reliably-edit-only-the-masked-selected-area-while-preserving-everything-else/1389833).
  So every serious tool does the same last step, and so does Crayon: the painted
  region is marked into the image, the model regenerates, and the result is
  **composited back over the original through a feathered mask**
  (`out = mask * generated + (1 - mask) * original`). Pixels outside your mark
  are the original's own bytes. `test/inpaint_composite_test.dart` asserts it.
- **Outpaint is done client-side.** Your image is composited onto a larger
  transparent canvas at the target aspect ratio and the model fills the empty
  area — a real composite, not a prompt trick, which is why it works without mask
  support.
- **Image upscale is a re-render**, not a dedicated upscaler: the image is sent
  back as a reference at the model's largest resolution tier. Video upscale uses
  the real `flux-video-upscale` model.
- **No in-app top-up.** OpenRouter has no API for adding credit, so the Spend
  screen opens their page in your browser.
- **Cost estimates say when they are guesses.** Per-image and per-second pricing
  is computed exactly. Token-billed models (Seedance, and Google / OpenAI image)
  depend on what the provider renders, so those show `metered` or a `~` prefix
  rather than a made-up figure. The real cost is read back from the API response
  after every generation and is what the Spend screen totals.

## Safety

Crayon only routes to OpenRouter's mainstream image and video models, which
enforce their own safety policies at the source. The app ships no "uncensored"
provider and adds nothing that bypasses them, so NSFW or otherwise disallowed
content is refused by the model and can't be forced from the client — and the
prompt enhancer is guarded so it never introduces any. That safeguard is built
in; if you fork Crayon and want an extra policy layer, the hook is
`LibraryState.submit`.

## Models

The app ships a bundled snapshot so it is usable the moment it opens, then
refreshes in the background and caches to disk. Models are pulled live from
OpenRouter's `/api/v1/images/models` and `/api/v1/videos/models`.

- **Image** includes Seedream, Nano Banana / Nano Banana Pro, GPT Image, Flux,
  Qwen Image, Recraft, Krea, Grok Imagine, and more.
- **Video** includes Seedance, Kling, Veo, Sora, Hailuo, Wan, Runway, and Flux
  video upscale.

The exact list is whatever your OpenRouter account can reach at refresh time.

## Adding a provider

Everything provider-specific sits behind one interface, `GenBackend`
(`lib/api/gen_backend.dart`): list models, generate an image, produce a video,
read the balance. `ORModel` normalises capabilities into a provider-neutral shape
and the whole UI is generated from that shape, so a new backend needs no UI work
— just a class that implements the interface. `OpenRouter`
(`lib/api/openrouter.dart`) is the one implementation today; video there returns a
job id the runner polls and can resume after a restart.

## Build

```bash
flutter pub get
flutter test
flutter build apk --release          # Android
# or:  flutter build ipa --release    # iOS
```

The Android APK lands at `build/app/outputs/flutter-apk/app-release.apk`.
Release is signed with the debug key — fine for sideloading onto your own phone,
not for a store listing.

Flutter is available at [flutter.dev](https://docs.flutter.dev/get-started/install).

## Layout

```
lib/
  api/        gen_backend.dart  the provider-neutral interface + shared result types
              openrouter.dart   OpenRouter backend: /images, /videos, /credits
              or_model.dart     capability parsing and task derivation
              enhance.dart      prompt rewriting on an OpenRouter chat model
  core/       theme.dart        monochrome tokens and shared widgets
              estimate.dart     cost estimation, including when it refuses to guess
              imaging.dart      downscaling, data URLs, the outpaint composite
  data/       db.dart           sqlite history
              files.dart        on-device storage
              character.dart    a reusable person + their reference images
              gen_record.dart   one generation
  state/      catalog_state.dart  bundled snapshot, disk cache, live refresh
              studio_state.dart   what you are about to generate
              library_state.dart  the gallery and the job runner
              settings_state.dart key and preferences
  ui/         studio, gallery, detail, characters, spend, settings, model picker
```

## License

[MIT](LICENSE).
