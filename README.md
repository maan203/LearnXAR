# LearnXAR

**Enhancing Learning with Augmented Reality and Personalization**

LearnXAR is an Android learning app that helps computer science students understand Data Structures and Algorithms (DSA). It combines interactive AR visualizations (built in Unity) with AI-personalized lesson content (Google Gemini). Each student's quiz, reading and AR activity feeds a learning-level estimate, and that estimate decides how their lessons are rewritten.

> Final Year Project, BS Computer Science (2022–2026), Department of Computer Science, Air University Aerospace & Aviation Campus, Kamra.
> Supervisor: Dr. Tufail Muhammad

---

## The problem

DSA concepts such as stacks, linked lists, trees and sorting algorithms are abstract and hard to picture from text and static diagrams. Students also learn at different speeds, but most material is written for a single audience. LearnXAR addresses both problems. Students can watch the structures operate in AR, and the explanations adapt to how each student is performing.

## Features

### Learning modules
Eight modules with subtopics:

| # | Module | Subtopics |
|---|--------|-----------|
| 1 | Introduction | — |
| 2 | Arrays | 1D, 2D, Multi-Dimensional |
| 3 | Linked List | Singly, Doubly, Circular |
| 4 | Stack | — |
| 5 | Queue | — |
| 6 | Searching | Linear Search, Binary Search |
| 7 | Sorting | Bubble, Selection, Insertion, Merge, Quick |
| 8 | Trees | Binary Trees, Binary Search Tree, AVL Trees |

### AI-personalized content
- Base lesson content is loaded from Cloud Firestore.
- Gemini rewrites it into 5 sections for the student's level: **Beginner**, **Intermediate** or **Advanced**. Beginner uses analogies and no code, Intermediate adds pseudocode and complexity, and Advanced covers trade-offs and edge cases.
- The student's predicted level is selected by default, and they can switch levels manually.
- Generated content is cached in memory and in Firestore to avoid repeat API calls. If Gemini fails, the app falls back to the base content.

### AR visualization
- Each module/subtopic launches its own Unity AR scene (ARCore) through a Flutter to Android `MethodChannel`.
- AR session time is tracked. Sessions interrupted by closing Unity are recovered when the app resumes.

### Adaptive quizzes
- MCQ quizzes loaded from Firestore, with difficulty that adapts during the quiz (easy / medium / hard).
- Score, time taken, attempt number and difficulty reached are recorded.
- The results screen shows an answer review and short AI-generated feedback on the questions the student got wrong.

### Level prediction
The app uses a rule-based classifier, not a trained ML model:
- **Per module:** a base level is set from the quiz score. Upgrade and downgrade signals then adjust it, such as a fast and accurate quiz, improvement across attempts, heavy AR/reading time paired with a low score, or signs of guessing. The adjustment is capped at ±1 level.
- **Global level:** a weighted score across all 8 modules (quiz 60%, reading time 25%, AR time 15%).

### Engagement and profile
- Home dashboard with progress overview and recent activity feed
- Insights tab with learning stats and level breakdown
- Daily streaks, achievements/badges (e.g. *First Step*, *Perfectionist*, *AR Enthusiast*, *DSA Champion*) and sound effects
- Scheduled local notifications (daily reminders, streak alerts)
- Profile with photo upload, light/dark mode and password reset
- Email/password authentication with Firebase Auth

## Tech stack

| Layer | Technology |
|-------|------------|
| Mobile UI | Flutter (Dart) |
| AR | Unity 2022.3 + AR Foundation / ARCore, exported as `unityLibrary` |
| Auth | Firebase Authentication |
| Database | Cloud Firestore |
| AI personalization | Google Gemini API (`gemini-flash-latest`) |
| Local storage | shared_preferences |
| Other | flutter_local_notifications, audioplayers, image_picker |

## Architecture

```
┌──────────────────────── Flutter app (lib/) ────────────────────────┐
│ screens/  login · signup · home · learn · module detail · quiz     │
│           quiz result · insights · profile                         │
│ services/ auth · gemini · streak · achievement · notification      │
└──────┬──────────────────────┬──────────────────────┬───────────────┘
       │ MethodChannel        │ HTTPS                │ Firebase SDK
       ▼ com.learnxar/        ▼                      ▼
  ar_launcher            Gemini API            Firebase Auth +
  (MainActivity.kt)      (content rewrite,     Cloud Firestore
       │                  quiz feedback)       (users, progress,
       ▼                                        modules, quizzes)
  UnityPlayerActivity
  (unityLibrary – AR scenes)
```

### Firestore collections used
- `users/{uid}`: profile and `predictedLevel`, with subcollections `moduleProgress`, `quizAttempts`, `arSessions`, `readingSessions`, `activities`, `contentCache`
- `modules/{moduleKey}/sections`: base lesson content
- `quizzes/{moduleKey}/questions`: quiz questions

## Project structure

```
lib/
├── main.dart              # App entry, Firebase init, AR session recovery
├── config/                # secrets.example.dart (copy to secrets.dart)
├── screens/               # All UI screens
├── services/              # Auth, Gemini, streaks, achievements, notifications, sound
├── utils/                 # Colours, helpers
└── widgets/
android/                   # Flutter Android host (MainActivity launches Unity)
unityLibrary/              # Exported Unity AR project (IL2CPP, arm64-v8a / armeabi-v7a)
assets/                    # App icon and sound effects
```

## Getting started

### Prerequisites
- Flutter SDK (Dart ≥ 3.0)
- Android Studio with Android SDK and NDK
- An ARCore-supported Android device (Android 8.0+ recommended)
- A Firebase project and a Gemini API key

### 1. Clone and install dependencies
```bash
git clone https://github.com/maan203/LearnXAR.git
cd LearnXAR
flutter pub get
```

### 2. Add the Gemini API key
```bash
cp lib/config/secrets.example.dart lib/config/secrets.dart
```
Then put your key in `lib/config/secrets.dart`. This file is gitignored.

### 3. Configure Firebase
1. Create a Firebase project and add an Android app with package name `com.example.learnxar_app`.
2. Enable **Email/Password** authentication and **Cloud Firestore**.
3. Download `google-services.json` into `android/app/`. This file is gitignored.
4. Seed Firestore with lesson content (`modules/…/sections`) and questions (`quizzes/…/questions`) for each module key listed above.

### 4. Unity library
`unityLibrary/build.gradle` sets `ndkPath` to a local Unity install (Unity 2022.3.62f1). Update it to match your machine, or remove it to use the Android SDK's NDK.

### 5. Run
```bash
flutter run
```
AR works only on a physical ARCore-capable device, not on an emulator.

## Known limitations
- **The Gemini API key is compiled into the client.** The SRS (NFR-SEC-3) requires keys not to be exposed client-side. A production build should route Gemini calls through a backend such as Firebase Cloud Functions.
- Lesson content and quiz questions live in Firestore and are not included in this repository.
- Only the exported Unity build (`unityLibrary`) is included, not the Unity editor project.
- Android only. The iOS/web/desktop folders are default Flutter scaffolding and have not been set up.

---

This repository is maintained by **Mahnoor Awan** ([@maan203](https://github.com/maan203)).
