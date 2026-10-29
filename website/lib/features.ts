// Feature list for /features (#350). Every entry was checked against the file named in its source comment
// (paths relative to the ShowRecorder repo). Tiers match the paywall (Packages/ShowRecorderKit/Sources/Recording/ProOffer.swift,
// `Paywall.features`) and ADR 0004.

export const featureGroups: {
  id: string;
  title: string;
  intro?: string;
  features: { title: string; body: string; tier: 'free' | 'pro' }[];
}[] = [
  {
    id: 'recording',
    title: 'Recording',
    intro: 'One file per USB Channel, recorded on your iPhone or iPad.',
    features: [
      // source: docs/adr/0004-one-time-pro-unlock-and-show-safe-limits.md (Free records every USB Channel, 2026-10-15, #705)
      {
        title: 'Every USB Channel',
        body: 'Free records every USB Channel the mixer sends, on the Device: 18 Stems from an XR18 or MR18, in step with each other.',
        tier: 'free',
      },
      // source: docs/adr/0001-mono-bwf-per-stem.md, Packages/ShowRecorderKit/Sources/BroadcastWave/StemWriter.swift (bytesPerSample = 3, bext chunk)
      {
        title: '24-bit Broadcast WAV',
        body: 'Each Stem is a mono 24-bit Broadcast WAV with a time stamp, so it drops straight into your DAW.',
        tier: 'free',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/SampleRateSetting.swift (capAt48k for Free)
      {
        title: '48 kHz',
        body: 'Records at the mixer\'s 48 kHz. Free records at 44.1 or 48 kHz on any interface.',
        tier: 'free',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/SampleRateSetting.swift, Packages/ShowRecorderKit/Sources/Recording/ProOffer.swift ("96 kHz recording")
      {
        title: '96 kHz',
        body: 'Pro records at up to 96 kHz on an audio interface that offers it. Choose the rate under Settings > Recording > Sample rate.',
        tier: 'pro',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/PreRollSetting.swift (choices 0, 5, 10, 20; default 10), App/RecordScreen.swift (preRollNote)
      {
        title: 'Pre-roll',
        body: 'A Take starts with the last 5, 10 or 20 seconds before you pressed record, so the count-in is not lost.',
        tier: 'free',
      },
      // source: App/RecordScreen.swift (markerButton, "Add Marker"), Packages/ShowRecorderKit/Sources/Recording/TakeSession.swift (addMarker)
      {
        title: 'Markers',
        body: 'Tap the flag during a Take to mark a song or a moment. Markers go into every Stem and the Reaper project. Free has up to 3 per Take; Pro has no limit.',
        tier: 'free',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/CutOffTake.swift (header committed every 2 s), docs/app-store/listing.md
      {
        title: 'Safe from a crash',
        body: 'Files are saved every 2 seconds. If the app is closed mid-Take, it finishes that Take the next time it opens.',
        tier: 'free',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/TakeSession.swift (Dropout markers), docs/adr/0001-mono-bwf-per-stem.md, CONTEXT.md (Dropout)
      {
        title: 'Dropouts marked, files in sync',
        body: 'Audio that is lost, such as during a phone call, is kept as silence of the exact length with a Dropout Marker, so every file stays in sync with your video.',
        tier: 'free',
      },
    ],
  },
  {
    id: 'names-and-mixer',
    title: 'Names and mixer',
    intro: 'Stems arrive named after what is on them.',
    features: [
      // source: App/SettingsView.swift (Mixer Link section), Packages/ShowRecorderKit/Sources/MixerLink/MixerLink.swift
      {
        title: 'Mixer Link',
        body: 'Over the mixer\'s Wi-Fi, ShowRecorder reads your channel names and colors. Recording never depends on it, and no internet is needed.',
        tier: 'free',
      },
      // source: App/FindMixersRow.swift ("Find Mixers")
      {
        title: 'Find Mixers',
        body: 'Find Mixers lists the mixers on your network. Tap one to link it; there is no IP address to type.',
        tier: 'free',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/StemFileName.swift, Packages/ShowRecorderKit/Sources/Recording/Entitlement.swift (mixerLinkNames: false on Free)
      {
        title: 'Names and colors from the mixer',
        body: 'Channel 3 arrives as "03 Snare.wav", not "USB 03". On Free, the meters show the names and the Stems have generic names.',
        tier: 'pro',
      },
      // source: App/ChannelNamesView.swift ("Channel names"), Packages/ShowRecorderKit/Sources/Recording/Recorder.swift (namingByHand)
      {
        title: 'Typed Channel names',
        body: 'Type a name for any USB Channel on the Channel names page, with shortcut chips and names you used before. The files take the names when the Take ends.',
        tier: 'pro',
      },
    ],
  },
  {
    id: 'copies',
    title: 'Copies',
    intro: 'Two Copies of every Take, written at the same time.',
    features: [
      // source: App/SettingsView.swift (Storage, "Choose Drive Folder…"), Packages/ShowRecorderKit/Sources/Recording/Show.swift (createNextTakeFolder)
      {
        title: 'Device and Drive at once',
        body: 'Choose a folder on a USB drive and every Take is written to the Device and the Drive together. Neither Copy is the primary.',
        tier: 'pro',
      },
      // source: Packages/ShowRecorderKit/Sources/Recording/TakeRepair.swift, Packages/ShowRecorderKit/Sources/Recording/DestinationAlert.swift
      {
        title: 'Repair',
        body: 'If the Drive drops out, recording continues on the Device. After the Take, the Gap is filled in from the other Copy.',
        tier: 'pro',
      },
    ],
  },
  {
    id: 'on-stage',
    title: 'On stage',
    intro: 'Readable from across the room.',
    features: [
      // source: CONTEXT.md (Target band), docs/adr/0005-level-meter-scale.md, App/MeterGrid.swift
      {
        title: 'Big meters with a target band',
        body: 'Each USB Channel has a tall meter for Peak and Average level, with a shaded band from -18 to -15 dBFS to aim for.',
        tier: 'free',
      },
      // source: CONTEXT.md (Clip mark), App/MeterGrid.swift (tap to clear)
      {
        title: 'Clip marks',
        body: 'A red mark appears above any channel that reaches full scale and stays until you tap that lane.',
        tier: 'free',
      },
      // source: App/AppearanceStyle.swift (System, Dark, Sunlight)
      {
        title: 'Sunlight and Dark',
        body: 'Sunlight gives a white background, black text and strong colors for a bright stage. Dark is for a dark room.',
        tier: 'free',
      },
      // source: App/MeterGrid.swift (accessibilityValue), App/RecordScreen.swift (accessibility labels)
      {
        title: 'VoiceOver',
        body: 'Meters, Record, the Marker button and the Take time all work with VoiceOver.',
        tier: 'free',
      },
    ],
  },
  {
    id: 'after-the-show',
    title: 'After the show',
    intro: 'Ready to mix when you get home.',
    features: [
      // source: Packages/ShowRecorderKit/Sources/ShowReport/ShowReport.swift (Report.html, Channels.csv)
      {
        title: 'Show report',
        body: 'Each Show gets a report of its Takes, levels and any Gaps, as Report.html and Channels.csv in the Show folder.',
        tier: 'pro',
      },
      // source: Packages/ShowRecorderKit/Sources/ProjectExport/ReaperExporter.swift, Packages/ShowRecorderKit/Sources/Recording/ShowProject.swift
      {
        title: 'Reaper project',
        body: 'A Reaper project with one track per USB Channel, every Take in place and every Marker on the timeline.',
        tier: 'pro',
      },
      // source: project.yml (UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace), App/ShowListView.swift (ShareLink "Share")
      {
        title: 'Files app, AirDrop and Share',
        body: 'Shows are in the Files app under ShowRecorder. Tap Share on a Show to send its folder with AirDrop or any app.',
        tier: 'free',
      },
    ],
  },
  {
    id: 'templates',
    title: 'Templates',
    features: [
      // source: Packages/ShowRecorderKit/Sources/Recording/Template.swift, App/NewShowSheet.swift ("Save this setup as a Template…")
      {
        title: 'Templates for each venue',
        body: 'Save a room\'s setup (channel names, mixer, Show name and Pre-roll) and start a Show from it in one tap.',
        tier: 'pro',
      },
    ],
  },
];

// In the public TestFlight beta, not yet in the App Store release (1.1). Each was checked against its availability
// rule: shown to TestFlight builds, never only Debug. Move an entry into featureGroups when 1.1 ships.
export const inBetaFeatures: { title: string; body: string; tier?: 'pro' }[] = [
  // source: Watch/ (the watch app, in TestFlight since 1.1.3)
  {
    title: 'Apple Watch remote',
    body: 'See whether the iPhone is Ready or recording and for how long, drop Markers, start a Take and stop it with a press and hold, from your wrist.',
  },
  // source: LiveActivity/TakeLiveActivityWidget.swift
  {
    title: 'Live Activity',
    body: 'The running Take, its time and Marker count on the Lock Screen and in the Dynamic Island, with an alert if a problem starts.',
  },
  // source: Packages/ShowRecorderKit/Sources/Recording/AutoGainAvailability.swift (Debug and TestFlight, #691)
  {
    title: 'Auto-gain',
    tier: 'pro',
    body: 'Over Mixer Link, sets each channel\'s preamp to -18 dBFS and moves the fader, sends and dynamics the other way, so the mix stays the same. Undo puts it all back.',
  },
  // source: Packages/ShowRecorderKit/Sources/Recording/ClipProtection.swift (ClipProtectionSetting.isOffered: Debug and TestFlight, #699)
  {
    title: 'Clip protection',
    tier: 'pro',
    body: 'During a Take, turns a clipping channel\'s preamp down on the mixer and raises its fader to match, at most 12 dB per Take, with a Marker for each move. Off until you switch it on.',
  },
];
