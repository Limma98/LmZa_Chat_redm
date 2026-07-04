-- LmZa_Chat · config.lua
-- All tuneable values live here. Edit freely — no other file needs changing.

Config = {}

-- ─── Spam protection ─────────────────────────────────────────────────────────
Config.SpamCooldownMs   = 2000   -- minimum ms between messages per player
Config.MaxMessageLength = 200    -- hard cap (also enforced in NUI)

-- ─── Chat display ────────────────────────────────────────────────────────────
Config.FadeTimeoutMs    = 8000   -- ms before idle messages fade out
Config.MaxMessages      = 50     -- max messages kept in the scroll buffer
Config.AutoClearMins    = 60     -- minutes between automatic chat clears (0 = disabled)

-- ─── /me 3D text ─────────────────────────────────────────────────────────────
Config.MeCommand        = 'me'   -- command name: /me <action>
Config.MeRange          = 10.0   -- units — only players within this distance see the 3D text
Config.MeDurationMs     = 5000   -- how long the 3D text floats above the player (ms)
Config.MeOffsetZ        = 0.0    -- 0.0 = entity origin (approx torso). Increase for higher, decrease for lower.

-- ─── Scroll history ──────────────────────────────────────────────────────────
Config.HistorySize      = 20     -- how many sent messages to remember (↑/↓ arrows)
