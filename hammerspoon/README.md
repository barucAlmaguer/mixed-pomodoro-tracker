# Hammerspoon Integration

El código de la barra de menú y panel flotante de macOS vive ahora **dentro del repo** (`hammerspoon/pomo.lua`) y se carga dinámicamente desde `~/.hammerspoon/`.

## Instalación

```bash
# 1. Backup de config anterior (si existe)
mv ~/.hammerspoon/init.lua ~/.hammerspoon/init.lua.backup.$(date +%Y%m%d) 2>/dev/null || true

# 2. Crear stub que apunta al repo
cat > ~/.hammerspoon/pomo.lua << 'EOF'
-- Stub: carga el código versionado desde el repo
local repo_path = os.getenv("HOME") .. "/repos/valiot/pomodoro_tracker/hammerspoon/pomo.lua"
local module, err = loadfile(repo_path)
if not module then
  hs.notify.new({title="Pomo Error", informativeText="No se pudo cargar: " .. tostring(err)}):send()
  error(err)
end
return module()
EOF

# 3. Crear init.lua que inicia el módulo
echo 'require("pomo").start()' > ~/.hammerspoon/init.lua

# 4. Recargar Hammerspoon (o Cmd+Alt+Shift+H → Reload Config)
hs -c "hs.reload()" 2>/dev/null || echo "Recarga manual requerida desde el menú de Hammerspoon"
```

## ¿Por qué este patrón?

| Antes | Después |
|-------|---------|
| Código en `~/.hammerspoon/pomo/` (fuera de git) | Código en `hammerspoon/pomo.lua` (versionado) |
| Editar código = cambios sin trackear | Todo commit está en el repo |
| Reload de Hammerspoon requería copiar archivos | El stub usa `loadfile()` → siempre carga última versión del disco |

## Desarrollo

Edita directamente `hammerspoon/pomo.lua` en el repo. Al hacer reload en Hammerspoon (Cmd+Alt+Shift+H), se recarga automáticamente desde el disco.

## Hot Reload

El stub usa `loadfile()` en lugar de `require()`, así que cada reload de Hammerspoon lee el archivo físico del disco. No hay cache de Lua entre reloads.
