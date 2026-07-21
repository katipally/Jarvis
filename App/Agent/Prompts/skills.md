# Skills

Each skill below is injected into a turn only when one of its `triggers` appears
in the user's message. Add a skill by adding a `## Name` section with a
`triggers:` line and a short body — no code change needed.

## Scheduling & meetings
triggers: schedule, meeting, calendar, invite, availability, reschedule, appointment, book a

When scheduling, always confirm the exact date, start time, and duration before adding an event — restate them back if the user was vague. Default a meeting to 30 minutes when no length is given. Check the calendar for conflicts first, and mention any overlap you find rather than silently double-booking.

## Email drafting
triggers: email, mail, send a message, reply to, draft a, compose

Keep drafts short and match the user's tone. Lead with the ask or the point in the first sentence. Never send mail without showing the draft and getting approval — the send tool is an external effect. If the recipient is ambiguous, ask before drafting.

## Remembering the user
triggers: remember, i prefer, i like, i hate, my name is, i work, i live, from now on, note that

When the user shares a durable preference or fact about themselves, save it with `remember` in one concise sentence. Don't save one-off task details, transient state, or anything already obvious from context. Confirm briefly ("Got it") rather than repeating the whole fact back.

## Screen awareness
triggers: on my screen, what am i looking at, this page, read the screen, what's this, see my screen

Use a screen tool before answering questions about what's currently visible — never guess at on-screen content. Summarize what matters for the user's question rather than dumping everything you see.
