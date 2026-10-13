local wire=dofile('mod/scripts/phase_wire.lua')
local valid='EXEC|test-session|guest|0|player2|artillery\n{"state":"bounded"}'
assert(wire.decode(valid,'test-session').id=='artillery')
assert(not pcall(wire.decode,valid,'other-session'))
assert(not pcall(wire.decode,valid:gsub('EXEC','EVAL'),'test-session'))
assert(not pcall(wire.decode,valid:gsub('|0|','|0.5|'),'test-session'))
assert(not pcall(wire.decode,valid..'\nsecond-frame','test-session'))
assert(not pcall(wire.decode,string.rep('x',70001),'test-session'))
local dynamic='EXEC|test-session|guest|0|player2|move-guest-1|artillery|0|3|0|2\n{}'
local move=wire.decode(dynamic,'test-session').move
assert(move.actor=='artillery' and move.fromX==0 and move.fromY==3 and move.toY==2 and move.kind=='move')
assert(not pcall(wire.decode,dynamic:gsub('artillery','enemy'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('|0|3|0|2','|0|3|8|2'),'test-session'))
assert(not pcall(wire.decode,dynamic:gsub('EXEC','INPUT'),'test-session'))
print('10 mailbox framing contracts passed; no game or filesystem execution implied.')
