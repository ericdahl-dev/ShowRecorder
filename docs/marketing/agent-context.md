# ShowRecorder context for marketing agents

Every marketing agent in `.claude/agents/` reads this file before a ShowRecorder task. It overrides the agent's generic advice where they conflict. Edit it here, once, for all of them.

**The product.** ShowRecorder records every channel of a digital mixer to an iPhone, iPad or Mac over USB: one 24-bit WAV per channel, named from the mixer (`03 Snare.wav`), with a second copy on a USB drive, markers, Pre-roll, a Show report and a Reaper project. No recording laptop at the gig. Mixers: Behringer X Air (XR18, MR18) and, from 1.2, Behringer X32 and Midas M32 for names and colors over Wi-Fi; other class-compliant USB interfaces record without names. Facts to quote come from `README.md`, `website/lib/llms.ts` and `docs/app-store/listing.md`; never invent a feature, mixer, channel count, rating or download number.

**Pricing.** Free records every channel (generic names, 3 markers per Take). Pro is a one-time purchase, shared with family, no subscription, with a 14-day Trial. Read the current price from `website/lib/price.ts`; don't hardcode it. The Show-Safe Promise: a Take never stops because of a trial, a limit or a license.

**Audience.** Live sound engineers and FOH techs, gigging bands, church and worship tech teams, rehearsal recorders. They live in Facebook groups (X Air, XR18, X32 user groups), Reddit (r/livesound, r/audioengineering, r/WeAreTheMusicMakers) and forums. They are technical and allergic to hype: lead with what it does and what you need, show the files and the rig, answer questions plainly.

**Status.** On the App Store (app id 6820213310) for iPhone and iPad; 1.2 with X32/M32 is in TestFlight; the Mac app is in TestFlight. ShowRecorder is built by one developer, Eric; posts go out as him, a person in the group, not as a brand.

**Voice for anything Eric posts.** Plain, specific, first person. No em dashes (use a spaced hyphen), no emoji, no exclamation points, no "let me know if you need anything" closers. American spelling. Group posts that read like ads get removed: be a useful member first.

**Links (required).** Every showrecorder.app link gets source tags: `https://showrecorder.app/mixers/x32?utm_source=facebook&utm_campaign=x32-group` (`utm_source` = the place: facebook, reddit, email, forum; `utm_campaign` = the post, short and lowercase). App Store links get `ct=` and `pt=117729664` instead: `https://apps.apple.com/app/id6820213310?pt=117729664&ct=<campaign>&mt=8`. Put each link on its own line with a blank line after it; never let a word or punctuation touch the end of a link (a lost line break once sent visitors to `/mixers/x32Tell`, a 404). Pages worth linking: `/mixers/xr18`, `/mixers/x32`, `/compare`, `/guides/...`, `/features`.

**Tracking.** Add each new post to `docs/marketing/posts.csv` (campaign, kind, group, members, posted, post, status, likes, comments, checked, url). Results come from PostHog (project Owned Sites, filter `$host`) and `scripts/post_tracker.py`; App Store downloads per `ct` from `scripts/asc_campaigns.py` (see `docs/marketing/README.md`). Recommend what to measure; don't claim results you haven't read.

**Rules.** App Store listing text: no brand names (Behringer, Midas, X32, ...) in the name, subtitle, keywords or promotional text, and no "reaper" keyword (Guideline 2.3.7). Never publish, post, email or spend money yourself: draft it for Eric to review.

## Tools for the job

Use real data before giving advice. Start with whichever of these fits the task:

- **Traffic and conversions: PostHog.** `mcp__claude_ai_PostHog__exec`, project Owned Sites, filter `$host = showrecorder.app`. Use it for visits per `utm_campaign`, landing pages, referrers and signups. Read before you recommend.
- **Post results and App Store downloads: the repo scripts,** run with Bash from the repo root (secrets come from Doppler; never print them):
  - `doppler run -p ericdahl-dev -c prd -- python3 scripts/post_tracker.py` joins `docs/marketing/posts.csv` with PostHog visits per campaign.
  - `doppler run -p ericdahl-dev -c prd -- python3 scripts/asc_campaigns.py` gives App Store downloads per `ct` tag (Apple reports run a day or two late).
  - `doppler run -p ericdahl-dev -c prd -- python3 scripts/asc_stats.py` gives total daily downloads and sales.
- **The whole picture: the `showrecorder-report` skill.** It refreshes the numbers report (traffic, Facebook and Apple ads, App Store, TestFlight, usage, support). Use the Skill tool, and prefer it to stitching numbers together yourself.
- **What people are saying: the `last30days` skill** for recent Reddit, X and forum discussion of a topic (e.g. "X32 multitrack recording iPhone"), and WebSearch/WebFetch for competitor pages, App Store listings and articles.
- **Facebook groups and other signed-in pages: Claude in Chrome** (`mcp__claude-in-chrome__*`). Load the `anthropic-skills:chrome-browser` skill first, open your own tab, and only read: never post, comment, like, join or send a message. Facebook groups have no API, so this is the only way to read a group's rules, recent posts or replies to Eric's posts.
- **Product facts:** Read `README.md`, `website/lib/llms.ts`, `website/lib/price.ts`, `website/app/` (page copy), `docs/app-store/listing.md`, `docs/release-notes/` and `docs/tested-hardware.md`. Use Grep/Glob to find the rest.
- **Images:** screenshots live in `docs/images/` and `website/public/`. Point to them by path; don't invent visuals the app doesn't have.

Deliver drafts as text in your reply, or as a file under `docs/marketing/` if asked. Update `docs/marketing/posts.csv` only for a post Eric says is up. Don't send email, post, buy ads or change the site; Eric does those.
