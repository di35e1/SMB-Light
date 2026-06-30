#!/bin/bash

APP_NAME="SMB Light"
ICON_NAME="icon.icns"
BG_IMAGE="background.png"
VERSION="3.0 beta"
DMG_NAME="${APP_NAME}_${VERSION}.dmg"
VOL_NAME="${APP_NAME} installation"

echo "Подготовка DMG"
rm -f "$DMG_NAME"
rm -f "tmp.dmg"

# Создаем пустой растущий образ
hdiutil create -size 200m -fs HFS+ -volname "$VOL_NAME" -ov -type SPARSE "tmp.dmg"

# Монтируем его
MOUNT_DIR=$(hdiutil attach -nobrowse "tmp.dmg.sparseimage" | grep -o '/Volumes/.*')
rm -f "$MOUNT_DIR/.DS_Store"

# Копируем приложение и создаем симлинк
cp -R "dist/." "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Копируем иконку для тома
cp "$ICON_NAME" "$MOUNT_DIR/.VolumeIcon.icns"
setfile -a C "$MOUNT_DIR"

echo "Настройка фона и иконок через AppleScript"
mkdir "$MOUNT_DIR/.background"
cp "$BG_IMAGE" "$MOUNT_DIR/.background/"

# AppleScript для настройки окна Finder
echo "
tell application \"Finder\"
    tell disk \"$VOL_NAME\"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        
        -- Настройка размеров окна (x1, y1, x2, y2)
        -- Подгони под размер твоей картинки (например, 600x400)
        set the bounds of container window to {400, 100, 1000, 500}
        
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        
        -- Установка фона
        set background picture of viewOptions to file \".background:$BG_IMAGE\"
        
        -- Расстановка иконок (x, y)
        -- Подгони координаты под пустые места на картинке
        set position of item \"$APP_NAME.app\" of container window to {165, 205}
        set position of item \"Applications\" of container window to {440, 205}
        
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
" | osascript

echo "--------------------------------------------------------"
echo "ПАУЗА: Окно DMG настроено автоматически."
echo "Проверь, ровно ли встали иконки в пустые слоты на фоне."
echo "При необходимости поправь их руками."
echo "Нажми ЛЮБУЮ КЛАВИШУ в терминале для финальной сборки."
echo "--------------------------------------------------------"

read -n 1 -s

# Размонтируем
hdiutil detach "$MOUNT_DIR"

echo "Финализация DMG"
hdiutil convert "tmp.dmg.sparseimage" -format UDZO -o "$DMG_NAME"
rm "tmp.dmg.sparseimage"

echo "Образ создан: $DMG_NAME ---"
open -R "$DMG_NAME"