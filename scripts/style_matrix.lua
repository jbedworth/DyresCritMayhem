-- Prints every theme's style for every damage school kind, from Themes.lua
-- itself, for scripts/build_matrix_preview.py. Run from the repository root:
--   lua5.1 scripts/style_matrix.lua [adult]
-- One line per drawn texture: theme kind texture r g b blend (adult or not
-- decides Spellburst's physical look).
local adult = arg and arg[1] == "adult"
-- "feral": your crits as in Cat or Bear form (Naturalist's claws).
local feral = arg and arg[1] == "feral"
local DCM = {}
function DCM.IsSecret() return false end
function DCM.IsAdult() return adult end
function DCM.random() return 1 end
local chunk = assert(loadfile("Themes.lua"))
chunk("DyresCritMayhem", DCM)

local MASKS = {{"physical", 1}, {"holy", 2}, {"fire", 4}, {"nature", 8}, {"frost", 16}, {"shadow", 32},
    {"arcane", 64}}
for _, theme in ipairs(DCM.Themes()) do
    for _, entry in ipairs(MASKS) do
        local kind, mask = entry[1], entry[2]
        DCM.feralForm = feral
        local style = DCM.CritStyle(theme, mask, {kind = "mine"})
        local seen = {}
        local textures = {}
        for _, texture in ipairs(style.splats) do textures[#textures + 1] = texture end
        local accentColors = {}
        if style.accent then
            local accent = style.accent.textures[1]
            table.insert(textures, 2, accent)
            accentColors[accent] = style.accent
        end
        for _, texture in ipairs(textures) do
            if not seen[texture] then
                seen[texture] = true
                local own = style.textureColors and style.textureColors[texture]
                local accent = accentColors[texture]
                local color = accent and accent.colors[1] or own and own[1]
                    or style.schoolColors and DCM.SchoolColor(style, mask) or style.colors[1]
                if style.untinted and style.untinted[texture] then
                    color = {1, 1, 1}
                end
                local blend = accent and (accent.blend or "BLEND")
                    or style.textureBlend and style.textureBlend[texture] or style.blend or "BLEND"
                print(("%s %s %s %.3f %.3f %.3f %s"):format(theme.key, kind, texture:match("([%w]+)$"), color[1],
                    color[2], color[3], blend))
            end
        end
    end
end
