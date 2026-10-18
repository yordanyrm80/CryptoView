# Antigravity Workspace Guidelines - CriptoBot

## 1. Programming Language Standard: 100% English
- All source code, class names, method names, variable names, function signatures, data models, schemas, and technical comments MUST be written strictly in standard, canonical English.
- No "Spanglish" or bilingual code.
- Avoid duplicate alias shims or bilingual property wrappers (ClassNameEs = ClassNameEn, valuar = evaluate) in core logic.
- The Spanish language is strictly restricted to:
  1. User-facing UI strings (Flutter application screens, buttons, charts, user dialogs).
  2. End-user notifications/alerts (Telegram, push notifications).
  3. High-level business strategy documents and user research notes.

## 2. Core Philosophy and Trading Logic
- High long-term compound return and realized cash flow are the supreme criteria ( > 0$).
- Never sacrifice net profitability to smooth floating drawdown.
- Zero-Trust API security: never enable withdrawal permissions on KuCoin API keys.
