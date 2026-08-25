# WeChat Mac Multi-Instance

![Platform](https://img.shields.io/badge/platform-macOS-blue?logo=apple)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

Run a second instance of WeChat on macOS with an independent Bundle ID.

This project creates:

```text
/Applications/WeChat.app
/Applications/WeChat2.app
```

The second application uses:

```text
com.tencent.xinWeChat2
```

instead of the official:

```text
com.tencent.xinWeChat
```

This allows macOS to treat `WeChat2.app` as a separate application.

## Features

- Create a second WeChat application
- Update WeChat2 after the official WeChat is updated
- Preserve the existing WeChat2 Bundle ID
- Ad-hoc re-sign the modified application
- Check WeChat and WeChat2 versions
- Verify the modified application signature
- Keep the previous WeChat2 version as a backup
- Roll back to the previous version
- Does not copy, modify, migrate, or delete WeChat chat data

## Requirements

- macOS
- WeChat for Mac installed at:

```text
/Applications/WeChat.app
```

- Administrator access (`sudo`)

The script uses standard macOS utilities including:

```text
PlistBuddy
codesign
osascript
pkill
```

No third-party dependencies are required.

## Installation

The whole tool is a single script. Cloning the repository is not required.

### Option 1: Download the script only (recommended)

```bash
curl -fsSL -o wechat-multi.sh \
    https://raw.githubusercontent.com/yuluod/wechat-mac-multi-instance/main/wechat-multi.sh
chmod +x wechat-multi.sh
```

### Option 2: Clone the repository

```bash
git clone https://github.com/yuluod/wechat-mac-multi-instance.git
cd wechat-mac-multi-instance
chmod +x wechat-multi.sh
```

Create the second WeChat instance:

```bash
./wechat-multi.sh install
```

Before making any changes, the script shows a summary of what will happen and asks for confirmation:

```text
! Please review before continuing:

  - This is an unofficial workaround, not endorsed by Tencent.
  - The modified app is ad-hoc signed, not signed by Tencent.
  - A future WeChat or macOS update may break this method.
  - WeChat and WeChat2 will be closed.
  - WeChat2.app will be created in /Applications.
  - Chat data under ~/Library/Containers is NOT touched.

Continue? [y/N]
```

The same confirmation applies to `update` and `rollback`. To skip it (e.g. in automation), pass `-y` / `--yes`:

```bash
./wechat-multi.sh install --yes
```

The script will create:

```text
/Applications/WeChat2.app
```

with the Bundle ID:

```text
com.tencent.xinWeChat2
```

After installation, WeChat2 will be opened automatically.

Log in to your second WeChat account normally.

## Updating WeChat2

When WeChat releases a new version, update the official `WeChat.app` first.

After confirming the official WeChat works correctly, run:

```bash
./wechat-multi.sh update
```

The script will:

1. Check the current WeChat and WeChat2 versions.
2. Close WeChat.
3. Rename the existing `WeChat2.app` to `WeChat2.old.app`.
4. Copy the latest official `WeChat.app`.
5. Change its Bundle ID to `com.tencent.xinWeChat2`.
6. Re-sign the modified application.
7. Verify the signature.
8. Start the updated WeChat2.

The old application is retained at:

```text
/Applications/WeChat2.old.app
```

After confirming that the updated WeChat2 works correctly, it can be removed:

```bash
sudo rm -rf /Applications/WeChat2.old.app
```

## Check Status

Run:

```bash
./wechat-multi.sh status
```

Example:

```text
----------------------------------------
WeChat
  Version:   4.x.x
  Bundle ID: com.tencent.xinWeChat

WeChat2
  Version:   4.x.x
  Bundle ID: com.tencent.xinWeChat2

Backup
  None
----------------------------------------
```

## Rollback

If an updated WeChat2 does not work correctly and `WeChat2.old.app` is still available:

```bash
./wechat-multi.sh rollback
```

The current WeChat2 application will be removed and the previous application restored.

## Chat Data

### Data Isolation

Because WeChat2 uses a different Bundle ID, macOS gives it a completely separate sandbox container. The two instances never share accounts, sessions, or chat history:

```text
~/Library/Containers/com.tencent.xinWeChat/    # WeChat  data
~/Library/Containers/com.tencent.xinWeChat2/   # WeChat2 data
```

WeChat 4.x may also store chat files under a user-selected or default data directory, typically:

```text
~/Documents/xwechat_files/
```

Each logged-in account gets its own subdirectory there, so the two instances do not conflict.

### Login State Across Updates

The `update` and `rollback` commands only replace the application bundle. The Bundle ID stays `com.tencent.xinWeChat2`, so the container path does not change and WeChat2 keeps its login state and chat history after an update.

### What This Script Never Touches

This script intentionally does **not** copy, delete, or modify anything under:

```text
~/Library/Containers/
~/Documents/xwechat_files/
```

### Backup Recommendations

Before major WeChat or macOS upgrades, back up:

```text
~/Library/Containers/com.tencent.xinWeChat2/
```

and the corresponding account directories under `xwechat_files`. WeChat's built-in chat history backup/migration is also an option.

## How It Works

The official application uses the Bundle ID:

```text
com.tencent.xinWeChat
```

The script copies the application and changes the second copy to:

```text
com.tencent.xinWeChat2
```

Changing `Info.plist` invalidates the original application signature, so the modified application is re-signed locally using:

```bash
codesign --force --deep --sign -
```

The modified application is not signed by Tencent.

## Important Notes

This is an unofficial workaround and is not supported or endorsed by Tencent or WeChat.

A future WeChat or macOS update may change application sandboxing, code-signing requirements, data storage, login behavior, or other mechanisms used by this method.

Always keep important chat data backed up.

## Uninstall

Remove the second application:

```bash
sudo rm -rf /Applications/WeChat2.app
```

If a backup application exists:

```bash
sudo rm -rf /Applications/WeChat2.old.app
```

This project does not automatically delete WeChat data from `~/Library/Containers`.

If you also want to remove the WeChat2 data (this permanently deletes its login state and chat history), the container is located at:

```text
~/Library/Containers/com.tencent.xinWeChat2/
```

Back up the relevant data first rather than deleting it blindly. Data of the official WeChat under `com.tencent.xinWeChat` is not affected.

## License

MIT