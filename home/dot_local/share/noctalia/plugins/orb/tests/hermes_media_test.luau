--!nonstrict
-- Unit tests for lib/hermes/media.luau. Run with tests/run.sh.

local M = require("../lib/hermes/media")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print(`ok   {name}`)
  else
    failures += 1
    print(`FAIL {name} {detail or ""}`)
  end
end

check("ext lowercased", M.ext("/a/B.PNG") == "png")
check("basename", M.basename("/srv/out/report.pdf") == "report.pdf")
check("image by extension", M.isImage("x.jpeg") and not M.isImage("x.pdf"))
check("safe name drops slashes and leading dots", M.safeName("../../etc/passwd") == "_.._etc_passwd", M.safeName("../../etc/passwd"))
check("safe name never empty", M.safeName("...") == "file")

check("small image goes inline", M.kind("a.png", 1000, nil) == "image")
check("huge image is copied", M.kind("a.png", 6 * 1024 * 1024, nil) == "file")
check("text goes into the message", M.kind("notes.md", 5, "hello") == "text")
check("binary is copied", M.kind("a.bin", 3, "a\0b") == "file")
check("short read is not text", M.kind("a.bin", 10, "abc") == "file")
check("bad utf8 is not text", M.kind("a.txt", 2, "\255\254") == "file")

local block = M.textBlock("a.md", "has ``` inside")
check("fence outgrows the file's backticks", string.find(block, "````\nhas ``` inside\n````", 1, true) ~= nil, block)

check("plain input stays text", M.input("hi", {}) == "hi")
local parts = M.input("look", { { mime = "image/png", b64 = "QUJD" } })
check("image input parts", #parts == 2 and parts[2].image_url.url == "data:image/png;base64,QUJD")
check("image only, no empty text part", #M.input("", { { mime = "image/png", b64 = "QQ==" } }) == 1)

local text, media = M.extract("Here is the chart:\n\n![image](data:image/png;base64,iVBORw0KGgo=)\n\nDone.")
check("data image pulled out", #media == 1 and media[1].kind == "image" and media[1].mime == "image/png" and media[1].b64 == "iVBORw0KGgo=")
check("text left clean", text == "Here is the chart:\n\nDone.", text)

local t2, m2 = M.extract("Saved it. MEDIA:/home/0cto/out/report.pdf and MEDIA:`/tmp/my file.csv`.")
check("bare media path", m2[1] ~= nil and m2[1].path == "/home/0cto/out/report.pdf" and m2[1].name == "report.pdf" and not m2[1].image)
check("quoted media path with a space", m2[2] ~= nil and m2[2].path == "/tmp/my file.csv", m2[2] and m2[2].path)
check("tags removed from the text", t2 == "Saved it.  and .", t2)

local _, m3 = M.extract("**MEDIA:~/pics/cat.png**")
check("wrapped tag, home path, image", m3[1] ~= nil and m3[1].path == "~/pics/cat.png" and m3[1].image)

local t4, m4 = M.extract("The MEDIA: prefix is how files travel.")
check("MEDIA: without a path stays", #m4 == 0 and t4 == "The MEDIA: prefix is how files travel.", t4)

check("hash is stable hex", M.hash("abc") == M.hash("abc") and #M.hash("abc") == 8 and M.hash("abc") ~= M.hash("abd"))
check("fnv-1a of empty", M.hash("") == "811c9dc5", M.hash(""))
check("fnv-1a of a", M.hash("a") == "e40c292c", M.hash("a"))

local taken = { ["/d/a.txt"] = true, ["/d/a (1).txt"] = true }
check("unique name", M.unique("/d", "a.txt", function(p)
  return taken[p] == true
end) == "/d/a (2).txt")
check("unique name without extension", M.unique("/d", "Makefile", function()
  return false
end) == "/d/Makefile")

if failures > 0 then
  error(`{failures} media test(s) failed`)
end
