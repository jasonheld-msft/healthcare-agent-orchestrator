# Teams-to-Orchestrator Flow

This diagram set shows how a Microsoft Teams message flows through the bot entrypoint, orchestration logic, agents/tools, and data services in this repo.

- Entry: Teams message hits `/api/{bot}/messages` via Bot Framework Service.
- Assistant path: Semantic Kernel GroupChat orchestrates agents (from `scenarios/*/config/agents.yaml`).
- Magentic path: Experimental MagenticOne stream uses blob-based gating for user input.

## Sequence: AssistantBot (default orchestrator)

```mermaid
sequenceDiagram
    autonumber
    participant U as Teams User
    participant T as Microsoft Teams
    participant BFS as Bot Framework Service
    participant API as FastAPI /api/{bot}/messages
    participant CAD as CloudAdapter
    participant AB as AssistantBot
    participant DA as DataAccess (Blob/FHIR/Fabric)
    participant SK as SK AgentGroupChat
    participant AOAI as Azure OpenAI (Chat Completion)
    participant PL as Scenario Tools / OpenAPI Plugins
    participant HAS as Healthcare Agent Service (Direct Line)
    participant KV as Azure Key Vault
    participant BLOB as Azure Blob Storage

    U->>T: Message in channel/chat (mentions bot)
    T->>BFS: Deliver activity
    BFS->>API: POST /api/{bot}/messages (Activity)
    API->>CAD: authenticate_request(activity, auth_header)
    API->>CAD: process_activity(..., bot.on_turn)
    CAD->>AB: on_turn -> on_message_activity

    AB->>DA: chat_context_accessor.read(conversation_id)
    alt first message in thread
        AB->>T: probe typing to agents in chat (who is present)
        note right of AB: get_bot_context(...) builds per-agent TurnContext
    end

    AB->>SK: create_group_chat(app_ctx, chat_ctx, participants)
    SK->>AOAI: ChatCompletion via Managed Identity
    loop agent turns (selection/termination)
        SK-->>AB: response (agent name + content)
        AB->>DA: replace blob URLs with SAS (BlobSasDelegate)
        AB->>T: send activity as that agent (via per-agent TurnContext)
    end

    par tools
        SK->>PL: invoke function tools (scenarios/.../tools/*)
        PL-->>DA: read patient data, images, notes (FHIR/Fabric/Blob)
        PL-->>BLOB: read artifacts/images
    and healthcare agents
        SK->>HAS: call agent via Direct Line
        HAS->>KV: fetch Direct Line secret (once)
        HAS-->>SK: response text (+attachments)
    end

    AB->>DA: chat_context_accessor.write(chat_ctx)
    AB-->>CAD: done
    CAD-->>API: 200 OK
    API-->>BFS: 200 OK
    BFS-->>T: deliver replies
    T-->>U: Bot/Agent messages
```

Key code:

- `src/routes/api/messages.py` (FastAPI route + CloudAdapter auth/dispatch)
- `src/bots/assistant_bot.py` (message handling, group chat invoke, SAS URL swap)
- `src/group_chat.py` (SK AgentGroupChat creation, selection/termination strategies)
- `src/data_models/*` (chat context/artifacts, FHIR/Fabric access, Blob SAS)
- `src/healthcare_agents/*` (Healthcare Agent via Direct Line + Key Vault)

## Sequence: MagenticBot (experimental)

```mermaid
sequenceDiagram
    autonumber
    participant U as Teams User
    participant T as Microsoft Teams
    participant BFS as Bot Framework Service
    participant API as FastAPI /api/magentic/messages
    participant CAD as CloudAdapter
    participant MB as MagenticBot
    participant MG as MagenticOneGroupChat
    participant BLOB as Azure Blob Storage (chat ctx + locks)

    U->>T: Message
    T->>BFS: Deliver activity
    BFS->>API: POST /api/magentic/messages
    API->>CAD: authenticate + process_activity
    CAD->>MB: on_message_activity

    MB->>BLOB: chat_context_accessor.read(...)
    alt conversation_in_progress.txt exists
        MB->>BLOB: upload user_message.txt (reply)
        MB-->>CAD: 200 OK
    else start new run
        MB->>MG: create_magentic_chat(..., user_input_callback)
        MB->>BLOB: upload conversation_in_progress.txt
        loop streamed events
            MG-->>MB: agent message chunks / events
            MB->>Teams: send messages (optionally monologue)
        end
        MB->>BLOB: delete conversation_in_progress.txt
    end
```

Key code:

- `src/bots/magentic_bot.py` (blob-gated user input flow, streaming)

## Component view

```mermaid
flowchart TD
    subgraph Teams
        U[User]
        T[Teams Client]
    end
    subgraph BotFramework
        BFS[Bot Framework Service]
    end
    subgraph App[FastAPI App]
        API[/routes/api/messages.py/]
        ADP[CloudAdapter]
        AB[AssistantBot]
        MB[MagenticBot]
        GC[group_chat.py - SK AgentGroupChat]
    end

    subgraph Data[Data Access]
        DAC[ChatContext/Artifact Accessors]
        BLOB[(Azure Blob Storage)]
        FHIR[FHIR Service]
        FAB[Fabric Function]
        SAS[Blob SAS Delegate]
    end

    subgraph AIServices[AI Services]
        AOAI[Azure OpenAI]
        TOOLS[Scenario Tools / OpenAPI Plugins]
        HAS[Healthcare Agent Service]
        KV[(Azure Key Vault)]
    end

    subgraph Obs[Observability]
        AppInsights[(Application Insights)]
    end

    U-->T-->BFS-->API-->ADP-->AB
    ADP-->MB

    AB-->GC
    MB-->GC
    GC-->AOAI
    GC-->|tools| TOOLS
    TOOLS-->|read/write| DAC
    DAC<-->BLOB
    DAC-->FHIR
    DAC-->FAB
    AB-->|SAS URLs| SAS
    SAS-->BLOB

    GC-->|healthcare agent| HAS
    HAS-->|secrets| KV

    API-.->|telemetry| AppInsights
```

Notes:

- Authentication: CloudAdapter uses `ConfigurationBotFrameworkAuthentication` with the specific bot’s App ID from environment (`BOT_IDS`) set in `DefaultConfig`.
- AOAI calls use Managed Identity via `AppContext.cognitive_services_token_provider`.
- Clinical notes can come from FHIR or Fabric based on `CLINICAL_NOTES_SOURCE` env.
- Images/artifacts live in Blob; SAS URLs are generated at send time to safely expose links in Teams.

## Where this is defined in code

- App bootstrap: `src/app.py` wires adapters and bots, mounts routes, and serves static UI.
- Agent config: `src/scenarios/<scenario>/config/agents.yaml` (facilitator, tools, descriptions).
- Env-driven wiring: `src/config.py` (`load_agent_config`, App Insights, logging).

## How to read this

Start at Teams -> Bot Framework -> `/api/{bot}/messages` route -> CloudAdapter -> Bot handler -> Group chat -> Tools/services -> back to Teams.

If you need a PNG for slides, you can paste the Mermaid blocks into a Mermaid renderer (e.g., VS Code Mermaid preview or mermaid.live) and export.
