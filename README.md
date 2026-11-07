# Noto Notes

A native iPhone notebook for filing entries under the day they belong to. Notes, search, calendar browsing, editing, and native spelling work locally. Cloud proofreading and rewriting require a configured service and explicit consent.

## Run the iPhone app

Open `NotoNotes.xcodeproj` in Xcode 16 or newer on macOS. Select the shared NotoNotes scheme and an iPhone simulator running iOS 17 or newer, then Run. For a physical iPhone, select your signing team and an available bundle identifier in Signing & Capabilities. The editor supports system spelling dictionaries, plain text, and Markdown heading and list prefixes.

Tap the date at the top of a note to file it in the past. Its filing day stays fixed when travelling. Actual creation and editing timestamps are available under Note options → Note information. Long-press a library row to duplicate, pin, or delete it. Restore deleted notes or export the library from Settings.

## Deploy the writing service

Use Node 24 or the included Dockerfile. From the backend directory run `docker build -t noto-writing .`. Set OPENAI_API_KEY, OPENAI_MODEL (a Chat Completions model supporting strict JSON Schema), and SERVICE_TOKEN (a private randomly generated token of at least 32 characters) in your hosting platform’s secrets store. Start the container with those environment variables, expose port 8080 behind an HTTPS reverse proxy, and restrict access to trusted notebook users. Example for local testing with variables already exported:

```sh
docker run --rm -p 127.0.0.1:8080:8080 -e SERVICE_TOKEN -e OPENAI_API_KEY -e OPENAI_MODEL noto-writing
```

In Settings enter the HTTPS base URL and the service token, tap Save token, and enable cloud writing. The token is stored in the device Keychain. The model provider key stays on the server. This deployment uses a shared access token and a per-process limit of 30 authenticated requests per minute for a personal or small trusted deployment. Rotate the token by updating the service and each client. Keep request-body logging disabled at the proxy. The service sends the passage to OpenAI with storage disabled; provider retention policies also apply.

Automatic mode sends the edited paragraph after a typing pause. Selection actions send only the selection. Whole-note actions send the note body. Suggestions expire when the text changes. Review the original, replacement, and explanation before accepting. The app supports English, Dari, Persian, and Pashto writing; native spelling availability depends on the installed keyboard and dictionary.

## Verify

Run `npm ci`, `npm run check`, and `npm test` in backend. On macOS start `node ci/fixture.mjs` from the project root and use Xcode’s Test action. The simulator UI test selects the loopback fixture only in Debug. The GitHub Actions workflow builds the server container, runs the backend checks, and runs XCTest on an available iPhone simulator. Its result bundle includes UI test diagnostics. No provider credentials are required for CI.

GitHub Actions provides the macOS build environment when developing on Windows. Real-device signing, hosting a live service, and App Store distribution require owner configuration.
