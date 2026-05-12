#!/usr/bin/env -S wordgrinder --lua

local function main(inputfile, tmpdir)
    if not inputfile or not tmpdir then
        io.stderr:write("usage: wordgrinder --lua wd-export.lua <file.wg> <tmpdir>\n")
        os.exit(1)
    end
    if not Cmd.LoadDocumentSet(inputfile) then
        io.stderr:write("wd-export: failed to load " .. inputfile .. "\n")
        os.exit(1)
    end
    local docs = documentSet:getDocumentList()
    for i, doc in ipairs(docs) do
        local outpath = string.format("%s/%03d.txt", tmpdir, i)
        Document = doc
        if not Cmd.ExportTextFile(outpath) then
            io.stderr:write("wd-export: failed to write " .. outpath .. "\n")
            os.exit(1)
        end
        print(doc.name .. "\t" .. outpath)
    end
end

main(...)
os.exit(0)
