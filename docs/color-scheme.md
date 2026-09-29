# Inverted Neon Cyberpunk Color Scheme

Bright popping neon surfaces with **bold black text** (dark-on-neon invert of the classic void theme).

| Role | Color | Hex | Notes |
|------|-------|-----|-------|
| Chat / main background | neon yellow | `#fff200` | Main app canvas |
| Secondary surface | hot yellow | `#ffe600` / `#ffd400` | Cards, elevated panels |
| Left sidebar | neon orange | `#ff6b00` | Nav rail + session list |
| Input box background | neon blue | `#00e5ff` | Chat textarea + input chrome |
| Input / body text | black bold | `#0a0a0a` | All UI + typed text (weight 700+) |
| User messages | neon red | `#ff2a2a` | User bubbles, red glow, black text |
| AI responses | neon cyan-blue | `#7df9ff` → `#00e5ff` | Assistant bubbles + headings |
| Terminal / code panel | neon red-pink | `#ff3355` | `pre`, syntax blocks (black mono) |
| Inline code chip | neon orange | `#ff6b00` | Inline `code` chips |
| Accent orange | neon | `#ff6b00` | Sidebar, warnings |
| Accent red | neon | `#ff2a2a` | User, danger, rings, selection |
| Accent yellow | neon | `#fff200` | Chat canvas |
| Accent blue | neon | `#00e5ff` | Input, AI, focus, links |
| Borders | hard black | `#0a0a0a` | High-contrast outlines |
| Success | matrix lime | `#39ff14` | Success states |

## Component map

```text
┌────────────────┬──────────────────────────────────────┐
│ NEON ORANGE    │  NEON YELLOW chat canvas             │
│ sidebar        │                                      │
│ #ff6b00        │   user bubble  = neon red #ff2a2a    │
│ black text     │   AI bubble    = neon blue #7df9ff   │
│                │                                      │
│                │  ┌────────────────────────────────┐  │
│                │  │ INPUT = neon blue #00e5ff      │  │
│                │  │ typed text = bold black        │  │
│                │  └────────────────────────────────┘  │
└────────────────┴──────────────────────────────────────┘
```

## Fonts

- **UI:** [Rajdhani](https://fonts.google.com/specimen/Rajdhani) **600/700** (loaded from Google Fonts)
- **Display / clock / headings:** [Orbitron](https://fonts.google.com/specimen/Orbitron) **700/800**
- **Mono / terminal:** [Share Tech Mono](https://fonts.google.com/specimen/Share+Tech+Mono)
- Fallbacks: Ubuntu / Noto Sans / system UI, Ubuntu Mono / DejaVu Sans Mono

All text is forced **bold black** (`font-weight: 700+`, `#0a0a0a`). Text sizes are bumped ~1 step above Goose defaults (`text-sm` → 1rem, base body 17px).
