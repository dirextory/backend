set -e

# install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# stop any old Ollama process
pkill ollama 2>/dev/null || true

# allow the frontend backend to communicate with Ollama
export OLLAMA_ORIGINS="*"

# start ollama
nohup env OLLAMA_ORIGINS="*" ollama serve > ~/ollama.log 2>&1 &

sleep 5

# create project
mkdir -p ~/crypted-ai/public
cd ~/crypted-ai

# create backend
cat > server.py <<'PY'
import json
import os
import subprocess
import urllib.request
from http.server import HTTPServer, SimpleHTTPRequestHandler

OLLAMA = "http://127.0.0.1:11434"

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="public", **kwargs)

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length))

    def do_POST(self):
        if self.path == "/api/chat":
            try:
                data = self.read_json()
                model = data["model"]
                prompt = data["prompt"]

                # Automatically downloads the selected model if necessary.
                installed = subprocess.run(
                    ["ollama", "list"],
                    capture_output=True,
                    text=True
                ).stdout

                if not any(line.startswith(model + " ") for line in installed.splitlines()):
                    pull = subprocess.run(
                        ["ollama", "pull", model],
                        capture_output=True,
                        text=True
                    )

                    if pull.returncode != 0:
                        self.send_json({
                            "error": "Could not install model.",
                            "details": pull.stderr[-1000:]
                        }, 500)
                        return

                request = urllib.request.Request(
                    OLLAMA + "/api/generate",
                    data=json.dumps({
                        "model": model,
                        "prompt": prompt,
                        "stream": False
                    }).encode(),
                    headers={"Content-Type": "application/json"}
                )

                with urllib.request.urlopen(request, timeout=600) as response:
                    result = json.loads(response.read())

                self.send_json({"response": result.get("response", "")})

            except Exception as error:
                self.send_json({"error": str(error)}, 500)
            return

        self.send_json({"error": "Not found"}, 404)

    def do_GET(self):
        if self.path == "/api/status":
            try:
                result = subprocess.run(
                    ["ollama", "list"],
                    capture_output=True,
                    text=True
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

        super().do_GET()

print("crypted AI running at http://localhost:8000")
HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
PY

# create frontend
cat > public/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#080808">
  <title>crypted AI</title>

  <style>
    :root {
      color-scheme: dark;
      --bg: #080808;
      --panel: rgba(20, 20, 20, .78);
      --panel-strong: #191919;
      --line: rgba(255,255,255,.13);
      --muted: #8b8b8b;
      --text: #f4f4f4;
      --accent: #fff;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      min-height: 100%;
    }

    body {
      min-height: 100vh;
      overflow: hidden;
      background:
        radial-gradient(circle at 50% -20%, #303030 0, transparent 38%),
        var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, sans-serif;
    }

    #snow {
      position: fixed;
      inset: 0;
      z-index: -1;
      opacity: .72;
    }

    .shell {
      width: min(100% - 28px, 940px);
      min-height: 100vh;
      margin: auto;
      display: flex;
      flex-direction: column;
      padding: 28px 0 20px;
    }

    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 20px;
      padding: 4px 2px 24px;
    }

    .brand {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .mark {
      width: 34px;
      height: 34px;
      display: grid;
      place-items: center;
      border: 1px solid var(--line);
      border-radius: 10px;
      background: linear-gradient(145deg, #fff, #777);
      color: #111;
      font-weight: 900;
    }

    .brand-name {
      font-weight: 800;
      letter-spacing: -.04em;
    }

    .brand-subtitle {
      margin-top: 2px;
      color: var(--muted);
      font-size: .72rem;
    }

    .status {
      color: #aaa;
      font-size: .72rem;
      letter-spacing: .12em;
      text-transform: uppercase;
    }

    .status::before {
      content: "";
      display: inline-block;
      width: 6px;
      height: 6px;
      margin-right: 8px;
      border-radius: 50%;
      background: #fff;
      box-shadow: 0 0 12px #fff;
    }

    .chat {
      flex: 1;
      min-height: 0;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      border: 1px solid var(--line);
      border-radius: 24px;
      background: var(--panel);
      box-shadow: 0 24px 80px rgba(0,0,0,.3);
      backdrop-filter: blur(18px);
    }

    .messages {
      flex: 1;
      overflow-y: auto;
      padding: clamp(22px, 5vw, 52px);
    }

    .welcome {
      max-width: 610px;
      margin: 5vh auto;
      text-align: center;
    }

    .welcome h1 {
      margin: 0;
      font-size: clamp(2.4rem, 7vw, 5rem);
      line-height: .95;
      letter-spacing: -.08em;
    }

    .welcome p {
      margin: 18px auto 0;
      max-width: 430px;
      color: var(--muted);
      line-height: 1.6;
    }

    .message {
      width: fit-content;
      max-width: min(82%, 680px);
      margin: 0 0 18px;
      padding: 14px 17px;
      border: 1px solid var(--line);
      border-radius: 16px;
      line-height: 1.6;
      white-space: pre-wrap;
    }

    .user {
      margin-left: auto;
      border-color: #fff;
      background: #f4f4f4;
      color: #111;
    }

    .assistant {
      background: var(--panel-strong);
    }

    .composer {
      display: flex;
      gap: 10px;
      padding: 16px;
      border-top: 1px solid var(--line);
    }

    select, textarea, button {
      font: inherit;
    }

    select {
      max-width: 190px;
      padding: 0 12px;
      border: 1px solid var(--line);
      border-radius: 12px;
      outline: none;
      background: #111;
      color: var(--text);
    }

    textarea {
      flex: 1;
      min-height: 50px;
      max-height: 150px;
      resize: vertical;
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 13px;
      outline: none;
      background: #0c0c0c;
      color: var(--text);
    }

    textarea:focus, select:focus {
      border-color: #fff;
      box-shadow: 0 0 0 3px rgba(255,255,255,.1);
    }

    button {
      min-width: 80px;
      border: 0;
      border-radius: 13px;
      background: #fff;
      color: #111;
      font-weight: 800;
      cursor: pointer;
      transition: transform .18s, opacity .18s;
    }

    button:hover { transform: translateY(-2px); }
    button:disabled { opacity: .45; cursor: wait; }

    footer {
      padding-top: 16px;
      color: #666;
      font-size: .72rem;
      text-align: center;
    }

    @media (max-width: 620px) {
      .shell { padding-top: 16px; }
      .status { display: none; }
      .composer { flex-wrap: wrap; }
      select { order: 2; flex: 1; max-width: none; height: 48px; }
      textarea { order: 1; flex-basis: 70%; }
      button { order: 1; }
      .message { max-width: 92%; }
    }

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        scroll-behavior: auto !important;
        transition: none !important;
      }
    }
  </style>
</head>

<body>
  <canvas id="snow" aria-hidden="true"></canvas>

  <main class="shell">
    <header>
      <div class="brand">
        <div class="mark">C</div>
        <div>
          <div class="brand-name">crypted AI</div>
          <div class="brand-subtitle">private local intelligence</div>
        </div>
      </div>
      <div class="status">local server</div>
    </header>

    <section class="chat">
      <div class="messages" id="messages">
        <div class="welcome" id="welcome">
          <h1>Think locally.</h1>
          <p>Select any model below. If it is not installed, crypted AI will download it automatically when you send your first message.</p>
        </div>
      </div>

      <form class="composer" id="form">
        <select id="model" aria-label="Choose an Ollama model">
          <option value="llama3.2:3b">Llama 3.2 · 3B</option>
          <option value="qwen2.5:3b">Qwen 2.5 · 3B</option>
          <option value="gemma3:4b">Gemma 3 · 4B</option>
          <option value="mistral:7b">Mistral · 7B</option>
          <option value="phi3:mini">Phi-3 Mini</option>
          <option value="deepseek-r1:7b">DeepSeek R1 · 7B</option>
        </select>

        <textarea id="prompt" placeholder="Ask crypted AI anything..." required></textarea>
        <button id="send" type="submit">Send</button>
      </form>
    </section>

    <footer>Models run locally through Ollama</footer>
  </main>

  <script>
    const messages = document.querySelector("#messages");
    const welcome = document.querySelector("#welcome");
    const form = document.querySelector("#form");
    const prompt = document.querySelector("#prompt");
    const model = document.querySelector("#model");
    const send = document.querySelector("#send");

    function addMessage(text, type) {
      welcome?.remove();
      const element = document.createElement("div");
      element.className = `message ${type}`;
      element.textContent = text;
      messages.appendChild(element);
      messages.scrollTop = messages.scrollHeight;
      return element;
    }

    form.addEventListener("submit", async event => {
      event.preventDefault();

      const text = prompt.value.trim();
      if (!text) return;

      addMessage(text, "user");
      prompt.value = "";
      send.disabled = true;

      const reply = addMessage(
        `Loading ${model.value}. First use may download the model...`,
        "assistant"
      );

      try {
        const response = await fetch("/api/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            model: model.value,
            prompt: text
          })
        });

        const data = await response.json();
        if (!response.ok) throw new Error(data.error || "Request failed");

        reply.textContent = data.response;
      } catch (error) {
        reply.textContent = `Error: ${error.message}`;
      } finally {
        send.disabled = false;
        prompt.focus();
      }
    });

    // Monochrome snow background
    const canvas = document.querySelector("#snow");
    const ctx = canvas.getContext("2d");
    let flakes = [];

    function resize() {
      canvas.width = innerWidth * devicePixelRatio;
      canvas.height = innerHeight * devicePixelRatio;
      ctx.scale(devicePixelRatio, devicePixelRatio);
      flakes = Array.from({ length: Math.min(100, innerWidth / 10) }, () => ({
        x: Math.random() * innerWidth,
        y: Math.random() * innerHeight,
        r: Math.random() * 2 + .5,
        v: Math.random() * .55 + .2,
        drift: (Math.random() - .5) * .25
      }));
    }

    function snow() {
      ctx.clearRect(0, 0, innerWidth, innerHeight);
      ctx.fillStyle = "rgba(255,255,255,.65)";

      for (const flake of flakes) {
        flake.y += flake.v;
        flake.x += flake.drift;

        if (flake.y > innerHeight + 5) {
          flake.y = -5;
          flake.x = Math.random() * innerWidth;
        }

        ctx.beginPath();
        ctx.arc(flake.x, flake.y, flake.r, 0, Math.PI * 2);
        ctx.fill();
      }

      requestAnimationFrame(snow);
    }

    addEventListener("resize", resize);
    resize();
    snow();
  </script>
</body>
</html>
HTML

# start server
cd ~/crypted-ai
nohup python3 server.py > server.log 2>&1 &

echo
echo "crypted AI is running."
echo "open port 8000 in the Codespaces Ports panel!"
