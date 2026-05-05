# LogiPrice: Conversational AI Logistics & Dynamic Pricing Assistant

LogiPrice is a state-of-the-art, voice-first logistics pricing engine and AI assistant. It provides a full speech-to-speech conversational flow, enabling users to seamlessly query shipping rates, analyze options, and confirm bookings entirely hands-free. The system employs dynamic pricing optimization and uses highly specialized Small Language Models (SLMs) for local intent parsing and real-time inference.

## 🌟 Novelty & SLM Architecture

Unlike traditional logistics dashboards that rely heavily on massive, generalized LLMs with high latency, LogiPrice leverages the concept of **Small Language Models (SLMs)** for specialized tasks:

1. **Local Intent Parsing:** Instead of performing an expensive network round-trip for every user utterance, LogiPrice uses high-performance on-device intent extraction. When a user says *"Book the fastest option"* or *"Go with ColdChain Express"*, the SLM-inspired parsing algorithms running natively within the Flutter client instantly map the natural language to the structured JSON options.
2. **Low-Latency Conversational Flow:** By offloading immediate decision-making and rank extraction (e.g. "cheapest", "fastest", "top option") to the client, the application achieves real-time speech-to-speech latency. 
3. **Deterministic Orchestration:** The backend optimization engine handles the heavy-lifting of route calculation and pricing logic, but returns structured data alongside a concise LLM-generated explanation, ensuring the voice assistant never "hallucinates" prices or routes.

## 🏗️ Architecture

```mermaid
graph TD
    %% Define Styles
    classDef client fill:#0B192C,stroke:#3B82F6,stroke-width:2px,color:#fff
    classDef voice fill:#1A2235,stroke:#E040FB,stroke-width:2px,color:#fff
    classDef backend fill:#111827,stroke:#10B981,stroke-width:2px,color:#fff
    classDef data fill:#1A2235,stroke:#F59E0B,stroke-width:2px,color:#fff

    %% Nodes
    User(("🗣️ User (Voice)"))
    
    subgraph Client ["Client (Flutter Web)"]
        UI["Voice UI (Glassmorphism)"]:::client
        ASR["Speech-to-Text Engine"]:::voice
        TTS["Text-to-Speech Engine"]:::voice
        NLP["Local SLM Intent Parser"]:::client
        State["App State Manager"]:::client
    end
    
    subgraph Server ["Backend (FastAPI)"]
        Router["API Gateway"]:::backend
        Pricing["Dynamic Pricing Engine"]:::backend
        Optimization["Route Optimizer"]:::backend
        LLM["Generative Explanation Service"]:::backend
    end
    
    subgraph Storage ["Data Layer"]
        DB[("Carrier & Market Data")]:::data
    end

    %% Connections
    User -->|Speaks Query| ASR
    ASR -->|Live Transcript| NLP
    NLP -->|Extracts Entities| State
    State -->|HTTP POST| Router
    
    Router --> Pricing
    Router --> Optimization
    Pricing --> DB
    Optimization --> DB
    
    Optimization --> LLM
    Pricing --> LLM
    LLM -->|JSON + Explanation| Router
    
    Router -->|Response| State
    State --> UI
    State --> TTS
    TTS -->|Reads Explanation| User
    
    User -->|Speaks Choice| ASR
    ASR --> NLP
    NLP -->|Matches Option| UI
    UI -->|Booking Confirmation| TTS
```

## 🔒 Security Details

The LogiPrice platform adheres to rigorous security standards to protect sensitive pricing algorithms and user data:

1. **Client-Side Audio Processing:** All initial Speech-to-Text (ASR) transcription occurs natively within the browser using secure Web APIs. Raw audio streams are never transmitted directly to the proprietary backend, strictly minimizing the payload size and protecting user biometric data.
2. **Ephemeral Transcripts:** The live transcripts (`_liveTranscript`) are explicitly wiped from memory (`clear()`) the moment the state machine transitions, ensuring no accidental leakage of spoken queries into browser caches or diagnostic logs.
3. **Environment Isolation:** All backend endpoints are abstracted away from the UI. The Flutter client operates in a zero-trust model, validating all inputs locally via the SLM layer before forwarding structured JSON to the backend API.
4. **Secure Execution Context:** The Web Speech API strictly requires HTTPS or a secure `localhost` context to access the microphone, guaranteeing that man-in-the-middle (MITM) attacks cannot intercept the conversational flow.

## 🚀 Key Features

* **Speech-to-Speech End-to-End:** Utterly hands-free. The system explains all options (e.g., *"I found 3 options. Option 1 is GreenWay..."*) and natively waits for your response.
* **Persistent Voice Engine:** Automatically enforces a high-pitch, premium female voice, overcoming browser limitations and OS-level resets to maintain brand consistency.
* **Dynamic Interruption Handling:** Synchronized event loops prevent Chrome/Safari from breaking the Text-to-Speech engine when microphone hardware streams are released.
* **Simulated Push Notifications:** Provides immediate visual feedback upon verbal booking confirmations.

## 📈 Dynamic Pricing Engine (Logic & Formula)

The core competitive advantage of LogiPrice is its proprietary pricing engine that adjusts rates in real-time based on high-frequency market signals.

### Core Formula: $P = (B \times D \times F \times T) + M$

*   **P (Final Price):** The real-time quote delivered to the user.
*   **B (Base Cost):** Distance (km) × Carrier Base Rate × Route Complexity Index.
*   **D (Demand Multiplier):** Real-time corridor demand surge (e.g., higher rates for peak seasons on Mumbai-Delhi routes).
*   **F (Fuel Index):** Automated adjustments tied to regional fuel price indices.
*   **T (Traffic/Weather Factor):** A composite score derived from live weather (Monsoon/Snow) and metropolitan traffic congestion indices.
*   **M (Margin):** An adaptive margin that fluctuates (3% to 15%) based on supply availability and customer priority.

---

## 🚀 Demo & Walkthrough

### 1. The Activation Flow
Due to browser security protocols, voice-first apps require an initial user interaction. LogiPrice handles this with a premium **Start Assistant** overlay.
- **Action:** Click "Start Assistant".
- **Result:** Initializes the secure audio context and triggers the **Female Greeting**.

### 2. Inquiry Phase
- **Utterance:** *"Ship 2 tons of electronics from Mumbai to Delhi urgently."*
- **Processing:** The SLM extracts the intent. The Dynamic Pricing Engine calculates rates for multiple carriers (e.g., GreenWay, ExpressLink).
- **Feedback:** The assistant verbally summarizes every option: *"I found 3 options. Option 1 is with GreenWay for ₹57,400..."*

### 3. Selection & Booking
- **Utterance:** *"Book the first one."*
- **Action:** The system matches "first one" to Option 1 and transitions to the **Booking Screen**.
- **Confirmation:** A push notification drops down visually while the voice confirms: *"Booking confirmed! I have sent the tracking details to your email."*

---

## 🛠️ Setup & Execution

### Prerequisites
- Flutter SDK (Stable)
- Python 3.9+
- Chrome Browser (Recommended for Web Speech API)

### 1. Start the Backend Services
```bash
cd backend/gateway
uvicorn main:app --reload --port 8000
```
*(Ensure all microservices in `backend/services` are running if in production mode).*

### 2. Start the Flutter Web App
```bash
cd flutter_app
flutter pub get
flutter run -d chrome --web-port 3000
```

### 3. Testing in Incognito
If testing in Incognito mode, ensure you click the screen once to allow the "Audio Autoplay" policy to activate the greeting.
