# iOS SpringBoard AI Agent: Voice-Controlled UI Automation

This is an **unfinished experimental jailbreak tweak** that turns your iOS device into an **AI-powered voice assistant** capable of analyzing the screen, locating UI elements, and tapping them automatically.

I built this as a fun experiment over about a week, but stopped before fully finishing it. It is in a **work-in-progress state** and still has rough edges. Feel free to fork and continue developing it!

---

https://github.com/user-attachments/assets/e63c6fd5-2374-4b79-aea1-ffaccd90e5fb

### Features

- **Voice Input:** Press and hold a floating microphone button to speak commands.
- **AI-Powered Screen Analysis:** Captures a live screenshot and sends it to OpenAI's `gpt-4o` model for visual understanding.
- **Fake Touch Simulation:** Automatically taps UI elements by mapping AI-provided coordinates back to the device screen.
- **Debug Visuals:** Draws a dot on the screenshot to visualize where the AI decided to tap.
- **UDP Logging:** Sends logs to a remote host (optional) for easier debugging.

---

### Overview

The **core concept works** (speech -> AI -> tap), but it needs refinement to be fully reliable. It serves as a solid foundation for building an **OS-level AI agent** on iOS.

The ultimate goal was an **autonomous assistant** that can:
- Process natural language voice commands (*"Open Safari and search for GitHub"*).
- Visually parse the active screen.
- Perform actions automatically via simulated touches.

This tweak handles the fundamentals; next steps include multi-step task planning and general polish.

---

### Concept Example

> Press the mic button and say:  
> **"Message Mehmet Hi"**  
>
> The agent workflow:
> 1. Open Messages.
> 2. Locate Mehmet's conversation thread.
> 3. Tap to open it.
> 4. Type "Hi" via `insertText`.
> 5. Tap send.

---

### How It Works

1. **Floating Button Overlay:** A draggable microphone button sits above SpringBoard.
2. **Speech Capture:** Transcribes voice input using `SFSpeechRecognizer`.
3. **Screenshot & Prompt:** Sends the transcription and screenshot to OpenAI.
4. **AI Response Parsing:** Extracts element coordinates from the JSON response: `{ "x": <number>, "y": <number> }`.
5. **Touch Simulation:** Maps coordinates to screen space and triggers a touch event.

Had to make it public -> private -> public so stars are gone 😭

### Example Flow

1. Press and hold the mic button.
2. Say: *"Tap the Settings icon."*
3. AI returns `{ "x": 210, "y": 120 }`.
4. The tweak simulates a tap at the target coordinates to open Settings.
