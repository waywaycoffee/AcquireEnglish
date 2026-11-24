#!/bin/sh
set -e
# App Store Connect rejects WechatOpenSDK when Info.plist MinimumOSVersion
# disagrees with the binary (binary is iOS 15+, plist used to say 12.0).
patch_plist() {
  plist="$1"
  [ -f "$plist" ] || return 0
  /usr/bin/plutil -replace MinimumOSVersion -string 15.0 "$plist" 2>/dev/null || true
}
# Embedded product
if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${FRAMEWORKS_FOLDER_PATH:-}" ]; then
  find "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}" -path '*/WechatOpenSDK.framework/Info.plist' 2>/dev/null | while read -r p; do
    patch_plist "$p"
  done
fi
# Source packages / pods copies that may feed embedding
if [ -n "${SRCROOT:-}" ]; then
  find "${SRCROOT}/../build" "${SRCROOT}/Pods" -path '*/WechatOpenSDK.framework/Info.plist' 2>/dev/null | while read -r p; do
    patch_plist "$p"
  done
fi
echo "patched WechatOpenSDK MinimumOSVersion -> 15.0"
