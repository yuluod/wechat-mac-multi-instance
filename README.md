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

Clone the repository:

```bash
git clone <YOUR_REPOSITORY_URL>
cd wechat-mac-multi-instance
```

Make the script executable:

```bash
chmod +x wechat-multi.sh
```

Create the second WeChat instance:

```bash
./wechat-multi.sh install
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

This script intentionally does **not** manipulate WeChat chat databases or data directories.

In particular, it does not copy, delete, or modify paths under:

```text
~/Library/Containers/
```

or WeChat 4.x data such as:

```text
xwechat_files
```

Updating WeChat2 only replaces the application bundle while keeping the same secondary Bundle ID:

```text
com.tencent.xinWeChat2
```

Back up important WeChat data separately before making major application or macOS upgrades.

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

If you want to remove associated application data as well, identify and back up the relevant data first rather than deleting it blindly.

## License

MIT