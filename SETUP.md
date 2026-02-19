# SMS Spam Filter — Xcode Setup Guide

## Prerequisites
- macOS with Xcode 15+
- iPhone with iOS 16+ connected via USB
- Apple Developer account (free is fine for side-loading)

## Step 1: Train the Model (Python)

```bash
cd /path/to/SMSSpamFilter
pip install scikit-learn pandas
python train_sms_classifier.py
```

This produces `SMSSpamClassifier.json` (~280 KB) containing the TF-IDF vocabulary, IDF weights, and logistic regression coefficients. The Swift extension does native inference (no Core ML dependency).

## Step 2: Create Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Product Name: `SMSSpamFilter`, Interface: **SwiftUI**, Language: **Swift**
4. Save to this directory (alongside the existing files)

## Step 3: Add Source Files

1. Delete the auto-generated `ContentView.swift` from the project
2. Drag `SMSSpamFilter/ContentView.swift` and `SMSSpamFilter/SMSSpamFilterApp.swift` into the SMSSpamFilter group in Xcode's navigator
3. Make sure "Copy items if needed" is unchecked (files are already in place)

## Step 4: Add Message Filter Extension

1. **File → New → Target**
2. Search for **Message Filter Extension**
3. Product Name: `MessageFilterExtension`, Language: **Swift**
4. Activate the scheme when prompted
5. Delete the auto-generated `MessageFilterExtension.swift`
6. Drag in `MessageFilterExtension/MessageFilterExtension.swift` from this repo
7. Set the extension's Info.plist to `MessageFilterExtension/Info.plist`

## Step 5: Add Model Weights

1. Drag `SMSSpamClassifier.json` into the project navigator
2. In the file inspector, check BOTH targets: `SMSSpamFilter` and `MessageFilterExtension`
3. Verify it appears in **Build Phases → Copy Bundle Resources** for both targets

## Step 6: Configure App Groups

For **both targets** (SMSSpamFilter app + MessageFilterExtension):

1. Select target → **Signing & Capabilities** tab
2. Click **+ Capability → App Groups**
3. Add: `group.com.aaron.SMSSpamFilter`

The `.entitlements` files in this repo already have the correct group name.

## Step 7: Build & Deploy

1. Connect iPhone via USB
2. Select your device in Xcode's device selector
3. **Product → Run** (Cmd+R)
4. On iPhone: **Settings → General → VPN & Device Management** → trust your developer profile

## Step 8: Enable the Filter

1. **Settings → Messages → Unknown & Spam**
2. Enable **Filter Unknown Senders**
3. Under **SMS FILTERING**, select **SMSSpamFilter**

## Testing

- Send yourself an SMS from a different number (Google Voice, friend's phone)
- Spam test: "Congratulations! You've won a FREE iPhone! Click here now!"
- Ham test: "Hey, are we still meeting for lunch tomorrow?"
- Monitor: Console.app on Mac, filter process `MessageFilterExtension`
- Check stats in the companion app after filtering occurs

## Troubleshooting

- **Extension not appearing in Settings:** Make sure the Message Filter Extension target builds and deploys alongside the main app. Check that the extension's bundle is embedded in the app.
- **Model not found error:** Verify `SMSSpamClassifier.json` is in both targets' "Copy Bundle Resources" build phase.
- **Stats not updating:** Confirm both targets have the same App Group (`group.com.aaron.SMSSpamFilter`).
