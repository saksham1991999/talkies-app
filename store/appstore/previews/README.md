# App previews

Three 30-second portrait previews, cut from `docs/img/talkies-explainer.mp4`
(1920x1080, 75s). Each is 1080x1920, H.264 High, yuv420p, 30fps, AAC 128k,
faststart, no device frame, no added UI.

| file | source range | what it shows |
| --- | --- | --- |
| `preview-1.mp4` | 0:00-0:30 | The premise: one viewing becomes one ticket stub, then the hall / seat / show / price fields filled in. |
| `preview-2.mp4` | 0:22-0:52 | The month in posters and the calendar, then search forgiving spaces and punctuation. |
| `preview-3.mp4` | 0:45-1:15 | The year in numbers, the FDFS and film counts, and the share card. |

The ranges overlap on purpose: the source is one continuous 75-second film, and
three non-overlapping 25-second cuts would each start and end mid-sentence of
the narration.

## The source is landscape and the format is portrait

The film is 16:9; an App Store preview is 9:16. Cropping the middle out of
1920x1080 would cut the captions off both edges, so each preview keeps the whole
frame at full width, centred on a blurred, dimmed copy of itself as fill. That
is why there are large soft bands above and below. No content is invented,
stretched or cropped out; the fill is the same frame, blurred.

Exact command, for one segment:

```sh
ffmpeg -y -ss 0 -t 30 -i docs/img/talkies-explainer.mp4 -filter_complex \
  "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,\
gblur=sigma=40,eq=brightness=-0.22:saturation=0.7[bg];\
[0:v]scale=1080:-2[fg];\
[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[v]" \
  -map "[v]" -map 0:a -c:v libx264 -preset slow -crf 20 -r 30 \
  -c:a aac -b:a 128k -movflags +faststart \
  store/appstore/previews/preview-1.mp4
```

Change `-ss`/`-t` for the other two segments (22.5/30 and 45/30).

## Ship or not

Ship them only if you are willing to also upload a real device capture later.
They explain the product well and the first preview is seen before anything else
on the listing, but a preview that is visibly a landscape film inside soft bars
reads as a marketing video, not as the app. App review accepts it, because the
bar is technical (size, duration, codec) and there is no device frame to reject.

If you want a preview that looks like the app, record it on a simulator instead
of cutting this film: a 30-second portrait screen recording of the diary scrolling
is worth more than any narrated graphic here. Nothing in this folder is required
by App Store Connect: `tool/asc.py` uploads screenshots only and never touches
`store/appstore/previews/`.
