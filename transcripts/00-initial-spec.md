# Transcript — Clarinet Tone & Pitch Trainer

A running log of prompts for the interview project. Newest entries appended below.

---

## Prompt 00 — Initial spec (2026-11-02)

> I am doing a coding project for an interview.
>
> What you'll be doing: as AI capabilities advance rapidly, engineers at Anthropic face a unique challenge - building tools and experiences that are genuinely useful, trustworthy, and delightful. The best products demonstrate taste, handle complexity gracefully, and solve real problems in non-obvious ways.
> This assignment asks you to build a functional prototype that demonstrates your ability to ship an impressive, self-contained experience, one that showcases your judgment, creativity, and execution. You'll choose from one of three themes: exploration & understanding, creative & generative tools, and systems & reliability.
> What we need from you:
> - A link to your working prototype (hosted anywhere)
> - GitHub repo link with your code
> - Design rationale - Both a ~5 minute self-recorded video and a short written doc explaining your approach and what makes it novel, key design decisions and tradeoffs, learnings, and iterations
> - Claude/AI transcripts - We expect you to use AI tools during development! Share your interaction history from Claude Code, Claude.ai, or other tools you used
>
> I need you to keep transcripts for me. Write all the prompts to disk so I can keep track of them.
>
> My idea is build a tool to help clarinetists improve their tone and pitch while also practice scales, major and minor. My idea is for the UI to show scales as sheet music, starting with a 80 bpm eighth notes. The user can adjust the tempo and note duration (1/32 -> whole). The user plays the music, and the app records. Remember clarinets are not concert pitch, so you need to transpose for clarinets when you do your comparison. The scale should be two octaves, starting as low as possible on a clarinet.
>
> If the user hits the note perfectly tempo-wise and it is on pitch, the note highlights in a flashy rainbow.
> If the user hits the note slightly off tempo-wise, the note highlights in green.
> If the user hits the note more slightly off tempo-wise, the note highlights in yellow.
> If the user hits the note off tempo-wise, the note is shaded in light gray.
> For pitch, if it is off, you draw a shadow note higher or lower than the note depending on what note the user actually played. Use sharp and flat notation. If they are slightly off, less than a sharp or flat from the main note, physically shift the note up or down accordingly.
>
> When they are done playing the scale, analyze the pitch quality. Ignore notes that are completely off or missed notes.
>
> Now you have to use an AI API to analyze the pitch and tone quality compared to other professional clarinet music. Use open source, public clarinet recordings as training data.
>
> Also, you need to give tips if the user has issues. For example, if a certain A is always off, mention that. Give tips on how to improve the tone and pitch. Is there clarinet assembled correctly? Problem with the embouchure? Reed too stiff? Problem with the clarinet? Give tips.
>
> But also give positive feedback.
>
> Also have fun and try to guess the clarinet model and the kind of reed. And also mention how close they are to a professional player. Especially if they are close to a certain clarinet style, mention that.

---

## Prompt 01 — Direction confirmed (2026-11-02)

> Proceed as native. Platform is correct. enable the audio-input entitlement (+ NSMicrophoneUsageDescription), and network

Decisions locked for the build:
- Native macOS app (primary target).
- Claude API for the qualitative coaching / clarinet + reed guesses / "how close to a pro" verdict.
- On-device YIN/autocorrelation pitch & tempo detection (the DSP layer).
- Curated, baked-in professional reference profile (no copyrighted audio shipped).
- Enable mic input + outgoing network via the project's generated-entitlements build settings.

---

## Prompts 02–10 — iteration (2026-11-02 → 2026-11-04)

> 02: Label the scale; let the user change tonic and major/minor type; use a key signature rather than inline sharps/flats.

> 03: Use conventional spellings for minor keys (no theoretical double-flat keys).

> 04: The font for the ligature (clef/accidentals) and notes is off — use Palatino.

> 05: (a) The top switches have no labels. (b) Add an edge arrow when the staff can scroll, and make tapping it scroll.

> 06: Eight-part pass — (1) fix white-on-white text, (2) follow Apple Liquid Glass everywhere, (3) add a 4/4 time signature, (4) replace the count-in with a film-leader / old-timey cinema countdown, (5) cross-fade Record into a red Stop, (6) actually record audio so the user can listen back and choose to save to disk, (7) silence should not register as very high notes (show gray), (8) cite real sources (YouTube/URLs) for performance tips.

> 07: The sheet music should auto-scroll left→right to keep the cursor visible. Rename the app (Tönika is a real app) — final choice: **Tone/Pitch**.
