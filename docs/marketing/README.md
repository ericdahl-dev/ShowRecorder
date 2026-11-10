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
