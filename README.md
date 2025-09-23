# iOS SpringBoard AI Agent – Voice-Controlled UI Automation

This is an **unfinished experimental jailbreak tweak** that turns your iOS device into an **AI-powered voice assistant** capable of analyzing the screen, locating UI elements, and tapping them automatically.

⚠️ **Disclaimer:**  
I built this as a fun experiment over about a week — but I got bored and stopped before fully finishing it.  
It is in a **work-in-progress state** and still has some rough edges.  
If you're interested in the idea, feel free to fork it and continue developing it!

---


https://github.com/user-attachments/assets/e63c6fd5-2374-4b79-aea1-ffaccd90e5fb


## 🚀 Features (Partially Working)

- 🎤 **Voice Input:** Press and hold a floating microphone button to speak commands.
- 🧠 **AI-Powered Screen Analysis:** Captures a live screenshot and sends it to OpenAI’s `gpt-4o` model for visual understanding.
- 👆 **Fake Touch Simulation:** Automatically taps UI elements by mapping AI-provided coordinates back to the device screen.
- 🖼️ **Debug Visuals:** Draws a dot on the screenshot to visualize where the AI decided to tap.
- 🌐 **UDP Logging:** Sends logs to a remote host (optional) for easier debugging.

---

Basically, the **core idea works** (speech → AI → tap), but it needs some refinement to be reliable.  
I stopped here because I lost interest — but the project is a great starting point for anyone who wants to build a true **OS-level AI agent** on iOS.

---

## 🎯 Vision

The ultimate goal was to create an **autonomous assistant** that could:
- Take natural language voice commands (_"Open Safari and search for GitHub"_).
- Visually understand the current screen.
- Perform actions automatically using simulated touches.

This tweak already does most of that — it just needs someone to polish it and maybe add multi-step task planning.

---

## 🧠 Example Use Case (Imagine the Possibilities)

Here’s what an OS-level AI agent could do in the future with a bit more work:

> You press the mic button and say:  
> **"Message Mehmet Hi"**  
>
> The agent could:
> 1. Open the Messages app.
> 2. Find Mehmet’s conversation.
> 3. Tap into it.
> 4. Type “Hi” automatically thru insertText.
> 5. Hit send — all without you touching the screen.

This is just one example, but the concept is that **anything you can normally do by tapping around, the AI can do for you**.

---

## 🛠️ How It Works

1. **Floating Button Overlay** – A draggable microphone button sits above SpringBoard.
2. **Speech Capture** – Voice input is transcribed with `SFSpeechRecognizer`.
3. **Screenshot + Prompt** – Sends both the transcription and the screenshot to OpenAI.
4. **AI Response Parsing** – Expects `{ "x": <number>, "y": <number> }` JSON with element center coordinates.
5. **Touch Simulation** – Maps coordinates to screen space and performs a fake tap.

---

## 📸 Example Flow

1. Press & hold the mic button.  
2. Say: "_Tap the Settings icon._"  
3. AI returns `{ "x": 210, "y": 120 }`.  
4. The tweak simulates a tap at that point — Settings opens automatically.

---

