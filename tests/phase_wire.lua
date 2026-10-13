local wire=dofile('mod/scripts/phase_wire.lua')
local valid='EXEC|test-session|guest|0|player2|artillery\n{"state":"bounded"}'
assert(wire.decode(valid,'test-session').id=='artillery')
assert(not pcall(wire.decode,valid,'other-session'))
assert(not pcall(wire.decode,valid:gsub('EXEC','EVAL'),'test-session'))
assert(not pcall(wire.decode,valid:gsub('|0|','|0.5|'),'test-session'))
assert(not pcall(wire.decode,valid..'\nsecond-frame','test-session'))
assert(not pcall(wire.decode,string.rep('x',70001),'test-session'))
print('6 mailbox framing contracts passed; no game or filesystem execution implied.')
