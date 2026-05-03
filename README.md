# Hermes Agent — Railway Template

## Railway Setup

When creating a new project in Railway, you must configure the following:

### 1. Create a Postgres Database

1. In your Railway project, click **+ New** and select **Database**
2. Choose **Postgres** from the database options
3. Railway will automatically provision a Postgres instance

### 2. Add Environment Variables

In your Railway service's **Variables** tab, add the following:

#### Database (auto-populated from Postgres service)
```
DATABASE_URL=${{Postgres.DATABASE_URL}}
PGPASSWORD=${{Postgres.PGPASSWORD}}
PGUSER=${{Postgres.PGUSER}}
```

#### LLM Provider (DeepSeek)
```
DEEPSEEK_API_KEY=sk-your-deepseek-api-key
HERMES_MODEL=deepseek-v4-pro
```

#### Telegram Bot
```
TELEGRAM_BOT_TOKEN=<your-telegram-bot-token>
TELEGRAM_ALLOWED_USERS=<your-telegram-user-id>
```

#### Optional: Vector Search (GBrain)
```
OPENAI_API_KEY=sk-your-openai-api-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-api-key
```

Once these variables are set, Railway will automatically spin up a new deployment using the DeepSeek V4 models.

## Getting Started

Follow the **Railway Setup** section above first to configure your environment variables. Then:

### 1. Get Your API Keys

**DeepSeek** (recommended for V4 models):
1. Sign up at [DeepSeek](https://platform.deepseek.com/)
2. Create an API key from your dashboard
3. Add to Railway Variables: `DEEPSEEK_API_KEY=sk-...`

**Alternative**: Use [OpenRouter](https://openrouter.ai/) for other models

### 2. Set Up a Telegram Bot (fastest channel)

Hermes Agent interacts entirely through messaging channels — there is no chat UI like ChatGPT. Telegram is the quickest to set up:

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot`, follow the prompts, and copy the **Bot Token**
3. Send a message to your new bot — it will appear as a pairing request in the admin dashboard
4. To find your Telegram user ID, message [@userinfobot](https://t.me/userinfobot)

### 3. Deploy to Railway

1. Click the **Deploy on Railway** button above
2. Set the `ADMIN_PASSWORD` environment variable (or a random one will be generated and printed to deploy logs)
3. Attach a **volume** mounted at `/data` (persists config across redeploys)
4. Open your app URL — log in with username `admin` and your password

### 4. Verify Configuration

Since you've already set the environment variables in Railway:

1. **LLM Provider** — DeepSeek V4 Pro is already configured
2. **Messaging Channel** — Telegram is already configured with your bot token
3. The gateway will start automatically — no additional setup needed in the dashboard

You can still use the admin dashboard to:
- Add additional channels (Discord, Slack, etc.)
- Configure additional tools and integrations
- Manage user access and pairing requests

### 5. Start Chatting

Message your Telegram bot. If you're a new user, a pairing request will appear in the admin dashboard under **Users** — click **Approve**, and you're in.

<!-- TODO: Add Telegram chat screenshot -->
<!-- ![Telegram Example](docs/telegram-example.png) -->

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Web server port (set automatically by Railway) |
| `ADMIN_USERNAME` | `admin` | Basic auth username |
| `ADMIN_PASSWORD` | *(auto-generated)* | Basic auth password — if unset, a random password is printed to logs |

All other configuration (LLM provider, model, channels, tools) is managed through the admin dashboard.

## Supported Providers

OpenRouter, DeepSeek, DashScope, GLM / Z.AI, Kimi, MiniMax, HuggingFace

## Supported Channels

Telegram, Discord, Slack, WhatsApp, Email, Mattermost, Matrix

## Supported Tool Integrations

Parallel (search), Firecrawl (scraping), Tavily (search), FAL (image gen), Browserbase, GitHub, OpenAI Voice (Whisper/TTS), Honcho (memory)

## Architecture

```
Railway Container
├── Python Admin Server (Starlette + Uvicorn)
│   ├── /            — Admin dashboard (Basic Auth)
│   ├── /health      — Health check (no auth)
│   └── /api/*       — Config, status, logs, gateway, pairing
└── hermes gateway   — Managed as async subprocess
```

The admin server runs on `$PORT` and manages the Hermes gateway as a child process. Config is stored in `/data/.hermes/.env` and `/data/.hermes/config.yaml`. Gateway stdout/stderr is captured into a ring buffer and streamed to the Logs panel.

## Running Locally

```bash
docker build -t hermes-agent .
docker run --rm -it -p 8080:8080 -e PORT=8080 -e ADMIN_PASSWORD=changeme -v hermes-data:/data hermes-agent
```

Open `http://localhost:8080` and log in with `admin` / `changeme`.

## Credits

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) by [Nous Research](https://nousresearch.com/)
- UI inspired by [OpenClaw](https://github.com/praveen-ks-2001/openclaw-railway) admin template
