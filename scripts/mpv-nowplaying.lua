-- Write icy-title / track name for the HDMI ticker. No extra runtime.
local out = "/tmp/airradio-nowplaying.txt"

local function write_title()
    local md = mp.get_property_native("metadata") or {}
    local title = md["icy-title"] or md["ICY-TITLE"] or md["title"] or md["TITLE"]
        or mp.get_property("media-title") or ""
    if title:find("streamtheworld", 1, true) or title:find("NOSTALGIEWHATAFEELING", 1, true) then
        title = ""
    end
    local f = io.open(out, "w")
    if f then
        f:write(title)
        f:close()
    end
end

mp.observe_property("metadata", "native", function() write_title() end)
mp.register_event("file-loaded", write_title)
write_title()
