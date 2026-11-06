# Developer ID署名とApple公証

`scripts/notarize-release.sh`はarm64・x86_64のUniversal版をビルドし、Developer ID署名、Appleへの公証申請、チケット添付、配布ZIPの生成と再検証を実行します。出力は申請ごとに`dist/notarization/run-*/`へ保存します。開発用の`dist/PortLens.app`や起動中のアプリを置き換えません。

## 初回の確認結果（2026-11-06）

- 対象：PortLens `0.1.0 (2)`、Bundle ID `local.portlens.PortLens`、arm64・x86_64。
- Apple申請ID：`240fca6f-ba6b-4bd7-81e3-e4f9146ee8a4`。
- 結果：`Accepted`、Appleログの`issues: null`。
- チケット添付後と最終ZIP展開後の署名・チケット検証、Gatekeeperの`accepted / Notarized Developer ID`を確認。
- arm64とRosetta 2のx86_64でデモスナップショットの一致を確認。署名済み実行ファイルから実際の`system_profiler`データも取得できた。共通検証は18件すべて成功。
- 記録と成果物：`dist/notarization/run-20261106-133227.A3RslZ/`。
- 最終ZIPのSHA-256：`4e5f6d99ac840081bb68df18821c1472a6f8a27b5df2f3f3ba063f7a3fc6f49d`。

配布先はGitHubリリース[`v0.1.0-notarized`](https://github.com/bassmicrobe/PortLens/releases/tag/v0.1.0-notarized)です。GUIの全機能やIntel実機での確認は、この検証には含みません。

## 実行

有効なDeveloper ID Application証明書と対応する秘密鍵、同じチームの`notarytool`キーチェーンプロファイルが必要です。パスワードや秘密鍵をリポジトリやコマンド引数に保存しないでください。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SIGNING_IDENTITY='CERTIFICATE_SHA1_FINGERPRINT'
export TEAM_ID='APPLE_DEVELOPER_TEAM_ID'
export NOTARY_PROFILE='EXISTING_KEYCHAIN_PROFILE'
# 専用キーチェーンを使う場合のみ指定します。
export SIGNING_KEYCHAIN='/absolute/path/to/signing.keychain-db'
./scripts/notarize-release.sh
```

このMacでは、前のSampleGlide公証時に作成したCybereye Technology Co., Ltd.（`8XUK86NH38`）の証明書と`sampleglide-notary`プロファイルを再利用しています。ローカルの実行用設定は、Git対象外の`.local/signing/notarize-this-mac.command`にあります。アプリごとに証明書を発行し直す必要はありません。別の所有者・チームへ配布する場合は設定を選び直してください。

キーチェーンが署名の認証を求めた場合は、画面に表示されたキーチェーンのパスワードを本人が入力します。Apple Accountやアプリ用パスワードとは別のものです。

## 成果物と検証

- `PortLens-<version>-universal-notarized.zip`：Accepted後にチケットを添付したアプリから作成した配布ZIP。
- `PortLens-<version>-notarized-SHA256SUMS.txt`：最終ZIPのSHA-256。
- `submission.json`・`status.json`・`notary-log.json`：Apple申請IDと結果。
- `signature.txt`・`gatekeeper.txt`・`extracted-gatekeeper.txt`：署名とGatekeeperの検証記録。
- `build-context.txt`：ビルド時のコミット、未コミットの変更一覧、Swiftバージョン。
- `extracted/PortLens.app`：最終ZIPを展開して再検証したアプリ。

署名にHardened Runtimeとタイムスタンプを使い、チームを照合します。現在のアプリは単一実行ファイルとリソースのみで、追加のentitlementsは不要です。helper・framework・dylibを追加した場合は、個別の署名順序と権限を設計するまでスクリプトが停止します。

Universalビルドでは、SwiftPMがアーキテクチャ間で同じ製品パスを使っても上書きされないよう、各ビルド直後に実行ファイルを退避してから結合します。`lipo -verify_arch`はアーキテクチャごとに実行します。

Appleの`Accepted`を確認するまでは配布ZIPを生成しません。添付後とZIP展開後の両方で、チケット、厳密な署名、Universalのアーキテクチャ、Gatekeeperの`Notarized Developer ID`を確認します。申請ZIPと最終配布ZIPのハッシュは異なります。

## 中断した申請

失敗時にも作業フォルダを残します。`submission.json`の`id`が存在する場合は、同じIDで状態を確認します。タイムアウト後もApple側の処理は続くため、すぐに新規申請し直さないでください。

```sh
xcrun notarytool info SUBMISSION_ID --keychain-profile "$NOTARY_PROFILE"
xcrun notarytool wait SUBMISSION_ID --keychain-profile "$NOTARY_PROFILE" --timeout 30m
xcrun notarytool log SUBMISSION_ID --keychain-profile "$NOTARY_PROFILE" /path/to/notary-log.json
```

Accepted後の復旧時は、同じ作業フォルダの`PortLens.app`へ`xcrun stapler staple`を実行し、検証してからZIPを作り直します。申請中のアプリは変更しないでください。

`scripts/package-release.sh`は従来の開発用アドホック署名ZIPを作るコマンドです。公証版の配布には`notarize-release.sh`の出力を使用します。GitHubへのアップロードやインストールはこのスクリプトには含みません。

## 公式資料

- [Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple：Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
