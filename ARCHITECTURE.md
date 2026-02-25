# 🏨 StayBright Hotels — Architecture

This document describes the architecture of the StayBright Hotels demo application, covering components, integration patterns, data flow, and deployment topology.

---

## High-Level Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        Azure App Service                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              ASP.NET Core Backend (net10.0)                 │ │
│  │                                                             │ │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐ │ │
│  │  │ REST API │  │MCP Server│  │  AG-UI    │  │  Feature  │ │ │
│  │  │ /api/*   │  │  /mcp    │  │/agent-chat│  │  Toggles  │ │ │
│  │  └────┬─────┘  └────┬─────┘  └─────┬─────┘  └───────────┘ │ │
│  │       │              │              │                       │ │
│  │  ┌────┴──────────────┴──────────────┴────────────────────┐ │ │
│  │  │         Services (HotelService, BookingService)       │ │ │
│  │  └───────────────────────┬───────────────────────────────┘ │ │
│  │                          │                                 │ │
│  │                   ┌──────┴──────┐                          │ │
│  │                   │  In-Memory  │                          │ │
│  │                   │  Seed Data  │                          │ │
│  │                   │ (100 hotels)│                          │ │
│  │                   └─────────────┘                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │          React SPA (served as static files from wwwroot)    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
         │                │                │
         │ REST           │ SSE            │ MCP/HTTP
         ▼                ▼                ▼
   ┌──────────┐   ┌──────────────┐  ┌──────────────┐
   │  Browser  │   │ Chat Widget  │  │Console Agent │
   │(React UI) │   │  (AG-UI)     │  │  (MCP Client)│
   └──────────┘   └──────────────┘  └──────────────┘

                                         │
         ┌───────────────────────────────┘
         ▼
  ┌──────────────┐
  │ Azure OpenAI │
  │   (gpt-4o)   │
  └──────────────┘
```

---

## Components

### 1. Backend API — ASP.NET Core

**Path:** `backend/HotelBooking.Api/`  
**Runtime:** .NET 10.0  
**Entry point:** `Program.cs`

The backend is the central hub hosting **four interfaces** in a single process:

| Interface | Path | Protocol | Purpose |
|-----------|------|----------|---------|
| REST API | `/api/*` | HTTP/JSON | Standard CRUD for hotels & bookings |
| OpenAPI Spec | `/openapi/v1.json` | HTTP/JSON | Machine-readable API schema |
| MCP Server | `/mcp` | HTTP + SSE | Tool exposure for external agents |
| AG-UI Agent | `/agent-chat` | HTTP + SSE | Streaming chat for the web widget |
| Static Files | `/` | HTTP | Serves the React SPA |

#### Service Layer

```
Program.cs
 ├── HotelService        →  Search, GetById, GetAvailableRooms
 ├── BookingService       →  Create, GetById, GetByEmail, Cancel
 └── FeatureToggleService →  Enable/disable chat widget
```

Services use **in-memory data** (`SeedData.cs`) — 100 hotels across 64 countries with rooms, amenities, and coordinates. No database required, making the demo portable and self-contained.

#### Key Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `Azure.AI.OpenAI` | 2.8.0-beta.1 | Azure OpenAI SDK |
| `Microsoft.Extensions.AI.OpenAI` | 10.3.0 | Unified AI abstraction layer |
| `ModelContextProtocol.AspNetCore` | 1.0.0-rc.1 | MCP server (HTTP transport) |
| `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore` | 1.0.0-preview | AG-UI protocol hosting |

---

### 2. Frontend — React SPA

**Path:** `frontend/`  
**Toolchain:** Vite 7 + React 19 + TypeScript 5 + Tailwind CSS 4

#### Pages

| Route | Page | Description |
|-------|------|-------------|
| `/` | `HomePage` | Hotel search with filters (city, country, stars, price, guests) |
| `/hotels/:id` | `HotelDetailPage` | Hotel info, room list, and booking form |
| `/my-bookings` | `MyBookingsPage` | Lookup and manage bookings by email |

#### Components

| Component | Role |
|-----------|------|
| `Layout` | Page shell with `Navbar` + optional `ChatWidget` |
| `Navbar` | Top navigation bar |
| `SearchBar` | Search/filter form on home page |
| `HotelCard` | Hotel listing card |
| `BookingForm` | Room booking form with date/guest inputs |
| `BookingCard` | Individual booking display with cancel action |
| `ChatWidget` | Floating AI assistant (AG-UI SSE client) |

#### API Client (`api/client.ts`)

Typed HTTP wrapper that calls `/api/*` endpoints. In development, Vite proxies these to `http://localhost:5000`.

#### Chat Widget — AG-UI Integration

The `ChatWidget` component implements the AG-UI client protocol:

1. Sends user message via `POST /agent-chat` with conversation history
2. Reads `text/event-stream` response (SSE)
3. Parses `TEXT_MESSAGE_CONTENT` events with `delta` payloads
4. Streams tokens into the UI in real time

Visibility is controlled by the backend feature toggle — the `Layout` component fetches `GET /api/config/features` on mount and conditionally renders the widget.

---

### 3. Console Agent — .NET CLI

**Path:** `console-agent/ConsoleAgent/`  
**Runtime:** .NET 10.0

A standalone interactive chat agent that connects to the backend's MCP server:

```
┌────────────────────────────────────────────────────┐
│                  Console Agent                      │
│                                                     │
│  ┌─────────────┐    ┌──────────────────────────┐   │
│  │  User Input  │───▶│  ChatClientBuilder       │   │
│  │  (stdin)     │    │  + UseFunctionInvocation  │   │
│  └─────────────┘    └──────────┬───────────────┘   │
│                                │                    │
│                     ┌──────────┴───────────┐        │
│                     │   Azure OpenAI       │        │
│                     │   (gpt-4o)           │        │
│                     └──────────┬───────────┘        │
│                                │                    │
│                     ┌──────────┴───────────┐        │
│                     │  MCP Client Tools    │        │
│                     │  (auto-discovered)   │        │
│                     └──────────┬───────────┘        │
│                                │                    │
└────────────────────────────────┼────────────────────┘
                                 │ HTTP
                                 ▼
                        ┌────────────────┐
                        │ Backend /mcp   │
                        └────────────────┘
```

**Key pattern:** The console agent dynamically discovers tools from the MCP server via `ListToolsAsync()`. Each `McpClientTool` implements the `AITool` interface from `Microsoft.Extensions.AI`, enabling seamless integration with the `ChatClientBuilder` pipeline.

#### Key Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `ModelContextProtocol` | 1.0.0-rc.1 | MCP client (HTTP transport) |
| `Microsoft.Agents.AI.OpenAI` | 1.0.0-rc1 | MAF AI integration |
| `Microsoft.Extensions.AI.OpenAI` | 10.3.0 | ChatClient builder + function invocation |

---

## Integration Patterns

### OpenAPI-Driven Design

The backend exposes a full OpenAPI 3.0 schema at `/openapi/v1.json` using ASP.NET Core's built-in `AddOpenApi()` + `MapOpenApi()`. This enables:
- API documentation and exploration
- Client code generation
- Contract-first development

### Model Context Protocol (MCP)

MCP provides a standardized way for AI agents to discover and invoke tools. The backend exposes 7 tools at `/mcp`:

| Tool | Description |
|------|-------------|
| `SearchHotels` | Search by city, country, stars, price, guests |
| `GetHotelDetails` | Full hotel information |
| `GetAvailableRooms` | Room availability for a hotel |
| `CreateBooking` | Book a room |
| `GetBooking` | Retrieve booking by ID |
| `ListBookings` | List bookings by email |
| `CancelBooking` | Cancel a booking |

Tools are defined in `McpTools/HotelTools.cs` using `[McpServerToolType]` and `[McpServerTool]` attributes. The server uses **HTTP transport with SSE** for streaming responses.

### AG-UI Protocol (Agent-User Interaction)

The AG-UI protocol (from the Microsoft Agent Framework) enables streaming agent-to-user communication over SSE:

```
Browser                    Backend                  Azure OpenAI
  │                           │                         │
  │  POST /agent-chat         │                         │
  │  {messages: [...]}        │                         │
  │ ─────────────────────────▶│                         │
  │                           │  Chat completion        │
  │                           │  (with tools)           │
  │                           │────────────────────────▶│
  │                           │                         │
  │  SSE: TEXT_MESSAGE_CONTENT│  Streaming response     │
  │  {delta: "Sure, I can..."}│◀────────────────────────│
  │ ◀─────────────────────────│                         │
  │                           │                         │
  │  SSE: TEXT_MESSAGE_CONTENT│  (tool call if needed)  │
  │  {delta: "help you..."}  │◀───────────────────────▶│
  │ ◀─────────────────────────│                         │
  │                           │                         │
  │  SSE: [DONE]              │                         │
  │ ◀─────────────────────────│                         │
```

The agent has access to the same 7 hotel tools (defined in `AgentTools/HotelAgentTools.cs` via `AIFunctionFactory.Create()`) and can perform actions like searching hotels or creating bookings during conversation.

### Feature Toggle

The chat widget is gated behind a backend feature toggle:

```
GET  /api/config/features              →  { "chatEnabled": true }
PUT  /api/config/features/chat?enabled=false  →  Disables the widget
```

The `Layout` component checks this on load; the `ChatWidget` is only rendered when `chatEnabled` is `true`. This allows live demos to toggle the AI experience on/off without redeployment.

---

## Data Flow

### Hotel Search Flow

```
User types search → SearchBar → API client → GET /api/hotels?city=paris
                                                      │
                                    HotelService.SearchHotels()
                                                      │
                                              In-memory filter
                                                      │
                                         JSON response (hotels[])
                                                      │
                                    HomePage renders HotelCards
```

### Booking Flow

```
User fills form → BookingForm → API client → POST /api/bookings
                                                    │
                                    BookingService.CreateBooking()
                                                    │
                                        Generates booking ID
                                        Stores in-memory
                                                    │
                                    BookingConfirmation response
                                                    │
                                    UI shows confirmation
```

### Agent Chat Flow (Web)

```
User types message → ChatWidget → POST /agent-chat (SSE)
                                         │
                              AG-UI Agent receives messages
                                         │
                              Azure OpenAI chat completion
                                         │
                         ┌───────────────┼───────────────┐
                         │               │               │
                    Direct reply    Tool call        Tool call
                         │          (search)        (book room)
                         │               │               │
                         │        HotelService    BookingService
                         │               │               │
                         └───────┬───────┘───────────────┘
                                 │
                          SSE stream tokens → ChatWidget renders
```

### Agent Chat Flow (Console)

```
User types message → Console Agent → MCP Client discovers tools
                                            │
                                    Azure OpenAI chat completion
                                            │
                                ┌───────────┼───────────┐
                                │                       │
                          Direct reply            MCP tool call
                                │                       │
                                │            HTTP POST to /mcp
                                │            Backend executes tool
                                │            Returns JSON result
                                │                       │
                                └───────┬───────────────┘
                                        │
                                Console prints response
```

---

## Deployment Architecture

### Single App Service Model

The entire application deploys as a **single Azure App Service**:

```
┌─────────────────────────────────────────────────┐
│           Azure App Service (Linux)              │
│           .NET 10.0 Runtime                      │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  ASP.NET Core Process                      │  │
│  │                                            │  │
│  │  /api/*          → REST Controllers        │  │
│  │  /mcp            → MCP Server (SSE)        │  │
│  │  /agent-chat     → AG-UI Agent (SSE)       │  │
│  │  /openapi/v1.json→ OpenAPI Spec            │  │
│  │  /*              → wwwroot/ (React SPA)    │  │
│  │                    + SPA fallback           │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  Environment Variables:                          │
│  ├── AZURE_OPENAI_ENDPOINT                       │
│  ├── AZURE_OPENAI_API_KEY                        │
│  └── AZURE_OPENAI_DEPLOYMENT_NAME                │
└─────────────────────────────────────────────────┘
                    │
                    │ HTTPS (API key auth)
                    ▼
          ┌───────────────────┐
          │  Azure OpenAI     │
          │  (gpt-4o)         │
          └───────────────────┘
```

### Infrastructure as Code (Bicep)

**File:** `infra/main.bicep`

| Resource | Purpose |
|----------|---------|
| `Microsoft.Web/serverfarms` | App Service Plan (Linux, configurable SKU) |
| `Microsoft.Web/sites` | Web App with .NET 10 runtime, app settings for OpenAI |

### Deployment Options

| Method | File | Trigger |
|--------|------|---------|
| **PowerShell** | `deploy.ps1` | Manual: `./deploy.ps1 -ResourceGroup rg-demo -Location westeurope -AppName staybright` |
| **GitHub Actions** | `.github/workflows/deploy.yml` | Push to `main` or manual dispatch |
| **Manual** | See README.md | Step-by-step Azure CLI commands |

### GitHub Actions Secrets Required

| Secret | Purpose |
|--------|---------|
| `AZURE_CLIENT_ID` | Service principal application ID |
| `AZURE_CLIENT_SECRET` | Service principal client secret |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key |

---

## Development Setup

### Local Architecture

```
┌──────────────┐         ┌──────────────────┐        ┌──────────────┐
│ Vite Dev     │ proxy   │ ASP.NET Core     │        │ Azure OpenAI │
│ :5173        │────────▶│ :5000            │───────▶│ (cloud)      │
│              │ /api/*  │                  │        │              │
│ React SPA   │ /agent-*│ REST + MCP + AGUI│        │              │
└──────────────┘         └──────────────────┘        └──────────────┘
                                  ▲
                                  │ MCP/HTTP
                         ┌────────┴─────────┐
                         │  Console Agent   │
                         │  (dotnet run)    │
                         └──────────────────┘
```

- **Frontend** runs on Vite dev server (`:5173`) with hot reload, proxying API calls to the backend
- **Backend** runs on Kestrel (`:5000`) serving REST, MCP, and AG-UI endpoints
- **Console Agent** connects to the backend's MCP server independently

### Port Configuration

| Component | Dev Port | Prod |
|-----------|----------|------|
| Frontend (Vite) | 5173 | Served from backend `/` |
| Backend API | 5000 | App Service (443) |
| MCP Server | 5000 `/mcp` | App Service `/mcp` |
| AG-UI Agent | 5000 `/agent-chat` | App Service `/agent-chat` |

---

## Technology Stack Summary

| Layer | Technology | Version |
|-------|-----------|---------|
| **Backend Runtime** | .NET | 10.0 |
| **Web Framework** | ASP.NET Core | 10.0 |
| **AI Framework** | Microsoft Agent Framework | 1.0.0-preview |
| **MCP** | ModelContextProtocol | 1.0.0-rc.1 |
| **AI Abstraction** | Microsoft.Extensions.AI | 10.3.0 |
| **LLM** | Azure OpenAI (gpt-4o) | — |
| **Frontend** | React | 19.2 |
| **Routing** | React Router | 7.13 |
| **Styling** | Tailwind CSS | 4.2 |
| **Build Tool** | Vite | 7.3 |
| **Language** | TypeScript | 5.9 |
| **IaC** | Bicep | — |
| **CI/CD** | GitHub Actions | — |
| **Hosting** | Azure App Service (Linux) | — |
