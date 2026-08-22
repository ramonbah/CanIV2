# README screenshot capture

Capture these five screens from an **iPhone 17 simulator in portrait**, using the same deterministic fictional dataset and the app's default text size.

| File | Screen | What should be visible |
| --- | --- | --- |
| `home.png` | Home | Net cash-flow header and trend, three recent Transactions, and active Plans |
| `plan-items.png` | Plan detail | Available, Spent/Overspent, and Income tabs with representative Items |
| `transactions.png` | Transactions | Submitted results plus expanded hierarchical Budget → Plan → Item filters |
| `reports.png` | Plan Reports | A meaningful report chart, summary, and breakdown |
| `time-effort.png` | Time Effort | Calculator result and assumptions, with salary itself hidden |

## Capture rules

- Use fictional names and amounts only.
- Keep the same currency, theme, locale, and simulator time across every image.
- Use light mode for the main set; dark-mode images can be added later if useful.
- Keep the status bar visible and do not include Xcode chrome.
- Ensure no sheet is partly presented and no row is mid-swipe.
- Hide the salary before capturing Time Effort.
- Save the images at their native simulator resolution without manual cropping.

Xcode or a simulator-capable coding agent can launch the app, seed the data, navigate to each state, and save screenshots with Simulator's capture command or `xcrun simctl io booted screenshot <path>`.

After all five files exist, replace the screenshot comment in the root `README.md` with the prepared Markdown table inside that comment.
