#!/usr/bin/env bash
set -e

echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

pkill ollama 2>/dev/null || true
pkill -f "crypted-ai/server.py" 2>/dev/null || true

export OLLAMA_ORIGINS="*"
nohup env OLLAMA_ORIGINS="*" ollama serve > "$HOME/ollama.log" 2>&1 &

sleep 5

APP="$HOME/crypted-ai"
mkdir -p "$APP/public"
cd "$APP"

cat > server.py <<'PY'
import json
import os
import subprocess
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = "http://127.0.0.1:11434"


def post_ollama(path, payload):
    request = urllib.request.Request(
        OLLAMA + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    return urllib.request.urlopen(request, timeout=900)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length))

    def stream_json_lines(self, path, payload):
        try:
            response = post_ollama(path, payload)
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            while True:
                line = response.readline()
                if not line:
                    break
                self.wfile.write(line)
                self.wfile.flush()

        except Exception as error:
            try:
                self.wfile.write(
                    (json.dumps({"error": str(error)}) + "\n").encode()
                )
                self.wfile.flush()
            except Exception:
                pass

    def do_POST(self):
        if self.path == "/api/generate":
            try:
                data = self.read_body()
                self.stream_json_lines("/api/generate", data)
            except Exception as error:
                self.send_json({"error": str(error)}, 500)
            return

        if self.path == "/api/pull":
            try:
                data = self.read_body()
                self.stream_json_lines("/api/pull", data)
            except Exception as error:
                self.send_json({"error": str(error)}, 500)
            return

        self.send_json({"error": "Not found"}, 404)

    def do_GET(self):
        if self.path == "/api/models":
            try:
                result = subprocess.run(
                    ["ollama", "list"],
                    capture_output=True,
                    text=True,
                )
                models = []

                for line in result.stdout.splitlines()[1:]:
                    parts = line.split()
                    if parts:
                        models.append(parts[0])

                self.send_json({"models": models})
            except Exception as error:
                self.send_json({"error": str(error)}, 500)
            return

        if self.path == "/api/health":
            self.send_json({"ok": True})
            return

        if self.path == "/" or self.path == "/index.html":
            filename = "public/index.html"
        else:
            filename = "public" + self.path

        if not os.path.isfile(filename):
            self.send_json({"error": "Not found"}, 404)
            return

        content_type = "text/html; charset=utf-8"
        if filename.endswith(".css"):
            content_type = "text/css"
        elif filename.endswith(".js"):
            content_type = "text/javascript"

        with open(filename, "rb") as file:
            content = file.read()

        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)


print("crypted AI is running on port 8000")
ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
PY

cat > public/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="theme-color" content="#080808">
  <title>crypted AI</title>

  <style>
    :root {
      color-scheme: dark;
      --bg: #080808;
      --surface: rgba(20,20,20,.86);
      --surface-2: #1d1d1d;
      --line: rgba(255,255,255,.14);
      --text: #f5f5f5;
      --muted: #929292;
      --white: #fff;
      --radius: 12px;
    }

    * {
      box-sizing: border-box;
    }

    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
    }

    body {
      overflow: hidden;
      background:
        radial-gradient(circle at 50% -20%, #343434, transparent 42%),
        var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, sans-serif;
    }

    button, textarea, select {
      font: inherit;
    }

    button, select {
      cursor: pointer;
    }

    #snow {
      position: fixed;
      inset: 0;
      z-index: -1;
      pointer-events: none;
    }

    .app {
      width: 100%;
      height: 100dvh;
      display: flex;
      flex-direction: column;
    }

    header {
      height: 64px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 24px;
      border-bottom: 1px solid var(--line);
      background: rgba(8,8,8,.65);
      backdrop-filter: blur(14px);
    }

    .brand {
      font-size: 1.05rem;
      font-weight: 800;
      letter-spacing: -.04em;
    }

    .brand span {
      color: var(--muted);
      font-weight: 500;
    }

    .header-actions {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .header-button {
      padding: 7px 11px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: transparent;
      color: var(--muted);
      font-size: .75rem;
    }

    .header-button:hover {
      color: var(--text);
      border-color: #777;
    }

    #messages {
      flex: 1;
      width: min(100%, 920px);
      margin: 0 auto;
      padding: 42px 24px 32px;
      overflow-y: auto;
      overscroll-behavior: contain;
      scrollbar-color: #555 transparent;
    }

    .welcome {
      max-width: 620px;
      margin: 13vh auto 0;
      text-align: center;
    }

    .welcome h1 {
      margin: 0;
      font-size: clamp(2.7rem, 9vw, 6rem);
      line-height: .9;
      letter-spacing: -.09em;
    }

    .welcome p {
      margin: 22px auto;
      max-width: 470px;
      color: var(--muted);
      line-height: 1.6;
    }

    .message {
      max-width: 82%;
      margin: 0 0 18px;
      padding: 13px 16px;
      border: 1px solid var(--line);
      border-radius: 15px;
      background: var(--surface-2);
      line-height: 1.6;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }

    .message.user {
      margin-left: auto;
      background: var(--white);
      color: #111;
      border-color: var(--white);
    }

    .message.error {
      border-color: #8c5555;
      color: #ffbaba;
    }

    .message pre {
      margin: 12px 0 2px;
      padding: 13px;
      overflow-x: auto;
      border: 1px solid var(--line);
      border-radius: 9px;
      background: #0a0a0a;
      color: #eee;
      white-space: pre;
      font: .84rem/1.55 ui-monospace, SFMono-Regular, Consolas, monospace;
    }

    .message code {
      padding: 2px 5px;
      border-radius: 4px;
      background: #333;
      font: .9em ui-monospace, monospace;
    }

    .message pre code {
      padding: 0;
      background: transparent;
    }

    .attachment {
      display: block;
      margin-bottom: 9px;
      color: #777;
      font-size: .75rem;
    }

    .composer-wrap {
      width: min(100%, 920px);
      margin: 0 auto;
      padding: 10px 24px 18px;
    }

    .progress {
      display: none;
      height: 28px;
      align-items: center;
      gap: 10px;
      color: var(--muted);
      font-size: .75rem;
    }

    .progress.visible {
      display: flex;
    }

    progress {
      width: 180px;
      height: 5px;
      accent-color: white;
    }

    .composer {
      display: flex;
      align-items: center;
      gap: 7px;
      padding: 7px;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: var(--surface);
      backdrop-filter: blur(16px);
    }

    textarea {
      flex: 1;
      min-width: 0;
      height: 30px;
      max-height: 130px;
      resize: none;
      padding: 5px 7px;
      border: 0;
      outline: 0;
      background: transparent;
      color: var(--text);
      line-height: 20px;
    }

    textarea::placeholder {
      color: #777;
    }

    select, .icon-button, .send-button {
      height: 32px;
      border-radius: 8px;
    }

    select {
      max-width: 155px;
      padding: 0 8px;
      border: 1px solid var(--line);
      outline: 0;
      background: #111;
      color: var(--text);
      font-size: .75rem;
    }

    .icon-button {
      width: 34px;
      border: 1px solid var(--line);
      background: transparent;
      color: #bbb;
      font-size: 1rem;
    }

    .icon-button:hover {
      color: white;
      border-color: #777;
    }

    .send-button {
      padding: 0 13px;
      border: 0;
      background: white;
      color: #111;
      font-size: .78rem;
      font-weight: 800;
    }

    button:disabled {
      opacity: .45;
      cursor: wait;
    }

    .file-name {
      max-width: 200px;
      margin: 5px 2px 0;
      overflow: hidden;
      color: var(--muted);
      font-size: .7rem;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    dialog {
      width: min(420px, calc(100% - 32px));
      border: 1px solid var(--line);
      border-radius: 16px;
      background: #181818;
      color: var(--text);
      box-shadow: 0 25px 100px #000;
    }

    dialog::backdrop {
      background: rgba(0,0,0,.72);
      backdrop-filter: blur(5px);
    }

    dialog h2 {
      margin: 0 0 10px;
      letter-spacing: -.04em;
    }

    dialog p {
      color: var(--muted);
      line-height: 1.6;
    }

    .dialog-close {
      width: 100%;
      height: 38px;
      margin-top: 10px;
      border: 0;
      border-radius: 9px;
      background: white;
      color: #111;
      font-weight: 700;
    }

    @media (max-width: 650px) {
      header {
        padding: 0 14px;
      }

      #messages {
        padding: 28px 14px 20px;
      }

      .composer-wrap {
        padding: 8px 10px 12px;
      }

      .composer {
        flex-wrap: wrap;
      }

      textarea {
        order: 1;
        flex-basis: calc(100% - 43px);
      }

      .icon-button {
        order: 1;
      }

      select {
        order: 2;
        flex: 1;
        max-width: none;
      }

      .send-button {
        order: 2;
      }

      .message {
        max-width: 94%;
      }
    }

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation: none !important;
        transition: none !important;
      }
    }
  </style>
</head>

<body>
  <canvas id="snow" aria-hidden="true"></canvas>

  <div class="app">
    <header>
      <div class="brand">crypted <span>AI</span></div>
      <div class="header-actions">
        <button class="header-button" id="privacy-button">Privacy</button>
        <button class="header-button" id="clear-button">Clear chat</button>
      </div>
    </header>

    <main id="messages" aria-live="polite">
      <section class="welcome" id="welcome">
        <h1>think privately.</h1>
        <p>
          Choose a model and start a conversation. Your chat data is not saved
          by crypted AI.
        </p>
      </section>
    </main>

    <div class="composer-wrap">
      <div class="progress" id="progress">
        <span id="progress-label">Downloading model…</span>
        <progress id="progress-bar" max="100" value="0"></progress>
      </div>

      <form class="composer" id="form">
        <select id="model" aria-label="Choose model">
          <option value="llama3.2:3b">Llama 3.2 · 3B</option>
          <option value="qwen2.5:3b">Qwen 2.5 · 3B</option>
          <option value="gemma3:4b">Gemma 3 · 4B</option>
          <option value="mistral:7b">Mistral · 7B</option>
          <option value="phi3:mini">Phi 3 Mini</option>
          <option value="deepseek-r1:7b">DeepSeek R1 · 7B</option>
          <option value="llava:7b">Llava · Vision</option>
        </select>

        <input id="file" type="file" hidden accept="image/*,.txt,.md,.js,.py,.html,.css,.json,.csv">
        <button class="icon-button" id="file-button" type="button" title="Attach file">＋</button>

        <textarea id="prompt" rows="1" placeholder="Message crypted AI…" required></textarea>
        <button class="send-button" id="send" type="submit">Send</button>
      </form>

      <div class="file-name" id="file-name"></div>
    </div>
  </div>

  <dialog id="privacy-dialog">
    <h2>Your data stays yours.</h2>
    <p>
      crypted AI does not save your conversations or uploaded files.
      Requests are processed by Ollama running in this environment.
      Clearing or closing the page removes the visible chat.
    </p>
    <button class="dialog-close" id="dialog-close">Continue</button>
  </dialog>

  <script>
    const messages = document.querySelector("#messages");
    const welcome = document.querySelector("#welcome");
    const form = document.querySelector("#form");
    const promptBox = document.querySelector("#prompt");
    const modelBox = document.querySelector("#model");
    const sendButton = document.querySelector("#send");
    const fileInput = document.querySelector("#file");
    const fileButton = document.querySelector("#file-button");
    const fileName = document.querySelector("#file-name");
    const progress = document.querySelector("#progress");
    const progressBar = document.querySelector("#progress-bar");
    const progressLabel = document.querySelector("#progress-label");
    const privacyDialog = document.querySelector("#privacy-dialog");

    let selectedFile = null;

    function addMessage(text, type, attachment = "") {
      welcome?.remove();

      const element = document.createElement("article");
      element.className = `message ${type}`;

      if (attachment) {
        const attachmentElement = document.createElement("span");
        attachmentElement.className = "attachment";
        attachmentElement.textContent = attachment;
        element.appendChild(attachmentElement);
      }

      const content = document.createElement("div");
      content.className = "content";
      content.textContent = text;
      element.appendChild(content);

      messages.appendChild(element);
      messages.scrollTop = messages.scrollHeight;
      return content;
    }

    function renderMarkdown(text) {
      const escaped = text
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");

      const blocks = [];
      const withoutBlocks = escaped.replace(
        /```(\w*)\n?([\s\S]*?)```/g,
        (_, language, code) => {
          const index = blocks.length;
          blocks.push(
            `<pre><code class="language-${language || "text"}">${code.trim()}</code></pre>`
          );
          return `@@CODE${index}@@`;
        }
      );

      return withoutBlocks
        .replace(/`([^`]+)`/g, "<code>$1</code>")
        .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
        .replace(/\n/g, "<br>")
        .replace(/@@CODE(\d+)@@/g, (_, index) => blocks[index]);
    }

    function showProgress(label, value = 0) {
      progress.classList.add("visible");
      progressLabel.textContent = label;
      progressBar.value = value;
    }

    function hideProgress() {
      progress.classList.remove("visible");
    }

    async function readStream(response, onLine) {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop();

        for (const line of lines) {
          if (line.trim()) onLine(JSON.parse(line));
        }
      }
    }

    async function installModel(model) {
      showProgress(`Downloading ${model}…`, 0);

      const response = await fetch("/api/pull", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model, stream: true })
      });

      if (!response.ok) throw new Error("Could not download the model.");

      await readStream(response, data => {
        if (data.error) throw new Error(data.error);

        const percent = data.total
          ? Math.round((data.completed / data.total) * 100)
          : 0;

        showProgress(data.status || `Downloading ${model}…`, percent);
      });

      hideProgress();
    }

    async function generate(model, prompt, output) {
      const response = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          prompt,
          stream: true
        })
      });

      if (!response.ok) throw new Error("Generation failed.");

      let answer = "";

      await readStream(response, data => {
        if (data.error) throw new Error(data.error);
        answer += data.response || "";
        output.innerHTML = renderMarkdown(answer);
        messages.scrollTop = messages.scrollHeight;
      });
    }

    fileButton.addEventListener("click", () => fileInput.click());

    fileInput.addEventListener("change", () => {
      selectedFile = fileInput.files[0] || null;
      fileName.textContent = selectedFile
        ? `Attached: ${selectedFile.name}`
        : "";
    });

    form.addEventListener("submit", async event => {
      event.preventDefault();

      const text = promptBox.value.trim();
      if (!text && !selectedFile) return;

      const model = modelBox.value;
      const file = selectedFile;
      const attachment = file ? `Attached: ${file.name}` : "";

      addMessage(text || "Please inspect this file.", "user", attachment);
      promptBox.value = "";
      promptBox.style.height = "30px";
      selectedFile = null;
      fileInput.value = "";
      fileName.textContent = "";
      sendButton.disabled = true;

      const output = addMessage(`Preparing ${model}…`, "assistant");

      try {
        // Text files are included in the prompt.
        let finalPrompt = text;

        if (file && !file.type.startsWith("image/")) {
          const fileText = await file.text();
          finalPrompt += `\n\nFile: ${file.name}\n\`\`\`\n${fileText}\n\`\`\``;
        }

        // Ollama vision models can receive images through its native API,
        // but this simple text proxy displays the upload and sends the text.
        if (file && file.type.startsWith("image/")) {
          finalPrompt += `\n\nThe user attached an image named ${file.name}.`;
        }

        try {
          await installModel(model);
        } catch (error) {
          // Pulling an already-installed model can return a harmless error.
          if (!String(error.message).toLowerCase().includes("already")) {
            throw error;
          }
        }

        output.textContent = "";
        await generate(model, finalPrompt, output);
      } catch (error) {
        output.className = "content";
        output.parentElement.classList.add("error");
        output.textContent = error.message;
      } finally {
        sendButton.disabled = false;
        promptBox.focus();
      }
    });

    promptBox.addEventListener("keydown", event => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        form.requestSubmit();
      }
    });

    promptBox.addEventListener("input", () => {
      promptBox.style.height = "30px";
      promptBox.style.height = `${Math.min(promptBox.scrollHeight, 130)}px`;
    });

    document.querySelector("#clear-button").addEventListener("click", () => {
      messages.innerHTML = "";
      messages.appendChild(welcome);
      welcome.style.display = "block";
    });

    document.querySelector("#privacy-button").addEventListener("click", () => {
      privacyDialog.showModal();
    });

    document.querySelector("#dialog-close").addEventListener("click", () => {
      privacyDialog.close();
    });

    if (!localStorage.getItem("crypted-ai-privacy-seen")) {
      privacyDialog.showModal();
      localStorage.setItem("crypted-ai-privacy-seen", "1");
    }

    // Snow background.
    const canvas = document.querySelector("#snow");
    const ctx = canvas.getContext("2d");
    let flakes = [];

    function resizeSnow() {
      const ratio = devicePixelRatio || 1;
      canvas.width = innerWidth * ratio;
      canvas.height = innerHeight * ratio;
      canvas.style.width = `${innerWidth}px`;
      canvas.style.height = `${innerHeight}px`;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);

      flakes = Array.from(
        { length: Math.min(120, Math.floor(innerWidth / 8)) },
        () => ({
          x: Math.random() * innerWidth,
          y: Math.random() * innerHeight,
          r: Math.random() * 2 + .4,
          speed: Math.random() * .55 + .2,
          drift: (Math.random() - .5) * .25
        })
      );
    }

    function animateSnow() {
      ctx.clearRect(0, 0, innerWidth, innerHeight);
      ctx.fillStyle = "rgba(255,255,255,.6)";

      for (const flake of flakes) {
        flake.y += flake.speed;
        flake.x += flake.drift;

        if (flake.y > innerHeight + 5) {
          flake.y = -5;
          flake.x = Math.random() * innerWidth;
        }

        ctx.beginPath();
        ctx.arc(flake.x, flake.y, flake.r, 0, Math.PI * 2);
        ctx.fill();
      }

      requestAnimationFrame(animateSnow);
    }

    addEventListener("resize", resizeSnow);
    resizeSnow();
    animateSnow();
  </script>
</body>
</html>
HTML

echo "starting crypted AI..."
cd "$APP"
nohup python3 server.py > server.log 2>&1 &

echo
echo "crypted AI is running."
echo "open port 8000 in the Codespaces Ports panel!"
