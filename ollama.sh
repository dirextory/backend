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
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = "http://127.0.0.1:11434"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_error_json(self, message, status=500):
        body = json.dumps({"error": message}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length))

    def stream_ollama(self, endpoint, payload):
        request = urllib.request.Request(
            OLLAMA + endpoint,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )

        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                self.send_response(200)
                self.send_header("Content-Type", "application/x-ndjson")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
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
                self.stream_ollama("/api/generate", self.read_json())
            except Exception as error:
                self.send_error_json(str(error))
            return

        if self.path == "/api/pull":
            try:
                self.stream_ollama("/api/pull", self.read_json())
            except Exception as error:
                self.send_error_json(str(error))
            return

        self.send_error_json("Not found", 404)

    def do_GET(self):
        if self.path == "/api/health":
            body = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        filename = (
            "public/index.html"
            if self.path in ("/", "/index.html")
            else "public" + self.path
        )

        if not os.path.isfile(filename):
            self.send_error_json("Not found", 404)
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


print("crypted AI running on port 8000")
ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
PY

cat > public/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>crypted AI</title>

<style>
:root {
  color-scheme: dark;
  --bg:#080808;
  --panel:rgba(20,20,20,.88);
  --line:rgba(255,255,255,.14);
  --text:#f5f5f5;
  --muted:#929292;
}

* { box-sizing:border-box; }

html,body {
  width:100%;
  height:100%;
  margin:0;
}

body {
  overflow:hidden;
  background:var(--bg);
  color:var(--text);
  font-family:Inter,system-ui,sans-serif;
}

button,textarea,select {
  font:inherit;
}

button,select {
  cursor:pointer;
}

#snow {
  position:fixed;
  inset:0;
  z-index:-1;
  pointer-events:none;
}

.app {
  width:100%;
  height:100dvh;
  display:flex;
  flex-direction:column;
}

header {
  height:58px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  padding:0 22px;
  border-bottom:1px solid var(--line);
  background:rgba(8,8,8,.7);
  backdrop-filter:blur(12px);
}

.brand {
  font-weight:800;
  letter-spacing:-.05em;
}

.brand span {
  color:var(--muted);
  font-weight:400;
}

.header-button {
  padding:6px 10px;
  border:1px solid var(--line);
  border-radius:8px;
  background:transparent;
  color:var(--muted);
  font-size:.75rem;
}

#messages {
  flex:1;
  width:min(100%,920px);
  margin:auto;
  padding:34px 22px 24px;
  overflow-y:auto;
  scrollbar-color:#555 transparent;
}

.welcome {
  max-width:620px;
  margin:13vh auto 0;
  text-align:center;
}

.welcome h1 {
  margin:0;
  font-size:clamp(2.8rem,9vw,6rem);
  line-height:.9;
  letter-spacing:-.09em;
}

.welcome p {
  color:var(--muted);
  line-height:1.6;
}

.message {
  max-width:82%;
  margin-bottom:16px;
  padding:12px 15px;
  border:1px solid var(--line);
  border-radius:14px;
  background:#1d1d1d;
  line-height:1.6;
  overflow-wrap:anywhere;
}

.message.user {
  margin-left:auto;
  background:#fff;
  color:#111;
  border-color:#fff;
}

.message.error {
  color:#ffb5b5;
  border-color:#875555;
}

.message pre {
  overflow-x:auto;
  padding:12px;
  border-radius:8px;
  background:#090909;
  color:#eee;
  white-space:pre;
  font:13px/1.5 monospace;
}

.message code {
  padding:2px 4px;
  border-radius:4px;
  background:#333;
  font: .9em monospace;
}

.message pre code {
  padding:0;
  background:none;
}

.attachment {
  display:block;
  margin-bottom:7px;
  color:#777;
  font-size:.75rem;
}

.composer-wrap {
  width:min(100%,920px);
  margin:auto;
  padding:8px 22px 16px;
}

.progress {
  display:none;
  align-items:center;
  gap:10px;
  height:27px;
  color:var(--muted);
  font-size:.75rem;
}

.progress.visible {
  display:flex;
}

progress {
  width:180px;
  height:5px;
  accent-color:white;
}

.composer {
  display:flex;
  align-items:center;
  gap:7px;
  padding:6px;
  border:1px solid var(--line);
  border-radius:13px;
  background:var(--panel);
  backdrop-filter:blur(14px);
}

textarea {
  flex:1;
  min-width:0;
  height:30px;
  max-height:120px;
  resize:none;
  padding:5px 7px;
  border:0;
  outline:0;
  background:transparent;
  color:var(--text);
  line-height:20px;
}

select,.attach,.send {
  height:31px;
  border-radius:8px;
}

select {
  max-width:155px;
  padding:0 7px;
  border:1px solid var(--line);
  background:#111;
  color:var(--text);
  font-size:.75rem;
}

.attach {
  width:33px;
  border:1px solid var(--line);
  background:transparent;
  color:#bbb;
}

.send {
  padding:0 13px;
  border:0;
  background:white;
  color:#111;
  font-size:.78rem;
  font-weight:800;
}

button:disabled {
  opacity:.45;
  cursor:wait;
}

.file-name {
  margin-top:4px;
  color:var(--muted);
  font-size:.7rem;
}

dialog {
  width:min(420px,calc(100% - 32px));
  border:1px solid var(--line);
  border-radius:15px;
  background:#181818;
  color:var(--text);
}

dialog::backdrop {
  background:rgba(0,0,0,.75);
}

.dialog-close {
  width:100%;
  height:36px;
  border:0;
  border-radius:8px;
  background:#fff;
  color:#111;
}

@media(max-width:650px) {
  header { padding:0 14px; }
  #messages { padding:25px 14px; }
  .composer-wrap { padding:8px 10px 12px; }
  .composer { flex-wrap:wrap; }
  textarea { order:1; flex-basis:calc(100% - 42px); }
  select { order:2; flex:1; max-width:none; }
  .attach,.send { order:2; }
  .message { max-width:94%; }
}
</style>
</head>

<body>
<canvas id="snow"></canvas>

<div class="app">
<header>
  <div class="brand">crypted <span>AI</span></div>
  <button class="header-button" id="clear">Clear chat</button>
</header>

<main id="messages" aria-live="polite">
  <section class="welcome" id="welcome">
    <h1>think privately.</h1>
    <p>
      Your conversations and uploaded files are not saved by crypted AI.
      Select a model and begin.
    </p>
  </section>
</main>

<div class="composer-wrap">
  <div class="progress" id="progress">
    <span id="progress-label">Downloading…</span>
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
    <button class="attach" type="button" id="attach">+</button>
    <textarea id="prompt" placeholder="Message crypted AI…" required></textarea>
    <button class="send" id="send">Send</button>
  </form>

  <div class="file-name" id="file-name"></div>
</div>
</div>

<dialog id="privacy">
  <h2>Your data stays yours.</h2>
  <p>
    crypted AI does not save your conversations or uploaded files.
    Processing happens through Ollama in this Codespace.
  </p>
  <button class="dialog-close" id="close-dialog">Continue</button>
</dialog>

<script>
const messages = document.querySelector("#messages");
const welcome = document.querySelector("#welcome");
const form = document.querySelector("#form");
const promptBox = document.querySelector("#prompt");
const modelBox = document.querySelector("#model");
const send = document.querySelector("#send");
const fileInput = document.querySelector("#file");
const fileName = document.querySelector("#file-name");
const progress = document.querySelector("#progress");
const progressBar = document.querySelector("#progress-bar");
const progressLabel = document.querySelector("#progress-label");
const privacy = document.querySelector("#privacy");

let selectedFile = null;

function addMessage(text, type, attachment="") {
  welcome?.remove();

  const article = document.createElement("article");
  article.className = `message ${type}`;

  if (attachment) {
    const label = document.createElement("span");
    label.className = "attachment";
    label.textContent = attachment;
    article.appendChild(label);
  }

  const content = document.createElement("div");
  content.className = "content";
  content.textContent = text;
  article.appendChild(content);

  messages.appendChild(article);
  messages.scrollTop = messages.scrollHeight;
  return content;
}

function markdown(text) {
  const escaped = text
    .replaceAll("&","&amp;")
    .replaceAll("<","&lt;")
    .replaceAll(">","&gt;");

  const blocks = [];

  const result = escaped.replace(
    /```(\w*)\n?([\s\S]*?)```/g,
    (_, lang, code) => {
      const index = blocks.length;
      blocks.push(
        `<pre><code class="language-${lang || "text"}">${code.trim()}</code></pre>`
      );
      return `___CODE_${index}___`;
    }
  );

  return result
    .replace(/`([^`]+)`/g,"<code>$1</code>")
    .replace(/\*\*(.*?)\*\*/g,"<strong>$1</strong>")
    .replace(/\n/g,"<br>")
    .replace(/___CODE_(\d+)___/g,(_, index) => blocks[index]);
}

function showProgress(label,value=0) {
  const number = Number(value);
  const safe = Number.isFinite(number)
    ? Math.min(100,Math.max(0,number))
    : 0;

  progress.classList.add("visible");
  progressLabel.textContent = label;
  progressBar.value = safe;
}

function hideProgress() {
  progress.classList.remove("visible");
}

async function readStream(response,onLine) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const {value,done} = await reader.read();
    if (done) break;

    buffer += decoder.decode(value,{stream:true});
    const lines = buffer.split("\n");
    buffer = lines.pop();

    for (const line of lines) {
      if (!line.trim()) continue;
      onLine(JSON.parse(line));
    }
  }

  if (buffer.trim()) onLine(JSON.parse(buffer));
}

async function installModel(model) {
  showProgress(`Downloading ${model}…`,0);

  const response = await fetch("/api/pull",{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({model,stream:true})
  });

  if (!response.ok) {
    throw new Error("Could not download the model.");
  }

  await readStream(response,data => {
    if (data.error) throw new Error(data.error);

    const completed = Number(data.completed);
    const total = Number(data.total);

    const percent = Number.isFinite(completed) &&
      Number.isFinite(total) &&
      total > 0
        ? Math.min(100,Math.max(0,
            Math.round(completed / total * 100)))
        : 0;

    showProgress(data.status || `Downloading ${model}…`,percent);
  });

  hideProgress();
}

function fileToBase64(file) {
  return new Promise((resolve,reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(",")[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

document.querySelector("#attach").onclick = () => fileInput.click();

fileInput.onchange = () => {
  selectedFile = fileInput.files[0] || null;
  fileName.textContent = selectedFile
    ? `Attached: ${selectedFile.name}`
    : "";
};

form.onsubmit = async event => {
  event.preventDefault();

  const text = promptBox.value.trim();
  if (!text && !selectedFile) return;

  const model = modelBox.value;
  const file = selectedFile;
  const attachment = file ? `Attached: ${file.name}` : "";

  addMessage(text || "Please inspect this file.","user",attachment);

  promptBox.value = "";
  promptBox.style.height = "30px";
  selectedFile = null;
  fileInput.value = "";
  fileName.textContent = "";
  send.disabled = true;

  const output = addMessage(`Preparing ${model}…`,"assistant");

  try {
    let finalPrompt = text || "Please inspect the attached file.";
    const payload = {model,prompt:finalPrompt,stream:true};

    if (file && file.type.startsWith("image/")) {
      payload.images = [await fileToBase64(file)];
    } else if (file) {
      finalPrompt += `\n\nFile: ${file.name}\n\`\`\`\n${await file.text()}\n\`\`\``;
      payload.prompt = finalPrompt;
    }

    await installModel(model);

    output.textContent = "";
    const response = await fetch("/api/generate",{
      method:"POST",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify(payload)
    });

    if (!response.ok) throw new Error("Generation failed.");

    let answer = "";

    await readStream(response,data => {
      if (data.error) throw new Error(data.error);

      answer += data.response || "";
      output.innerHTML = markdown(answer);
      messages.scrollTop = messages.scrollHeight;
    });
  } catch (error) {
    output.parentElement.classList.add("error");
    output.textContent = error.message;
  } finally {
    hideProgress();
    send.disabled = false;
    promptBox.focus();
  }
};

promptBox.onkeydown = event => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    form.requestSubmit();
  }
};

promptBox.oninput = () => {
  promptBox.style.height = "30px";
  promptBox.style.height = `${Math.min(promptBox.scrollHeight,120)}px`;
};

document.querySelector("#clear").onclick = () => {
  messages.innerHTML = "";
  messages.appendChild(welcome);
  welcome.style.display = "block";
};

if (!sessionStorage.getItem("privacy-shown")) {
  privacy.showModal();
  sessionStorage.setItem("privacy-shown","1");
}

document.querySelector("#close-dialog").onclick = () => privacy.close();

const canvas = document.querySelector("#snow");
const ctx = canvas.getContext("2d");
let flakes = [];

function resizeSnow() {
  const ratio = devicePixelRatio || 1;
  canvas.width = innerWidth * ratio;
  canvas.height = innerHeight * ratio;
  ctx.setTransform(ratio,0,0,ratio,0,0);

  flakes = Array.from(
    {length:Math.min(120,Math.floor(innerWidth / 8))},
    () => ({
      x:Math.random() * innerWidth,
      y:Math.random() * innerHeight,
      r:Math.random() * 2 + .4,
      speed:Math.random() * .55 + .2,
      drift:(Math.random() - .5) * .25
    })
  );
}

function animateSnow() {
  ctx.clearRect(0,0,innerWidth,innerHeight);
  ctx.fillStyle = "rgba(255,255,255,.6)";

  for (const flake of flakes) {
    flake.y += flake.speed;
    flake.x += flake.drift;

    if (flake.y > innerHeight + 5) {
      flake.y = -5;
      flake.x = Math.random() * innerWidth;
    }

    ctx.beginPath();
    ctx.arc(flake.x,flake.y,flake.r,0,Math.PI * 2);
    ctx.fill();
  }

  requestAnimationFrame(animateSnow);
}

addEventListener("resize",resizeSnow);
resizeSnow();
animateSnow();
</script>
</body>
</html>
HTML

cd "$APP"
nohup python3 server.py > server.log 2>&1 &

echo
echo "crypted AI is running on port 8000."
echo "Open port 8000 in the Codespaces Ports panel."
