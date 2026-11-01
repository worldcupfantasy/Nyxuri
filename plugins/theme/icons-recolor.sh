#!/usr/bin/env bash
# 由 Noctalia 主题引擎渲染（theme.templates.user.icons_recolor）。
# 用当前 Material You 调色板重染 Adwaita-Matugen 图标主题的文件夹图标。
#
# 为什么 A/B 交替：GTK 按图标主题名做缓存，原地改同名目录不会刷新。
# 每次写入「另一个」变体再把 gsettings 切过去，等于强制所有应用重新加载。

set -euo pipefail

COLOR_DARK="{{ colors.secondary.default.hex }}"
COLOR_LIGHT="{{ colors.secondary_container.default.hex }}"

TEMPLATE_DIR="$HOME/.config/matugen/templates/gtk-folder/Adwaita-Matugen"
[[ -d "$TEMPLATE_DIR" ]] || exit 0
command -v gsettings >/dev/null 2>&1 || exit 0

# 同一时刻只允许一个实例（钩子在后台异步跑，主题连续切换会重入）
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/nyxuri-icons-recolor.lock"
flock -n 9 || exit 0

CURRENT=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
if [[ "$CURRENT" == "Adwaita-Matugen-A" ]]; then
    TARGET="Adwaita-Matugen-B"
else
    TARGET="Adwaita-Matugen-A"
fi
TARGET_DIR="$HOME/.local/share/icons/$TARGET"

mkdir -p "$TARGET_DIR"
cp -rf --reflink=auto --no-preserve=mode,ownership "$TEMPLATE_DIR/"* "$TARGET_DIR/"
sed -i "s/^Name=.*/Name=$TARGET/" "$TARGET_DIR/index.theme"

# 16x16 PNG 文件夹图标：灰度化后套双色渐变
find "$TARGET_DIR" -name '*.png' -print0 | xargs -0 -r -P0 -I {} magick "{}" \
    -channel RGB -colorspace gray -sigmoidal-contrast 10,50% \
    +level-colors "#1a5fb4","$COLOR_DARK" +channel "{}"

# SVG 只替换 6 个原本的蓝色 accent，其余颜色保持 Adwaita 原样
find "$TARGET_DIR" -name '*.svg' -print0 | xargs -0 -r -P0 sed -i \
    -e "s/#3f8ae5/$COLOR_DARK/g" \
    -e "s/#438de6/$COLOR_DARK/g" \
    -e "s/#62a0ea/$COLOR_DARK/g" \
    -e "s/#a4caee/$COLOR_LIGHT/g" \
    -e "s/#afd4ff/$COLOR_LIGHT/g" \
    -e "s/#c0d5ea/$COLOR_LIGHT/g"

gtk-update-icon-cache -f -t "$TARGET_DIR" >/dev/null 2>&1 || true

# 真正让应用换图标主题：gsettings（portal 读它）+ GTK 配置文件兜底
gsettings set org.gnome.desktop.interface icon-theme "$TARGET" 2>/dev/null || true
for version in gtk-3.0 gtk-4.0; do
    ini="$HOME/.config/$version/settings.ini"
    [[ -f "$ini" ]] || continue
    if grep -q '^gtk-icon-theme-name' "$ini"; then
        sed -i "s|^gtk-icon-theme-name.*|gtk-icon-theme-name = $TARGET|" "$ini"
    else
        sed -i "/^\[Settings\]/a gtk-icon-theme-name = $TARGET" "$ini"
    fi
done

flatpak override --user --env=ICON_THEME="$TARGET" 2>/dev/null || true

exit 0
