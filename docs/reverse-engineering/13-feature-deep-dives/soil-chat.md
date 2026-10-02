# Deep dive — Soil chat

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | Let the user ask follow-up questions about a saved soil and "refine details" | CONFIRMED |
| Entry | card chat icon; details "Chat with AI to Refine Details" | CONFIRMED |
| Screen | `SoilChatScreen`: header with thumbnail, type and health; quick-prompt chips ("Best crops to grow", "Soil health tips", …); message list with a "Today" separator; hint "Share information about condition to refine details"; "View Full Details"; text input and send | CONFIRMED |
| State | `conversationHistory`, typing indicator, input text | CONFIRMED (UI) |
| Controller | `useChatContext`, `onChatPress`, `startChat` | HIGHLY LIKELY |
| Use case | chat service: send history + soil context to Gemini; fallback Flash → Pro | HIGHLY LIKELY |
| API | Gemini `generateContent` (or the stream variant); models from Remote Config | HIGHLY LIKELY |
| Persistence | `saveChatHistory` per soil (survives a force-stop) | CONFIRMED |
| Rules | BR-11, BR-21, BR-22 | — |
| Side effects | possibly `applySoilUpdates` writing refined fields back to the record | UNKNOWN |
| Errors | any failure → assistant bubble "I'm having trouble processing that. Could you rephrase or try a different question?" | CONFIRMED |
| Output | AI text rendered as Markdown-ish (the `**bold**` markers were shown literally in the template bubble) | CONFIRMED |

## Call graph

```text
SoilChatScreen.mount
→ load history(soilId) || seed with local template ("Great find! I've identified this as **{type}**…")
onSend(text)
→ append user message (optimistic) + typing indicator
→ chatService.send(history, soil)
   → model(flash).generateContent(...)  ── fail ──▶ model(pro).generateContent(...)
   → reply text
   └─ any error → apology text
→ append AI message → saveChatHistory(soilId)
```

Observed: the quick prompt "Best crops to grow" (online, free plan, 0 scans)
answered with the apology bubble, so either both models failed or the request
was refused. Offline, the same screen kept the history and accepted input.
