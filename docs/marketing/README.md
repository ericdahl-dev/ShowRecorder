# Facebook posts

`posts.csv` is the post log: one row per Facebook group post, ad set or Page link, with the `utm_campaign`
its showrecorder.app link carries. Add a row when a post goes up, and update `likes`, `comments`, `status`
and `checked` when someone reads them on Facebook (Facebook groups have no API, so this is by hand).

`scripts/post_tracker.py` joins the log with PostHog visits per campaign:

```
doppler run -p ericdahl-dev -c prd -- python3 scripts/post_tracker.py
```

`--json DIR` writes the files behind the tracker page, and `--dashboard` creates or updates the
PostHog dashboard "Facebook posts" (project Owned Sites), which stays live on its own.

# App Store downloads per campaign

App Store links on the site and in posts carry a campaign tag (`ct=site-xr18`, `ct=fbad-xr18`, ...) with
provider token `pt=117729664`. `scripts/asc_campaigns.py` reads Apple's "App Downloads Detailed" analytics
report, the only downloads report with a Campaign column, and prints first-time downloads and redownloads by
day and campaign. Downloads with no tag (App Store search, browse) are listed as `(no tag)`.

```
doppler run -p ericdahl-dev -c prd -- python3 scripts/asc_campaigns.py
doppler run -p ericdahl-dev -c prd -- python3 scripts/asc_campaigns.py --json DIR   # also write campaign_downloads.json
```

The report comes from the app's ONGOING analytics report request, which already exists (Apple adds one
report instance per day). `--create-request` makes one only if it is ever missing. Apple publishes each day
a day or two late, and leaves out rows below its privacy threshold, so a campaign with a handful of downloads
may not show up at all; the daily sales reports (`scripts/asc_stats.py`) have the full download count.
